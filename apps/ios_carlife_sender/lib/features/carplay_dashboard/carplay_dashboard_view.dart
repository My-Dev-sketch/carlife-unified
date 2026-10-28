import 'dart:async';
import 'package:carlife_protocol/carlife_protocol.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../navigation/zero_key_navigation_service.dart';
import '../video_pipeline/ios_video_pipeline_bridge.dart';

enum CarPlayActiveTab {
  dashboardSplit,
  appLauncherGrid,
  fullMapNavigation,
  wazeTrafficMap,
  nowPlayingMusic,
  phoneDialer,
  carSettingsAndLogs,
}

class _MusicTrackItem {
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final List<Color> gradient;

  const _MusicTrackItem({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.gradient,
  });
}

/// Real Android Auto Coolwalk + `ft-app` (`CarScreen.kt`) Automotive UI (`lib/features/carplay_dashboard/`)
/// optimized for full-screen 16:9 / ultra-wide landscape car displays:
/// - BYD Qin Plus DiLink (1920x1080 @ 60fps)
/// - Chinese-spec Toyota Corolla Hybrid (1920x720 / 1280x720 @ 60fps)
class CarPlayDashboardView extends StatefulWidget {
  final CarLifeSession session;
  final IosVideoPipelineBridge videoBridge;
  final List<String> logs;
  final bool soundOverBluetooth;
  final ValueChanged<bool> onSoundModeChanged;
  final VoidCallback onTriggerBroadcastPicker;

  const CarPlayDashboardView({
    super.key,
    required this.session,
    required this.videoBridge,
    required this.logs,
    required this.soundOverBluetooth,
    required this.onSoundModeChanged,
    required this.onTriggerBroadcastPicker,
  });

  @override
  State<CarPlayDashboardView> createState() => _CarPlayDashboardViewState();
}

class _CarPlayDashboardViewState extends State<CarPlayDashboardView> {
  CarPlayActiveTab _activeTab = CarPlayActiveTab.dashboardSplit;
  final ZeroKeyNavigationService _navService = ZeroKeyNavigationService();
  final MapController _mapController = MapController();

  // Default coordinates (configurable via quick destinations or map tap)
  final LatLng _currentLocation = const LatLng(36.1901, 44.0091);
  LatLng _destination = const LatLng(36.2063, 44.0088);
  String _destinationLabel = 'Home • Empire World';
  double _mapZoom = 14.5;
  NavigationRouteResult? _activeRoute;
  int _currentStepIndex = 0;
  bool _darkMapStyle = true;

  static const List<_MusicTrackItem> _playlist = [
    _MusicTrackItem(
      title: 'Starboy (Dolby Car Mix)',
      artist: 'The Weeknd, Daft Punk',
      album: 'Starboy • Lossless A2DP',
      durationMs: 230000,
      gradient: [Color(0xFFE11D48), Color(0xFF7C3AED)],
    ),
    _MusicTrackItem(
      title: 'Midnight City (Night Drive)',
      artist: 'M83',
      album: 'Hurry Up, We\'re Dreaming',
      durationMs: 243000,
      gradient: [Color(0xFF2563EB), Color(0xFF06B6D4)],
    ),
    _MusicTrackItem(
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      album: 'After Hours • CarLife Hi-Fi',
      durationMs: 200000,
      gradient: [Color(0xFFD97706), Color(0xFFDC2626)],
    ),
    _MusicTrackItem(
      title: 'Nightcall ( Highway Cruise )',
      artist: 'Kavinsky',
      album: 'OutRun',
      durationMs: 258000,
      gradient: [Color(0xFF4F46E5), Color(0xFFEC4899)],
    ),
  ];

  int _trackIndex = 0;
  String _songTitle = _playlist[0].title;
  String _songArtist = _playlist[0].artist;
  String _songAlbum = _playlist[0].album;
  int _songDurationMs = _playlist[0].durationMs;
  bool _isPlaying = true;
  int _songProgressMs = 38000;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  String _dialedNumber = '';

  // Android Auto Dark Map color filter matrix (transforms standard OpenStreetMap tiles into
  // a rich dark-navy automotive navigation map with zero watermarks and zero API keys)
  static const ColorFilter _androidAutoDarkMapFilter = ColorFilter.matrix(<double>[
    -0.82, 0.0, 0.0, 0.0, 215.0,
    0.0, -0.78, 0.0, 0.0, 225.0,
    0.0, 0.0, -0.65, 0.0, 245.0,
    0.0, 0.0, 0.0, 1.0, 0.0,
  ]);

