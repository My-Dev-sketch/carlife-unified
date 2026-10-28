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
  fullMapNavigation,
  wazeTrafficMap,
  nowPlayingMusic,
  phoneDialer,
  carSettingsAndLogs,
}

/// iOS 18 CarPlay Dashboard UI (`lib/features/carplay_dashboard/`) optimized for landscape car screens
/// (Toyota Corolla 1920x720 / 1280x720 and BYD Qin Plus 1920x1080).
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

  // Default coordinates (Erbil / configurable via quick destinations)
  final LatLng _currentLocation = const LatLng(36.1901, 44.0091);
  LatLng _destination = const LatLng(36.2063, 44.0088);
  NavigationRouteResult? _activeRoute;
  int _currentStepIndex = 0;
  bool _wazeOverlayMode = false;

  // Now Playing state (synced with iOS MediaPlayer.framework + CarLife CMD_MEDIA_INFO)
  String _songTitle = 'Starboy (iPhone 15 Pro Max)';
  String _songArtist = 'The Weeknd';
  String _songAlbum = 'Apple Music / Spotify Lossless';
  bool _isPlaying = true;
  int _songProgressMs = 42000;
  final int _songDurationMs = 230000;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  String _dialedNumber = '';

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
      if (t.isNotEmpty && t != _songTitle) {
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
    final step = route.steps[_currentStepIndex.clamp(0, route.steps.length - 1)];
    final hudInfo = ZeroKeyNavigationService.toCarLifeHudInfo(step);
    widget.session.sendNavigationTurn(
      action: 1,
      info: hudInfo,
      totalDistance: route.totalDistanceMeters,
    );
  }

  void _selectQuickDestination(String label, LatLng target) {
    setState(() {
      _destination = target;
    });
    _loadInitialRoute();
    try {
      _mapController.move(target, 14.0);
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0B0F19),
            Color(0xFF131B2E),
            Color(0xFF090D16),
          ],
        ),
      ),
      child: Row(
        children: [
          _buildCarPlayDock(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: _buildMainStage(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarPlayDock() {
    final timeStr =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    return Container(
      width: 84,
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF182238).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            timeStr,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi, size: 12, color: Color(0xFF34D399)),
              const SizedBox(width: 4),
              Text(
                widget.session.projecting ? '60FPS' : 'READY',
                style: const TextStyle(
                  color: Color(0xFF34D399),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 18),
          _dockIcon(
            icon: CupertinoIcons.square_split_2x1_fill,
            label: 'Split',
            tab: CarPlayActiveTab.dashboardSplit,
            activeColor: const Color(0xFF38BDF8),
          ),
          _dockIcon(
            icon: CupertinoIcons.location_north_line_fill,
            label: 'Maps',
            tab: CarPlayActiveTab.fullMapNavigation,
            activeColor: const Color(0xFF34D399),
          ),
          _dockIcon(
            icon: CupertinoIcons.car_detailed,
            label: 'Waze',
            tab: CarPlayActiveTab.wazeTrafficMap,
            activeColor: const Color(0xFFFB923C),
          ),
          _dockIcon(
            icon: CupertinoIcons.music_note_2,
            label: 'Music',
            tab: CarPlayActiveTab.nowPlayingMusic,
            activeColor: const Color(0xFFF43F5E),
          ),
          _dockIcon(
            icon: CupertinoIcons.phone_fill,
            label: 'Phone',
            tab: CarPlayActiveTab.phoneDialer,
            activeColor: const Color(0xFF22C55E),
          ),
          const Spacer(),
          _dockIcon(
            icon: CupertinoIcons.slider_horizontal_3,
            label: 'CarLife',
            tab: CarPlayActiveTab.carSettingsAndLogs,
            activeColor: const Color(0xFFA78BFA),
          ),
        ],
      ),
    );
  }

  Widget _dockIcon({
    required IconData icon,
    required String label,
    required CarPlayActiveTab tab,
    required Color activeColor,
  }) {
    final selected = _activeTab == tab;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _activeTab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 8),
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
                size: 24,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
          children: [
            Expanded(
              flex: 6,
              child: _buildMapCard(showControls: false),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  Expanded(flex: 5, child: _buildTurnBannerCard()),
                  const SizedBox(height: 12),
                  Expanded(flex: 6, child: _buildNowPlayingCard(compact: true)),
                ],
              ),
            ),
          ],
        );
      case CarPlayActiveTab.fullMapNavigation:
        return _buildMapCard(showControls: true);
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

  Widget _buildMapCard({required bool showControls}) {
    final routePoints = _activeRoute?.polyline ?? [_currentLocation, _destination];
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 14.0,
              onTap: (tapPos, latLng) {
                _selectQuickDestination('Pinned Car Touch Target', latLng);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _wazeOverlayMode
                    ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                    : 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.mydevsketch.ios_carlife_sender',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: routePoints,
                    strokeWidth: 6.0,
                    color: _wazeOverlayMode
                        ? const Color(0xFFFB923C)
                        : const Color(0xFF38BDF8),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(
                        Icons.navigation,
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
                      Icons.location_on,
                      color: Color(0xFFF43F5E),
                      size: 40,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              children: [
                _mapChip(
                  icon: Icons.bolt,
                  label: _wazeOverlayMode ? 'Waze Daylight Style' : 'CarPlay Dark OSRM',
                  onTap: () => setState(() => _wazeOverlayMode = !_wazeOverlayMode),
                ),
                const SizedBox(width: 8),
                _mapChip(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  onTap: () => _selectQuickDestination(
                    'Home',
                    const LatLng(36.2063, 44.0088),
                  ),
                ),
                const SizedBox(width: 8),
                _mapChip(
                  icon: Icons.work_rounded,
                  label: 'Work',
                  onTap: () => _selectQuickDestination(
                    'Work',
                    const LatLng(36.1833, 43.9667),
                  ),
                ),
                const Spacer(),
                if (showControls)
                  _mapChip(
                    icon: Icons.speed,
                    label: 'Send HUD Turn',
                    onTap: () {
                      final steps = _activeRoute?.steps ?? const [];
                      if (steps.isNotEmpty) {
                        setState(() {
                          _currentStepIndex =
                              (_currentStepIndex + 1) % steps.length;
                        });
                        _pushHudManeuver();
                      }
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF0F172A).withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
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
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTurnBannerCard() {
    final steps = _activeRoute?.steps ?? const [];
    final currentStep = steps.isNotEmpty
        ? steps[_currentStepIndex.clamp(0, steps.length - 1)]
        : const TurnByTurnStep(
            instruction: 'Turn right onto Express Ring Road',
            roadName: 'Express Ring Road',
            distanceMeters: 450,
            durationSeconds: 45,
            carLifeManeuver: 4,
            location: LatLng(36.1901, 44.0091),
          );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF064E3B).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF34D399).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              CupertinoIcons.arrow_turn_up_right,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${currentStep.distanceMeters} m • HUD Sync ON',
                  style: const TextStyle(
                    color: Color(0xFFA7F3D0),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  currentStep.instruction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Next Turn / Test Corolla & BYD HUD',
            onPressed: () {
              if (steps.isNotEmpty) {
                setState(() {
                  _currentStepIndex = (_currentStepIndex + 1) % steps.length;
                });
                _pushHudManeuver();
              }
            },
            icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildWazeIntegrationCard() {
    final wazeDeepLink = ZeroKeyNavigationService.buildWazeDeepLink(_destination);
    final wazeEmbedUrl =
        ZeroKeyNavigationService.buildWazeLiveEmbedUrl(_currentLocation);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFB923C).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                CupertinoIcons.car_detailed,
                color: Color(0xFFFB923C),
                size: 28,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Waze Zero-Key Integration (iPhone 15 Pro Max + BYD DiLink + Toyota Corolla)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFB923C),
                  foregroundColor: Colors.black,
                ),
                onPressed: widget.onTriggerBroadcastPicker,
                icon: const Icon(Icons.screen_share_rounded, size: 18),
                label: const Text('Mirror Full iPhone Waze (ReplayKit)'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '• Deep-Link URI: $wazeDeepLink\n'
            '• Live Traffic Embed: $wazeEmbedUrl\n'
            '• On Toyota Corolla: Tap "Switch to Waze Map Style" below for 100% car-touchscreen control, or tap "Mirror Full iPhone Waze" to stream native iOS Waze at 60fps.\n'
            '• On BYD Qin Plus: Use the BYD Receiver Split-Screen button to run native DiLink Waze side-by-side with iPhone CarPlay!',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _buildMapCard(showControls: true),
          ),
        ],
      ),
    );
  }

  Widget _buildNowPlayingCard({required bool compact}) {
    final progress = (_songProgressMs / _songDurationMs).clamp(0.0, 1.0);
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.92),
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
                width: compact ? 48 : 72,
                height: compact ? 48 : 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF43F5E), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  CupertinoIcons.music_note_2,
                  color: Colors.white,
                  size: 28,
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
              Chip(
                backgroundColor: widget.soundOverBluetooth
                    ? const Color(0xFF1D4ED8)
                    : const Color(0xFF047857),
                label: Text(
                  widget.soundOverBluetooth ? 'BT A2DP Audio' : 'CarLife PCM 9240',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF43F5E)),
            borderRadius: BorderRadius.circular(8),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: () {
                  setState(() => _songProgressMs = 0);
                  widget.session.sendSongPosition(0);
                },
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
                    count: 1,
                    id: _songTitle,
                  );
                },
                icon: Icon(
                  _isPlaying
                      ? CupertinoIcons.pause_circle_fill
                      : CupertinoIcons.play_circle_fill,
                  color: Colors.white,
                  size: compact ? 36 : 48,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _songTitle = _songTitle.contains('Starboy')
                        ? 'Midnight City (CarPlay Mix)'
                        : 'Starboy (iPhone 15 Pro Max)';
                    _songArtist = _songTitle.contains('Midnight')
                        ? 'M83'
                        : 'The Weeknd';
                    _songProgressMs = 0;
                  });
                  widget.session.sendSong(
                    title: _songTitle,
                    artist: _songArtist,
                    album: _songAlbum,
                    durationMs: _songDurationMs,
                    count: 1,
                    id: _songTitle,
                  );
                },
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
        color: const Color(0xFF1E293B).withValues(alpha: 0.92),
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
                    backgroundColor: const Color(0xFF334155),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Projection & Audio Modes:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              FilterChip(
                selected: widget.videoBridge.currentTier ==
                    ProjectionModeTier.tier1HybridCarPlayAndReplayKit,
                label: const Text('Tier 1: Hybrid 60fps + ReplayKit'),
                onSelected: (_) async {
                  await widget.videoBridge.setProjectionTier(
                    ProjectionModeTier.tier1HybridCarPlayAndReplayKit,
                  );
                  if (mounted) setState(() {});
                },
              ),
              FilterChip(
                selected: widget.videoBridge.currentTier ==
                    ProjectionModeTier.tier2PureInteractiveDashboard,
                label: const Text('Tier 2: 100% Touch CarPlay UI'),
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
                label: const Text('Tier 3: Full iPhone Mirror'),
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
          const Divider(color: Colors.white24, height: 18),
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
