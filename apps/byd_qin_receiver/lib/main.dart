import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:carlife_protocol/carlife_protocol.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const BydQinReceiverApp());
}

class BydQinReceiverApp extends StatelessWidget {
  const BydQinReceiverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BYD Qin Plus CarLife 60fps Receiver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const BydReceiverScreen(),
    );
  }
}

class BydReceiverScreen extends StatefulWidget {
  const BydReceiverScreen({super.key});

  @override
  State<BydReceiverScreen> createState() => _BydReceiverScreenState();
}

class _BydReceiverScreenState extends State<BydReceiverScreen> {
  static const MethodChannel _decoderChannel =
      MethodChannel('com.mydevsketch.byd_qin_receiver/decoder');

  final TextEditingController _manualIpCtrl =
      TextEditingController(text: '172.20.10.1');

  int? _textureId;
  RawDatagramSocket? _udpListener;
  Timer? _probeTimer;
  CarLifeReceiverSession? _receiverSession;

  String _status = 'Listening for iPhone 15 Pro Max on UDP 7999 / Hotspot...';
  String _connectedPhoneIp = '';
  int _framesReceived = 0;
  int _fpsMeasured = 0;
  int _framesInCurrentSecond = 0;
  Timer? _fpsTimer;

  // Live HUD & Now Playing Metadata received over CarLife CMD 7240
  String _songTitle = 'Waiting for iPhone Media...';
  String _songArtist = 'Connect iPhone Hotspot or Wi-Fi';
  String _hudRoad = '';
  int _hudMeters = 0;
  bool _showOverlayBar = true;