  @override
  void initState() {
    super.initState();
    _loadInitialRoute();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
        if (_isPlaying) {
          _songProgressMs = (_songProgressMs + 1000) % _songDurationMs;
        }
      });
      widget.session.sendSongPosition(_songProgressMs);
      _syncNativeNowPlaying();
    });
  }

  Future<void> _syncNativeNowPlaying() async {
    final info = await widget.videoBridge.fetchNowPlaying();
    if (info != null && mounted) {
      final t = (info['title'] as String? ?? '').trim();
      final a = (info['artist'] as String? ?? '').trim();
      final al = (info['album'] as String? ?? '').trim();
      if (t.isNotEmpty &&
          !t.contains('Android Auto Coolwalk') &&
          !t.contains('CarPlay 60fps') &&
          t != _songTitle) {
        setState(() {
          _songTitle = t;
          _songArtist = a.isEmpty ? 'Unknown Artist' : a;
          _songAlbum = al;
        });
        widget.session.sendSong(
          title: _songTitle,
          artist: _songArtist,
          album: _songAlbum,
          durationMs: _songDurationMs,
          count: 1,
          id: _songTitle,
        );
      }
    }
  }

  void _selectTrack(int index) {
    final i = index % _playlist.length;
    final item = _playlist[i];
    setState(() {
      _trackIndex = i;
      _songTitle = item.title;
      _songArtist = item.artist;
      _songAlbum = item.album;
      _songDurationMs = item.durationMs;
      _songProgressMs = 0;
      _isPlaying = true;
    });
    widget.session.sendSong(
      title: _songTitle,
      artist: _songArtist,
      album: _songAlbum,
      durationMs: _songDurationMs,
      count: _playlist.length,
      id: _songTitle,
    );
  }

  Future<void> _loadInitialRoute() async {
    final route = await _navService.calculateRoute(
      origin: _currentLocation,
      destination: _destination,
    );
    if (!mounted) return;
    setState(() {
      _activeRoute = route;
      _currentStepIndex = 0;
    });
    _pushHudManeuver();
  }

  void _pushHudManeuver() {
    final route = _activeRoute;
    if (route == null || route.steps.isEmpty) return;
    final step =
        route.steps[_currentStepIndex.clamp(0, route.steps.length - 1)];
    final hudInfo = ZeroKeyNavigationService.toCarLifeHudInfo(step);
    widget.session.sendNavigationTurn(
      action: 1,
      info: hudInfo,
      totalDistance: route.totalDistanceMeters,
    );
  }

  void _selectQuickDestination(String label, LatLng target) {
    setState(() {
      _destinationLabel = label;
      _destination = target;
    });
    _loadInitialRoute();
    try {
      _mapController.move(target, _mapZoom);
    } catch (_) {}
  }

  void _zoomMap(double delta) {
    setState(() {
      _mapZoom = (_mapZoom + delta).clamp(4.0, 18.0);
    });
    try {
      _mapController.move(_mapController.camera.center, _mapZoom);
    } catch (_) {}
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF070A12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAndroidAutoCoolwalkRail(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
              child: _buildMainStage(),
            ),
          ),
        ],
      ),
    );
  }

  /// Real Android Auto Coolwalk Left Navigation Rail (`CarScreen.kt` + Coolwalk Dock).
  Widget _buildAndroidAutoCoolwalkRail() {
    final timeStr =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    return Container(
      width: 78,
      margin: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF111726),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.09),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Top Status Pill: Clock + Signal + 60FPS status
          Text(
            timeStr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF064E3B),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi, size: 10, color: Color(0xFF34D399)),
                const SizedBox(width: 3),
                Text(
                  widget.session.projecting ? '60FPS' : 'LIVE',
                  style: const TextStyle(
                    color: Color(0xFF34D399),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _railIcon(
                    icon: Icons.dashboard_rounded,
                    label: 'Split',
                    tab: CarPlayActiveTab.dashboardSplit,
                    activeColor: const Color(0xFF38BDF8),
                  ),
                  _railIcon(
                    icon: Icons.navigation_rounded,
                    label: 'Maps',
                    tab: CarPlayActiveTab.fullMapNavigation,
                    activeColor: const Color(0xFF34D399),
                  ),
                  _railIcon(
                    icon: Icons.explore_rounded,
                    label: 'Waze',
                    tab: CarPlayActiveTab.wazeTrafficMap,
                    activeColor: const Color(0xFFFB923C),
                  ),
                  _railIcon(
                    icon: Icons.music_note_rounded,
                    label: 'Music',
                    tab: CarPlayActiveTab.nowPlayingMusic,
                    activeColor: const Color(0xFFF43F5E),
                  ),
                  _railIcon(
                    icon: Icons.phone_rounded,
                    label: 'Phone',
                    tab: CarPlayActiveTab.phoneDialer,
                    activeColor: const Color(0xFF22C55E),
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 10),
          // Bottom Android Auto 9-Dot App Launcher Button
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              setState(() {
                _activeTab = _activeTab == CarPlayActiveTab.appLauncherGrid
                    ? CarPlayActiveTab.dashboardSplit
                    : CarPlayActiveTab.appLauncherGrid;
              });
            },
            child: Container(
              width: 52,
              height: 44,
              decoration: BoxDecoration(
                color: _activeTab == CarPlayActiveTab.appLauncherGrid
                    ? const Color(0xFF38BDF8)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.apps_rounded,
                color: _activeTab == CarPlayActiveTab.appLauncherGrid
                    ? Colors.black
                    : Colors.white,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _railIcon({
    required IconData icon,
    required String label,
    required CarPlayActiveTab tab,
    required Color activeColor,
  }) {
    final selected = _activeTab == tab;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _activeTab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 62,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? activeColor.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: selected
                ? Border.all(color: activeColor, width: 1.5)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: selected ? activeColor : Colors.white70,
                size: 22,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainStage() {
    switch (_activeTab) {
      case CarPlayActiveTab.dashboardSplit:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left 60%: Real Android Auto Coolwalk Map with floating Turn-by-Turn banner
            Expanded(
              flex: 60,
              child: _buildMapCard(showControls: false, showTurnOverlay: true),
            ),
            const SizedBox(width: 10),
            // Right 40%: Media Player Card + ft-app Quick Mirror / Waze / Weather Card
            Expanded(
              flex: 40,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 56,
                    child: _buildNowPlayingCard(compact: true),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    flex: 44,
                    child: _buildCoolwalkSmartShortcutsCard(),
                  ),
                ],
              ),
            ),
          ],
        );
      case CarPlayActiveTab.appLauncherGrid:
        return _buildFtAppLauncherGrid();
      case CarPlayActiveTab.fullMapNavigation:
        return _buildMapCard(showControls: true, showTurnOverlay: true);
      case CarPlayActiveTab.wazeTrafficMap:
        return _buildWazeIntegrationCard();
      case CarPlayActiveTab.nowPlayingMusic:
        return _buildNowPlayingCard(compact: false);
      case CarPlayActiveTab.phoneDialer:
        return _buildPhoneDialerCard();
      case CarPlayActiveTab.carSettingsAndLogs:
        return _buildSettingsAndDiagnosticsCard();
    }
  }

  /// `ft-app` (`CarScreen.kt`) style 2x4 Automotive Launcher Grid for 1-tap access on the car touchscreen.
  Widget _buildFtAppLauncherGrid() {
    final items = <({
      String title,
      String subtitle,
      IconData icon,
      Color color,
      VoidCallback onTap,
    })>[
      (
        title: 'Coolwalk Split',
        subtitle: 'Map + Music + HUD',
        icon: Icons.dashboard_rounded,
        color: const Color(0xFF38BDF8),
        onTap: () => setState(() => _activeTab = CarPlayActiveTab.dashboardSplit),
      ),
      (
        title: 'Maps Navigation',
        subtitle: 'Full-Screen OSRM',
        icon: Icons.navigation_rounded,
        color: const Color(0xFF10B981),
        onTap: () =>
            setState(() => _activeTab = CarPlayActiveTab.fullMapNavigation),
      ),
      (
        title: 'Mirror Phone',
        subtitle: 'Full 60fps Screen',
        icon: Icons.screen_share_rounded,
        color: const Color(0xFF6366F1),
        onTap: widget.onTriggerBroadcastPicker,
      ),
      (
        title: 'Waze Traffic',
        subtitle: 'Live Alerts & Mirror',
        icon: Icons.explore_rounded,
        color: const Color(0xFFFB923C),
        onTap: () => setState(() => _activeTab = CarPlayActiveTab.wazeTrafficMap),
      ),
      (
        title: 'Music & Audio',
        subtitle: _songTitle,
        icon: Icons.library_music_rounded,
        color: const Color(0xFFF43F5E),
        onTap: () =>
            setState(() => _activeTab = CarPlayActiveTab.nowPlayingMusic),
      ),
      (
        title: 'YouTube Video',
        subtitle: 'Launch & Mirror',
        icon: Icons.play_circle_fill_rounded,
        color: const Color(0xFFEF4444),
        onTap: () async {
          widget.onTriggerBroadcastPicker();
          await widget.videoBridge.launchExternalApp(
            packageName: 'com.google.android.youtube',
            fallbackUrl: 'https://m.youtube.com',
          );
        },
      ),
      (
        title: 'Phone Dialer',
        subtitle: 'Bluetooth Handsfree',
        icon: Icons.phone_in_talk_rounded,
        color: const Color(0xFF22C55E),
        onTap: () => setState(() => _activeTab = CarPlayActiveTab.phoneDialer),
      ),
      (
        title: 'CarLife & OEM',
        subtitle: 'Settings / Car Home',
        icon: Icons.tune_rounded,
        color: const Color(0xFFA855F7),
        onTap: () =>
            setState(() => _activeTab = CarPlayActiveTab.carSettingsAndLogs),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111726),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white12),
      ),
      child: GridView.builder(
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.55,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return Material(
            color: const Color(0xFF1A2337),
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: item.onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: item.color.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Icon(item.icon, color: item.color, size: 26),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Bottom-right Coolwalk Smart Card combining `ft-app` Mirror Phone, Native Waze, and Live Telemetry.
  Widget _buildCoolwalkSmartShortcutsCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.wb_sunny_rounded,
                      color: Color(0xFFFBBF24),
                      size: 18,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '24°C • Clear',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _destinationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: widget.onTriggerBroadcastPicker,
                  icon: const Icon(Icons.screen_share_rounded, size: 18),
                  label: const Text(
                    'Mirror Phone',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFB923C),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () async {
                    final launched = await widget.videoBridge.launchExternalApp(
                      packageName: 'com.waze',
                      fallbackUrl:
                          ZeroKeyNavigationService.buildWazeDeepLink(_destination),
                    );
                    if (!launched && mounted) {
                      setState(
                        () => _activeTab = CarPlayActiveTab.wazeTrafficMap,
                      );
                    }
                  },
                  icon: const Icon(Icons.explore_rounded, size: 18),
                  label: const Text(
                    'Open Waze',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapCard({
    required bool showControls,
    required bool showTurnOverlay,
  }) {
    final routePoints =
        _activeRoute?.polyline ?? [_currentLocation, _destination];
    final steps = _activeRoute?.steps ?? const [];
    final currentStep = steps.isNotEmpty
        ? steps[_currentStepIndex.clamp(0, steps.length - 1)]
        : const TurnByTurnStep(
            instruction: 'Continue on Express Ring Road',
            roadName: 'Express Ring Road',
            distanceMeters: 450,
            durationSeconds: 45,
            carLifeManeuver: 4,
            location: LatLng(36.1901, 44.0091),
          );

    final tileLayer = TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.mydevsketch.ios_carlife_sender',
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: _mapZoom,
              onTap: (tapPos, latLng) {
                _selectQuickDestination('Pinned Map Destination', latLng);
              },
            ),
            children: [
              if (_darkMapStyle)
                ColorFiltered(
                  colorFilter: _androidAutoDarkMapFilter,
                  child: tileLayer,
                )
              else
                tileLayer,
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routePoints,
                    strokeWidth: 7.0,
                    color: const Color(0xFF38BDF8),
                    borderStrokeWidth: 2.0,
                    borderColor: const Color(0xFF0284C7),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation,
                    width: 42,
                    height: 42,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(
                        Icons.navigation_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  Marker(
                    point: _destination,
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFFF43F5E),
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Top-left Android Auto Green Turn-by-Turn Navigation Card
          if (showTurnOverlay)
            Positioned(
              top: 10,
              left: 10,
              right: showControls ? 220 : 70,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF065F46).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF34D399).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        CupertinoIcons.arrow_turn_up_right,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${currentStep.distanceMeters} m  •  $_destinationLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFA7F3D0),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            currentStep.instruction,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Next Turn / Push to Car HUD',
                      onPressed: () {
                        if (steps.isNotEmpty) {
                          setState(() {
                            _currentStepIndex =
                                (_currentStepIndex + 1) % steps.length;
                          });
                          _pushHudManeuver();
                        }
                      },
                      icon: const Icon(
                        Icons.skip_next_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Right-side Map Controls (Dark/Day toggle + Zoom In / Out + Recenter)
          Positioned(
            right: 10,
            top: 10,
            child: Column(
              children: [
                _mapRoundButton(
                  icon: _darkMapStyle
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  tooltip: 'Toggle Dark / Day Map',
                  onTap: () => setState(() => _darkMapStyle = !_darkMapStyle),
                ),
                const SizedBox(height: 8),
                _mapRoundButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Zoom In',
                  onTap: () => _zoomMap(1.0),
                ),
                const SizedBox(height: 8),
                _mapRoundButton(
                  icon: Icons.remove_rounded,
                  tooltip: 'Zoom Out',
                  onTap: () => _zoomMap(-1.0),
                ),
                const SizedBox(height: 8),
                _mapRoundButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'Center Map',
                  onTap: () {
                    try {
                      _mapController.move(_currentLocation, 14.5);
                    } catch (_) {}
                  },
                ),
              ],
            ),
          ),

          // Bottom Quick Destination Chips Bar
          Positioned(
            bottom: 10,
            left: 10,
            right: 10,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _mapChip(
                    icon: Icons.home_rounded,
                    label: 'Home',
                    onTap: () => _selectQuickDestination(
                      'Home • Empire World',
                      const LatLng(36.2063, 44.0088),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _mapChip(
                    icon: Icons.work_rounded,
                    label: 'Work',
                    onTap: () => _selectQuickDestination(
                      'Work • Downtown Hub',
                      const LatLng(36.1833, 43.9667),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _mapChip(
                    icon: Icons.local_mall_rounded,
                    label: 'Family Mall',
                    onTap: () => _selectQuickDestination(
                      'Family Mall • 100m Rd',
                      const LatLng(36.2015, 44.0412),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _mapChip(
                    icon: Icons.flight_takeoff_rounded,
                    label: 'Airport',
                    onTap: () => _selectQuickDestination(
                      'International Airport',
                      const LatLng(36.2375, 43.9631),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _mapChip(
                    icon: Icons.ev_station_rounded,
                    label: 'BYD Fast Charge',
                    onTap: () => _selectQuickDestination(
                      'BYD DC Supercharger',
                      const LatLng(36.1950, 44.0220),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapRoundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF0F172A).withValues(alpha: 0.90),
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white24),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _mapChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF0F172A).withValues(alpha: 0.90),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF38BDF8), size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWazeIntegrationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFFB923C).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.explore_rounded,
                color: Color(0xFFFB923C),
                size: 28,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Waze Live Traffic & 60fps Full-Phone Mirroring',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFB923C),
                  foregroundColor: Colors.black,
                ),
                onPressed: () async {
                  await widget.videoBridge.launchExternalApp(
                    packageName: 'com.waze',
                    fallbackUrl:
                        ZeroKeyNavigationService.buildWazeDeepLink(_destination),
                  );
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text(
                  'Launch Native Waze',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.onTriggerBroadcastPicker,
                icon: const Icon(Icons.screen_share_rounded, size: 16),
                label: const Text('Mirror Full Screen'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _buildMapCard(showControls: true, showTurnOverlay: true),
          ),
        ],
      ),
    );
  }

  Widget _buildNowPlayingCard({required bool compact}) {
    final progress = (_songProgressMs / _songDurationMs).clamp(0.0, 1.0);
    final currentItem = _playlist[_trackIndex % _playlist.length];
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 48 : 68,
                height: compact ? 48 : 68,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: currentItem.gradient),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  CupertinoIcons.music_note_2,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _songTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 15 : 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$_songArtist • $_songAlbum',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D4ED8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.soundOverBluetooth
                        ? 'Bluetooth A2DP'
                        : 'CarLife PCM',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _playlist.length,
                itemBuilder: (context, idx) {
                  final track = _playlist[idx];
                  final active = idx == _trackIndex;
                  return ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    tileColor: active
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.transparent,
                    leading: Icon(
                      active && _isPlaying
                          ? Icons.equalizer_rounded
                          : Icons.music_note_rounded,
                      color: active ? const Color(0xFFF43F5E) : Colors.white54,
                    ),
                    title: Text(
                      track.title,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      '${track.artist} • ${track.album}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    onTap: () => _selectTrack(idx),
                  );
                },
              ),
            ),
          ],
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: progress,
              activeColor: const Color(0xFFF43F5E),
              inactiveColor: Colors.white12,
              onChanged: (v) {
                final nextMs = (v * _songDurationMs).round();
                setState(() => _songProgressMs = nextMs);
                widget.session.sendSongPosition(nextMs);
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () =>
                    _selectTrack((_trackIndex - 1 + _playlist.length) % _playlist.length),
                icon: const Icon(
                  CupertinoIcons.backward_end_fill,
                  color: Colors.white,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() => _isPlaying = !_isPlaying);
                  widget.session.sendSong(
                    title: _songTitle,
                    artist: _songArtist,
                    album: _songAlbum,
                    durationMs: _songDurationMs,
                    count: _playlist.length,
                    id: _songTitle,
                  );
                },
                icon: Icon(
                  _isPlaying
                      ? CupertinoIcons.pause_circle_fill
                      : CupertinoIcons.play_circle_fill,
                  color: Colors.white,
                  size: compact ? 38 : 48,
                ),
              ),
              IconButton(
                onPressed: () => _selectTrack(_trackIndex + 1),
                icon: const Icon(
                  CupertinoIcons.forward_end_fill,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneDialerCard() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _dialedNumber.isEmpty ? 'Enter Number' : _dialedNumber,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () {},
                      icon: const Icon(CupertinoIcons.phone_fill),
                      label: const Text('Call via Car HFP'),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () {
                        if (_dialedNumber.isNotEmpty) {
                          setState(() {
                            _dialedNumber = _dialedNumber.substring(
                              0,
                              _dialedNumber.length - 1,
                            );
                          });
                        }
                      },
                      icon: const Icon(
                        CupertinoIcons.delete_left_fill,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: GridView.builder(
              itemCount: keys.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.9,
              ),
              itemBuilder: (context, index) {
                final k = keys[index];
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => setState(() => _dialedNumber += k),
                  child: Text(
                    k,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsAndDiagnosticsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Projection & Audio:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              FilterChip(
                selected: widget.videoBridge.currentTier ==
                    ProjectionModeTier.tier1HybridCarPlayAndReplayKit,
                label: const Text('60fps Coolwalk UI'),
                onSelected: (_) async {
                  await widget.videoBridge.setProjectionTier(
                    ProjectionModeTier.tier2PureInteractiveDashboard,
                  );
                  if (mounted) setState(() {});
                },
              ),
              FilterChip(
                selected: widget.videoBridge.currentTier ==
                    ProjectionModeTier.tier3FullIphoneReplayKitMirror,
                label: const Text('Full Phone Screen Mirror'),
                onSelected: (_) async {
                  await widget.videoBridge.setProjectionTier(
                    ProjectionModeTier.tier3FullIphoneReplayKitMirror,
                  );
                  if (mounted) setState(() {});
                },
              ),
              FilterChip(
                selected: widget.soundOverBluetooth,
                label: Text(
                  widget.soundOverBluetooth
                      ? 'Audio: Car Bluetooth A2DP'
                      : 'Audio: CarLife TCP 9240',
                ),
                onSelected: widget.onSoundModeChanged,
              ),
              ElevatedButton.icon(
                onPressed: () => widget.session.goToCarHome(),
                icon: const Icon(Icons.directions_car, size: 16),
                label: const Text('Car Original Screen'),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 16),
          const Text(
            'Live Baidu CarLife Wire Protocol & UDP 7999/8999 Telemetry:',
            style: TextStyle(
              color: Color(0xFF38BDF8),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.builder(
                itemCount: widget.logs.length,
                itemBuilder: (context, idx) {
                  final line = widget.logs[widget.logs.length - 1 - idx];
                  return Text(
                    line,
                    style: const TextStyle(
                      color: Color(0xFFA7F3D0),
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
