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

  String _status =
      'Auto-detecting Phone Hotspot (POCO F7 / Android / iPhone) on Wi-Fi...';
  String _connectedPhoneIp = '';
  String _detectedGatewayIp = '';
  String _detectedLocalIp = '';
  bool _dialingInProgress = false;
  int _framesReceived = 0;
  int _fpsMeasured = 0;
  int _framesInCurrentSecond = 0;
  Timer? _fpsTimer;

  // Live HUD & Now Playing Metadata received over CarLife CMD 7240
  String _songTitle = 'Waiting for Phone Media...';
  String _songArtist = 'Connect Phone Hotspot + Bluetooth to BYD';
  bool _showOverlayBar = false;

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
            if (_receiverSession?.connected != true && !_dialingInProgress) {
              _connectToIphone(ip);
            }
          }
        }
      });
    } catch (_) {}

    // Immediately inspect Wi-Fi gateway and start 2-second auto-connect loop
    _probeGatewayAndConnect();
    _probeTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _probeGatewayAndConnect();
    });
  }

  Future<void> _probeGatewayAndConnect() async {
    if (_receiverSession?.connected == true || _dialingInProgress) return;

    String gatewayIp = '';
    String broadcastIp = '255.255.255.255';
    try {
      final info = await _decoderChannel
          .invokeMapMethod<String, String>('getWifiGatewayInfo');
      if (info != null) {
        gatewayIp = (info['gatewayIp'] ?? '').trim();
        broadcastIp = (info['broadcastIp'] ?? '255.255.255.255').trim();
        final localIp = (info['localIp'] ?? '').trim();
        if (mounted &&
            (gatewayIp != _detectedGatewayIp || localIp != _detectedLocalIp)) {
          setState(() {
            _detectedGatewayIp = gatewayIp;
            _detectedLocalIp = localIp;
            if (gatewayIp.isNotEmpty) {
              _manualIpCtrl.text = gatewayIp;
            }
          });
        }
      }
    } catch (_) {}

    final probePayload = utf8.encode('{"carlifehost":"byd_qin_plus"}');
    final targets = <String>{
      if (gatewayIp.isNotEmpty) gatewayIp,
      if (broadcastIp.isNotEmpty) broadcastIp,
      '172.20.10.1',
      '192.168.43.1',
      '255.255.255.255',
    };
    for (final target in targets) {
      try {
        _udpListener?.send(
          probePayload,
          InternetAddress(target),
          CarLifeProtocol.helloPort,
        );
      } catch (_) {}
    }

    // Direct TCP auto-connect to the detected Phone Hotspot Gateway (POCO F7 10.x.x.x or iPhone 172.20.10.1)
    if (gatewayIp.isNotEmpty &&
        _receiverSession?.connected != true &&
        !_dialingInProgress) {
      await _connectToIphone(gatewayIp);
    }
  }

  Future<void> _connectToIphone(String ip) async {
    final targetIp = ip.trim();
    if (targetIp.isEmpty || _dialingInProgress) return;
    _dialingInProgress = true;
    try {
      await _receiverSession?.stop();
      if (mounted) {
        setState(() {
          _connectedPhoneIp = targetIp;
          _manualIpCtrl.text = _connectedPhoneIp;
          _status = 'Connecting to Phone at $_connectedPhoneIp:7240...';
        });
      }

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

      session.onStatus = (msg) {
        _updateStatus(msg);
        if (session.negotiatedStreamWidth > 0 &&
            session.negotiatedStreamHeight > 0) {
          try {
            _decoderChannel.invokeMethod<void>('updateSurfaceSize', {
              'width': session.negotiatedStreamWidth,
              'height': session.negotiatedStreamHeight,
            });
          } catch (_) {}
        }
      };
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
          setState(() {
            _showOverlayBar = false;
          });
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
          _songTitle = title.isEmpty ? 'Phone Audio' : title;
          _songArtist = artist;
        });
      };
      session.onNavigationHud = (turnCode, road, remainingMeters) {
        if (!mounted) return;
        setState(() {
          _status = 'HUD: ${remainingMeters}m → $road';
        });
      };

      _receiverSession = session;
      await session.start();
    } finally {
      _dialingInProgress = false;
    }
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
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_textureId != null && isStreaming)
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (e) {
                      _receiverSession?.sendTouch(
                        action: CarTouch.down,
                        localX: e.localPosition.dx,
                        localY: e.localPosition.dy,
                        viewWidth: w,
                        viewHeight: h,
                      );
                    },
                    onPointerMove: (e) {
                      _receiverSession?.sendTouch(
                        action: CarTouch.move,
                        localX: e.localPosition.dx,
                        localY: e.localPosition.dy,
                        viewWidth: w,
                        viewHeight: h,
                      );
                    },
                    onPointerUp: (e) {
                      _receiverSession?.sendTouch(
                        action: CarTouch.up,
                        localX: e.localPosition.dx,
                        localY: e.localPosition.dy,
                        viewWidth: w,
                        viewHeight: h,
                      );
                    },
                    onPointerCancel: (e) {
                      _receiverSession?.sendTouch(
                        action: CarTouch.up,
                        localX: e.localPosition.dx,
                        localY: e.localPosition.dy,
                        viewWidth: w,
                        viewHeight: h,
                      );
                    },
                    child: SizedBox.expand(
                      child: Texture(
                        textureId: _textureId!,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                )
              else
                _buildDiscoveryLandingView(),
              if (_showOverlayBar) _buildTopDiLinkControlBar(),
              Positioned(
                bottom: 10,
                right: 10,
                child: Material(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () =>
                        setState(() => _showOverlayBar = !_showOverlayBar),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showOverlayBar
                                ? CupertinoIcons.xmark_circle_fill
                                : CupertinoIcons.slider_horizontal_3,
                            color: const Color(0xFF38BDF8),
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isStreaming ? '${_fpsMeasured}fps' : 'Menu',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
          color: const Color(0xFF0F172A).withValues(alpha: 0.92),
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
                'BYD Waze Split-Screen',
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
              CupertinoIcons.wifi,
              color: Color(0xFF38BDF8),
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              'BYD Qin Plus • Wireless Android Auto & CarPlay Receiver',
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
            if (_detectedGatewayIp.isNotEmpty || _detectedLocalIp.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'BYD IP: ${_detectedLocalIp.isEmpty ? "detecting..." : _detectedLocalIp}  •  Phone Hotspot Gateway: ${_detectedGatewayIp.isEmpty ? "detecting..." : _detectedGatewayIp}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualIpCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText:
                          'Phone Hotspot IP (Auto-detected from POCO F7 / iPhone)',
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