  @override
  void initState() {
    super.initState();
    _initHardwareSurface();
    _startAutoDiscovery();
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _fpsMeasured = _framesInCurrentSecond;
        _framesInCurrentSecond = 0;
      });
    });
  }

  Future<void> _initHardwareSurface() async {
    try {
      final texId = await _decoderChannel.invokeMethod<int>(
        'initHardwareSurface',
        {'width': 1920, 'height': 1080},
      );
      if (mounted) {
        setState(() => _textureId = texId);
      }
    } on MissingPluginException {
      // Running in widget tests
    } catch (e) {
      _updateStatus('Surface init warning: $e');
    }
  }

  Future<void> _startAutoDiscovery() async {
    try {
      _udpListener = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        CarLifeProtocol.discoveryPort,
        reuseAddress: true,
      );
      _udpListener!.broadcastEnabled = true;
      _udpListener!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _udpListener?.receive();
          if (dg == null) return;
          final msg = utf8.decode(dg.data, allowMalformed: true);
          if (msg.contains('CarlifeHost') || msg.contains('carlifehost')) {
            final ip = dg.address.address;
            if (_receiverSession?.connected != true) {
              _connectToIphone(ip);
            }
          }
        }
      });
    } catch (_) {}

    // Also actively probe UDP 8999 for iPhone Personal Hotspot gateway (172.20.10.1) & subnet broadcast
    _probeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_receiverSession?.connected == true) return;
      final probePayload = utf8.encode('{"carlifehost":"byd_qin_plus"}');
      for (final target in [
        '172.20.10.1',
        '192.168.43.1',
        '255.255.255.255',
      ]) {
        try {
          _udpListener?.send(
            probePayload,
            InternetAddress(target),
            CarLifeProtocol.helloPort,
          );
        } catch (_) {}
      }
    });
  }

  Future<void> _connectToIphone(String ip) async {
    if (ip.trim().isEmpty) return;
    await _receiverSession?.stop();
    setState(() {
      _connectedPhoneIp = ip.trim();
      _manualIpCtrl.text = _connectedPhoneIp;
      _status = 'Dialing iPhone 15 Pro Max at $_connectedPhoneIp:7240...';
    });

    final link = WifiClientChannelLink(
      host: _connectedPhoneIp,
      ports: CarLifeProtocol.defaultPorts,
    );
    final session = CarLifeReceiverSession(
      link: link,
      targetWidth: 1920,
      targetHeight: 1080,
      targetFps: 60,
    );

    session.onStatus = _updateStatus;
    session.onVideoNal = (Uint8List h264AnnexB, int timestamp) {
      _framesReceived++;
      _framesInCurrentSecond++;
      try {
        _decoderChannel.invokeMethod<void>('feedH264Nal', {
          'nal': h264AnnexB,
          'ptsUs': timestamp * 1000000,
        });
      } catch (_) {}
      if (_framesReceived == 1 && mounted) {
        setState(() {});
      }
    };
    session.onMediaPcm = (Uint8List pcm) {
      try {
        _decoderChannel.invokeMethod<void>('feedPcmAudio', {'pcm': pcm});
      } catch (_) {}
    };
    session.onSongMetadata = (title, artist, album, durationMs) {
      if (!mounted) return;
      setState(() {
        _songTitle = title.isEmpty ? 'iPhone Audio' : title;
        _songArtist = artist;
      });
    };
    session.onNavigationHud = (turnCode, road, remainingMeters) {
      if (!mounted) return;
      setState(() {
        _hudRoad = road;
        _hudMeters = remainingMeters;
      });
    };

    _receiverSession = session;
    await session.start();
  }

  void _updateStatus(String msg) {
    if (!mounted) return;
    setState(() => _status = msg);
  }

  Future<void> _openNativeBydWazeSplitScreen() async {
    try {
      await _decoderChannel.invokeMethod<bool>('launchBydWazeSplitScreen', {
        'lat': 36.2063,
        'lon': 44.0088,
      });
    } catch (_) {}
  }

  Future<void> _enterPip() async {
    try {
      await _decoderChannel.invokeMethod<bool>('enterPipMode');
    } catch (_) {}
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    _probeTimer?.cancel();
    _udpListener?.close();
    _receiverSession?.stop();
    _manualIpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isStreaming =
        _receiverSession?.connected == true && _framesReceived > 0;
    return Scaffold(
      backgroundColor: const Color(0xFF060911),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) {
              _receiverSession?.sendTouch(
                action: CarTouch.down,
                localX: d.localPosition.dx,
                localY: d.localPosition.dy,
                viewWidth: w,
                viewHeight: h,
              );
            },
            onPanUpdate: (d) {
              _receiverSession?.sendTouch(
                action: CarTouch.move,
                localX: d.localPosition.dx,
                localY: d.localPosition.dy,
                viewWidth: w,
                viewHeight: h,
              );
            },
            onPanEnd: (d) {
              _receiverSession?.sendTouch(
                action: CarTouch.up,
                localX: 0,
                localY: 0,
                viewWidth: w,
                viewHeight: h,
              );
            },
            onTapUp: (d) {
              _receiverSession?.sendTouch(
                action: CarTouch.up,
                localX: d.localPosition.dx,
                localY: d.localPosition.dy,
                viewWidth: w,
                viewHeight: h,
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_textureId != null && isStreaming)
                  Texture(textureId: _textureId!)
                else
                  _buildDiscoveryLandingView(),
                if (_hudRoad.isNotEmpty) _buildBydHudOverlay(),
                if (_showOverlayBar) _buildTopDiLinkControlBar(),
                Positioned(
                  bottom: 14,
                  right: 14,
                  child: FloatingActionButton.small(
                    backgroundColor:
                        const Color(0xFF1E293B).withValues(alpha: 0.85),
                    onPressed: () =>
                        setState(() => _showOverlayBar = !_showOverlayBar),
                    child: Icon(
                      _showOverlayBar
                          ? CupertinoIcons.eye_slash_fill
                          : CupertinoIcons.eye_fill,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopDiLinkControlBar() {
    return Positioned(
      top: 12,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.car_detailed,
              color: Color(0xFF38BDF8),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'BYD Qin Plus DiLink • $_status • $_fpsMeasured FPS ($_framesReceived frames)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFB923C),
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: _openNativeBydWazeSplitScreen,
              icon: const Icon(Icons.map_rounded, size: 16),
              label: const Text(
                'Open BYD Waze Split-Screen',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _enterPip,
              icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 16),
              label: const Text('PiP Mode', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Request Fresh Keyframe',
              onPressed: () => _receiverSession?.requestKeyframe(),
              icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBydHudOverlay() {
    return Positioned(
      top: 74,
      left: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF064E3B).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF34D399)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.arrow_turn_up_right,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              '$_hudMeters m → $_hudRoad',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryLandingView() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680),
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.wifi_exclamationmark,
              color: Color(0xFF38BDF8),
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              'BYD Qin Plus • Wireless CarPlay / CarLife 60fps Receiver',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF34D399), fontSize: 14),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualIpCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText:
                          'iPhone 15 Pro Max Hotspot / Wi-Fi IP (Default: 172.20.10.1)',
                      filled: true,
                      fillColor: const Color(0xFF1F2937),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                  ),
                  onPressed: () => _connectToIphone(_manualIpCtrl.text),
                  icon: const Icon(Icons.link_rounded),
                  label: const Text(
                    'Connect Now',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  CupertinoIcons.music_note_2,
                  color: Colors.white70,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$_songTitle — $_songArtist',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
