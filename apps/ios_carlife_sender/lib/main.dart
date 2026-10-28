import 'dart:io';
import 'package:carlife_protocol/carlife_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'features/carplay_dashboard/carplay_dashboard_view.dart';
import 'features/touch_dispatcher/touch_dispatcher.dart';
import 'features/video_pipeline/ios_video_pipeline_bridge.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const IosCarLifeSenderApp());
}

class IosCarLifeSenderApp extends StatefulWidget {
  const IosCarLifeSenderApp({super.key});

  @override
  State<IosCarLifeSenderApp> createState() => _IosCarLifeSenderAppState();
}

class _IosCarLifeSenderAppState extends State<IosCarLifeSenderApp> {
  final GlobalKey _dashboardRepaintKey = GlobalKey();
  final CarLifeTouchDispatcher _touchDispatcher = CarLifeTouchDispatcher();
  final CarDiscoveryService _discoveryService = CarDiscoveryService();
  final List<String> _logs = [];

  late final WifiServerChannelLink _wifiServerLink;
  late final CarLifeSession _session;
  late final IosVideoPipelineBridge _videoBridge;

  bool _soundOverBluetooth = true;

  @override
  void initState() {
    super.initState();
    _wifiServerLink = WifiServerChannelLink(ports: CarLifeProtocol.defaultPorts);
    _session = CarLifeSession(
      link: _wifiServerLink,
      carName: 'iPhone 15 Pro Max',
    );
    _videoBridge = IosVideoPipelineBridge(
      onCodecConfig: (spsPps) => _session.videoConfig(spsPps),
      onEncodedNal: (nal, isKey) => _session.videoFrame(nal, key: isKey),
      onLog: _appendLog,
    );

    _session.onLog = _appendLog;
    _session.onVideoConfig = (plan) {
      _appendLog('Starting 60fps VideoToolbox stream: $plan');
      _videoBridge.startEncoder(
        width: plan.streamWidth,
        height: plan.streamHeight,
        fps: plan.fps,
        bitrate: plan.bitrate,
        repaintBoundaryKey: _dashboardRepaintKey,
      );
    };
    _session.onNeedKeyframe = () => _videoBridge.requestKeyframe();
    _session.onTouch = (CarTouch touch) {
      final box = _dashboardRepaintKey.currentContext?.findRenderObject()
          as RenderBox?;
      if (box != null && box.hasSize) {
        final topLeft = box.localToGlobal(Offset.zero);
        _touchDispatcher.dispatch(
          touch: touch,
          streamWidth: _session.streamWidth,
          streamHeight: _session.streamHeight,
          dashboardRect: topLeft & box.size,
        );
      }
    };

    _bootServices();
  }

  void _appendLog(String line) {
    if (!mounted) return;
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _logs.add('[$ts] $line');
      if (_logs.length > 250) {
        _logs.removeAt(0);
      }
    });
  }

  Future<void> _bootServices() async {
    await _session.start();
    await _discoveryService.startPhoneBeacon(
      targetAddresses: () => <InternetAddress>[],
      onCarDiscovered: (ip, port, msg) {
        _appendLog('Car discovered at ${ip.address}:$port -> $msg');
      },
      onLog: _appendLog,
    );
  }

  @override
  void dispose() {
    _videoBridge.stop();
    _discoveryService.stop();
    _session.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iOS CarLife 60fps Sender',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: RepaintBoundary(
            key: _dashboardRepaintKey,
            child: CarPlayDashboardView(
              session: _session,
              videoBridge: _videoBridge,
              logs: _logs,
              soundOverBluetooth: _soundOverBluetooth,
              onSoundModeChanged: (val) {
                setState(() => _soundOverBluetooth = val);
                _appendLog(
                  val
                      ? 'Audio routed over Car Bluetooth A2DP + CarLife Metadata'
                      : 'Audio routed over CarLife TCP Media Port 9240',
                );
              },
              onTriggerBroadcastPicker: () {
                _videoBridge.showBroadcastPicker();
              },
            ),
          ),
        ),
      ),
    );
  }
}
