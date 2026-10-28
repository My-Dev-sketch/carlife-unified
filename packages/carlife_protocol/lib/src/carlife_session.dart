import 'dart:async';
import 'dart:typed_data';
import 'carlife_crypto.dart';
import 'carlife_framing.dart';
import 'carlife_link.dart';
import 'carlife_protocol_constants.dart';
import 'media_and_navigation.dart';
import 'proto_lite.dart';
import 'video_feed.dart';
import 'video_plan.dart';

/// Touch event model ported from `ft-app` (`CarTouch` in `CarLifeSession.kt`).
class CarTouch {
  static const int down = 0;
  static const int up = 1;
  static const int move = 2;
  static const int pointerDown = 5;
  static const int pointerUp = 6;

  final int action;
  final int x;
  final int y;
  final int x2;
  final int y2;
  final int index;

  const CarTouch({
    required this.action,
    required this.x,
    required this.y,
    this.x2 = -1,
    this.y2 = -1,
    this.index = 0,
  });

  /// Maps stream coordinates (`streamWidth` x `streamHeight`) to logical dashboard coordinates (`targetWidth` x `targetHeight`).
  (double, double) normalize({
    required int streamWidth,
    required int streamHeight,
    required double targetWidth,
    required double targetHeight,
  }) {
    final sw = streamWidth > 0 ? streamWidth : 1280;
    final sh = streamHeight > 0 ? streamHeight : 720;
    return (
      (x / sw).clamp(0.0, 1.0) * targetWidth,
      (y / sh).clamp(0.0, 1.0) * targetHeight,
    );
  }

  @override
  String toString() =>
      'CarTouch(action=$action, x=$x, y=$y, x2=$x2, y2=$y2, index=$index)';
}

sealed class CarLifeSessionState {
  const CarLifeSessionState();
}

class CarLifeIdle extends CarLifeSessionState {
  const CarLifeIdle();
}

class CarLifeLinked extends CarLifeSessionState {
  final String via;
  const CarLifeLinked(this.via);
}

class CarLifeNegotiated extends CarLifeSessionState {
  final String via;
  final int width;
  final int height;
  final int fps;
  final int streamWidth;
  final int streamHeight;

  const CarLifeNegotiated({
    required this.via,
    required this.width,
    required this.height,
    required this.fps,
    required this.streamWidth,
    required this.streamHeight,
  });
}

class CarLifeProjecting extends CarLifeSessionState {
  final String via;
  final int width;
  final int height;
  final int fps;
  final int streamWidth;
  final int streamHeight;

  const CarLifeProjecting({
    required this.via,
    required this.width,
    required this.height,
    required this.fps,
    required this.streamWidth,
    required this.streamHeight,
  });
}

/// Complete Phone-side Baidu CarLife session state machine ported from `ft-app` (`CarLifeSession.kt`).
/// Speaks the exact handshake order expected by Chinese-spec Toyota Corolla (DesaySV CarLife)
/// and our BYD Qin Plus DiLink receiver.
class CarLifeSession {
  final CarLifeLink link;
  final String carName;

  final StreamController<CarLifeSessionState> _stateCtrl =
      StreamController<CarLifeSessionState>.broadcast();
  CarLifeSessionState _state = const CarLifeIdle();

  CarLifeSessionState get state => _state;
  Stream<CarLifeSessionState> get stateStream => _stateCtrl.stream;

  void Function(VideoPlan plan)? onVideoConfig;
  void Function()? onStopVideo;
  void Function(int fps)? onFrameRate;
  void Function()? onNeedKeyframe;
  void Function()? onVideoBack;
  void Function(int gear)? onGear;
  void Function(CarTouch touch)? onTouch;
  void Function(int keyCode)? onHardKey;
  void Function(Uint8List pcm)? onVoiceAudio;
  void Function(String mode)? onLaunchMode;
  void Function(String reason)? onClosed;
  void Function()? onPauseMedia;
  void Function(bool play)? onMusicControl;
  void Function(String logLine)? onLog;

  int width = 1280;
  int height = 720;
  int streamWidth = 1280;
  int streamHeight = 720;
  int fps = 60;
  int forcedFps = 60;
  int videoBitrate = 4000000;
  int sizeMode = VideoPlans.sizeCar;
  bool projecting = false;

  final CarLifeCrypto _crypto = CarLifeCrypto();
  late final VideoFeed _feed;
  late final MediaStream _media;

  bool _matched = false;
  bool _initSeen = false;
  bool _videoReady = false;
  bool _newVehicle = false;
  bool _carMicOn = false;
  bool _naviSubscribed = false;
  int _frames = 0;
  int _gear = -1;
  bool _musicStartSeen = false;
  bool _musicEndSeen = false;
  Timer? _videoTimer;
  Timer? _encryptProbe;
  Timer? _moduleStatusDelay;

  static const int _subscribeNavigation = 0;
  static const int _subscribeMusic = 2;
  static const int _doubleTapGapMs = 60;
  static const int _longPressMs = 800;
  static const int _videoPollMs = 50;
  static const int _quietFrames = 6;
  static const int _heartbeatCapMs = 900;

  CarLifeSession({
    required this.link,
    this.carName = 'iPhone 15 Pro Max',
  }) {
    _feed = VideoFeed(
      sendFrame: _videoPacket,
      sendEmpty: _videoEmpty,
    );
    _media = MediaStream(
      send: _mediaPacket,
      status: _moduleUpdate,
    );
  }

  void _setState(CarLifeSessionState next) {
    _state = next;
    if (!_stateCtrl.isClosed) {
      _stateCtrl.add(next);
    }
  }

  void _log(String msg) => onLog?.call('[CarLifeSession] $msg');

  Future<void> start() async {
    _log('Starting session via ${link.name}');
    await link.start(
      onMessage: _onMessage,
      onEvent: _log,
      onConnected: _linked,
      onClosed: _closed,
    );
  }

  Future<void> stop() async {
    await link.stop();
    _reset();
    _setState(const CarLifeIdle());
  }

  void _reset() {
    projecting = false;
    _gear = -1;
    _videoTimer?.cancel();
    _videoTimer = null;
    _encryptProbe?.cancel();
    _encryptProbe = null;
    _moduleStatusDelay?.cancel();
    _moduleStatusDelay = null;
    _crypto.reset();
    _matched = false;
    _carMicOn = false;
    _initSeen = false;
    _videoReady = false;
    _naviSubscribed = false;
    _feed.close();
    _media.forget();
  }

  void videoConfig(Uint8List config) => _feed.config(config);

  void videoFrame(Uint8List frame, {required bool key}) =>
      _feed.frame(frame, key);

  int _videoClock() =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) & 0xffffffff;

  void _videoPacket(Uint8List frame) {
    _frames++;
    if (_frames <= 3 || _frames % 300 == 0) {
      _log(
        'Video frame #$_frames (${frame.length}B)${_crypto.active ? " [AES]" : ""}',
      );
    }
    link.send(
      CarLifeProtocol.chVideo,
      CarLifeFraming.stream(
        CarLifeProtocol.videoData,
        _crypto.encryptOut(frame),
        timestamp: _videoClock(),
      ),
    );
  }

  void _videoEmpty(bool heartbeat) {
    final id = heartbeat
        ? CarLifeProtocol.videoHeartbeat
        : CarLifeProtocol.videoData;
    link.send(
      CarLifeProtocol.chVideo,
      CarLifeFraming.stream(
        id,
        Uint8List(0),
        timestamp: _videoClock(),
      ),
    );
  }

  void sendAudio(Uint8List pcm) {
    if (_matched) _media.data(pcm);
  }

  bool mediaIdle() => _media.idle();

  void _mediaPacket(int serviceId, Uint8List payload) {
    final body = serviceId == CarLifeProtocol.mediaData
        ? _crypto.encryptOut(payload)
        : payload;
    link.send(
      CarLifeProtocol.chMedia,
      CarLifeFraming.stream(serviceId, body),
    );
  }

  void sendVoiceStart({int rate = 16000, int channels = 1}) {
    final r = (rate >= 4000 && rate <= 48000) ? rate : 16000;
    link.send(
      CarLifeProtocol.chTts,
      CarLifeFraming.stream(
        CarLifeProtocol.ttsInit,
        ProtoWriter()
            .int32(1, r)
            .int32(2, channels.clamp(1, 2))
            .int32(3, 16)
            .toBytes(),
      ),
    );
    _moduleUpdate(CarLifeProtocol.moduleNavi, 1);
  }

  void sendVoice(Uint8List pcm) {
    link.send(
      CarLifeProtocol.chTts,
      CarLifeFraming.stream(CarLifeProtocol.ttsData, _crypto.encryptOut(pcm)),
    );
  }

  void sendVoiceEnd() {
    link.send(
      CarLifeProtocol.chTts,
      CarLifeFraming.stream(CarLifeProtocol.ttsEnd, Uint8List(0)),
    );
    if (!_naviSubscribed) {
      _moduleUpdate(CarLifeProtocol.moduleNavi, 0);
    }
  }

  void carMicrophone(bool on) {
    if (!_matched || on == _carMicOn) return;
    _carMicOn = on;
    if (on) {
      _moduleUpdate(CarLifeProtocol.moduleMic, 1);
      _cmd(CarLifeProtocol.cmdMicRecordRecogStart);
    } else {
      _cmd(CarLifeProtocol.cmdMicRecordEnd);
      _moduleUpdate(CarLifeProtocol.moduleVr, 0);
      _moduleUpdate(CarLifeProtocol.moduleMic, 0);
    }
  }

  void sendSong({
    required String title,
    required String artist,
    required String album,
    Uint8List? art,
    required int durationMs,
    required int count,
    required String id,
  }) {
    if (!projecting && _state is! CarLifeNegotiated) return;
    _cmd(
      CarLifeProtocol.cmdMediaInfo,
      songPayload(
        title: title,
        artist: artist,
        album: album,
        art: art,
        durationMs: durationMs,
        count: count,
        id: id,
      ),
      true,
    );
  }

  void sendSongPosition(int ms) {
    if (!projecting) return;
    _cmd(
      CarLifeProtocol.cmdMediaProgressBar,
      ProtoWriter().int32(1, ms.clamp(0, 0x7fffffff)).toBytes(),
      true,
    );
  }

  void sendNavigationTurn({
    required int action,
    required CarLifeNavigationInfo info,
    required int totalDistance,
    Uint8List? iconPng,
  }) {
    if (!_matched) return;
    _moduleUpdate(CarLifeProtocol.moduleNavi, info.active ? 1 : 0);
    _cmd(
      CarLifeProtocol.cmdNaviNextTurnInfo,
      NavigationRelay.payload(
        action: action,
        info: info,
        totalDistance: totalDistance,
        iconPng: iconPng,
      ),
      true,
    );
  }

  void goToCarHome() {
    _cmd(CarLifeProtocol.cmdGoToDesktop);
  }

  void goodbye() {
    if (_matched) _cmd(CarLifeProtocol.cmdMdManualDisconnect);
  }

  void _moduleUpdate(int module, int stateVal) {
    if (!_matched) return;
    _cmd(
      CarLifeProtocol.cmdModuleStatus,
      ProtoWriter()
          .int32(1, 1)
          .message(2, ProtoWriter().int32(1, module).int32(2, stateVal))
          .toBytes(),
    );
  }

  void _cmd(int serviceId, [Uint8List? payload, bool quiet = false]) {
    final encrypted = _crypto.encryptOut(payload ?? Uint8List(0));
    final inner = CarLifeFraming.cmd(serviceId, encrypted);
    if (!quiet) {
      _log('TX CMD ${CarLifeProtocol.name(serviceId)} (${inner.length}B)');
    }
    link.send(CarLifeProtocol.chCmd, inner);
  }

  void _linked() {
    _log('Head unit connected over ${link.name}');
    if (_state is CarLifeIdle) {
      _setState(CarLifeLinked(link.name));
    }
  }

  void _closed(String reason) {
    _log('Session closed: $reason');
    _reset();
    onStopVideo?.call();
    _setState(const CarLifeIdle());
    onClosed?.call(reason);
  }

  void _onMessage(int channel, Uint8List head, Uint8List body) {
    switch (channel) {
      case CarLifeProtocol.chCmd:
        final c = CarLifeFraming.parseCmd(head, body);
        _handleCmd(c.copyWith(payload: _crypto.decryptIn(c.payload)));
      case CarLifeProtocol.chCtrl:
        final c = CarLifeFraming.parseCmd(head, body);
        _handleCtrl(c.copyWith(payload: _crypto.decryptIn(c.payload)));
      case CarLifeProtocol.chVr:
        final s = CarLifeFraming.parseStream(head, body);
        if (s.payload.isNotEmpty) {
          onVoiceAudio?.call(s.payload);
        }
      default:
        break;
    }
  }

  void _handleCmd(CarLifeCmdFrame c) {
    if (c.serviceId != CarLifeProtocol.cmdHuGearInfo &&
        c.serviceId != CarLifeProtocol.cmdModuleControl) {
      _log('RX CMD ${CarLifeProtocol.name(c.serviceId)} (${c.payload.length}B)');
    }
    switch (c.serviceId) {
      case CarLifeProtocol.cmdHuProtocolVersion:
        _onProtocolVersion(ProtoReader(c.payload));
      case CarLifeProtocol.cmdHuInfo:
        final r = ProtoReader(c.payload);
        _log('HU_INFO model=${r.stringVal(1)} vendor=${r.stringVal(2)}');
      case CarLifeProtocol.cmdHuFeatureConfigResponse:
        final r = ProtoReader(c.payload);
        final features = <String, int>{};
        for (final m in r.messages(2)) {
          features[m.stringVal(1) ?? ''] = m.intVal(2);
        }
        _log('HU features: $features');
        if (features['CONTENT_ENCRYPTION'] == 1) {
          _startEncryption();
        } else if (features['CONTENT_ENCRYPTION'] == 0) {
          _encryptProbe?.cancel();
        }
      case CarLifeProtocol.cmdHuRsaPublicKeyResponse:
        final pub = ProtoReader(c.payload).stringVal(1) ?? '';
        final req = _crypto.aesKeyRequest(pub);
        if (req != null) {
          _crypto.armIncoming();
          _cmd(
            CarLifeProtocol.cmdMdAesKeySendRequest,
            ProtoWriter().string(1, req).toBytes(),
          );
          _log('Sent wrapped AES-128 session key to Head Unit');
        }
      case CarLifeProtocol.cmdHuAesRecResponse:
        _crypto.enableOutgoing();
        _cmd(CarLifeProtocol.cmdMdEncryptReady);
        _log('AES-128 content encryption active');
      case CarLifeProtocol.cmdHuBtPairInfo:
        _cmd(CarLifeProtocol.cmdMdBtPairInfo, _btPairInfo(1));
      case CarLifeProtocol.cmdVideoEncoderInit:
        _onVideoInit(ProtoReader(c.payload));
      case CarLifeProtocol.cmdVideoEncoderStart:
        final mode = _feed.start();
        projecting = true;
        _frames = 0;
        _setState(
          CarLifeProjecting(
            via: link.name,
            width: width,
            height: height,
            fps: fps,
            streamWidth: streamWidth,
            streamHeight: streamHeight,
          ),
        );
        _startVideoTimer();
        if (mode == VideoFeedMode.resuming) {
          onVideoBack?.call();
        }
      case CarLifeProtocol.cmdVideoEncoderPause:
        _feed.pause();
        projecting = false;
        _setState(
          CarLifeNegotiated(
            via: link.name,
            width: width,
            height: height,
            fps: fps,
            streamWidth: streamWidth,
            streamHeight: streamHeight,
          ),
        );
      case CarLifeProtocol.cmdVideoEncoderReset:
        _feed.resendConfig();
        onNeedKeyframe?.call();
      case CarLifeProtocol.cmdVideoEncoderFrameRateChange:
        final asked = ProtoReader(c.payload).intVal(1, -1);
        final nextFps = VideoPlans.rateChange(asked, forcedFps, 15, fps);
        if (nextFps != null) {
          fps = nextFps;
          onFrameRate?.call(nextFps);
          _cmd(
            CarLifeProtocol.cmdVideoEncoderFrameRateChangeDone,
            ProtoWriter().int32(1, asked).toBytes(),
          );
        }
      case CarLifeProtocol.cmdStatisticInfo:
        if (!_newVehicle) {
          _cmd(
            CarLifeProtocol.cmdMdAuthenResult,
            ProtoWriter().boolean(1, true).toBytes(),
          );
        }
        _cmd(CarLifeProtocol.cmdMdFeatureConfigRequest);
      case CarLifeProtocol.cmdHuAuthenRequest:
        final rnd = ProtoReader(c.payload).stringVal(1) ?? '';
        _cmd(
          CarLifeProtocol.cmdMdAuthenResponse,
          ProtoWriter().string(1, rnd).toBytes(),
        );
      case CarLifeProtocol.cmdLaunchModeNormal:
        _media.launchedAgain();
        onLaunchMode?.call('normal');
      case CarLifeProtocol.cmdLaunchModePhone:
        onLaunchMode?.call('phone');
      case CarLifeProtocol.cmdLaunchModeMap:
        onLaunchMode?.call('map');
      case CarLifeProtocol.cmdLaunchModeMusic:
        onLaunchMode?.call('music');
      case CarLifeProtocol.cmdPauseMedia:
        onPauseMedia?.call();
      case CarLifeProtocol.cmdModuleControl:
        _onModuleControl(ProtoReader(c.payload));
      case CarLifeProtocol.cmdCarlifeDataSubscribe:
        _cmd(
          CarLifeProtocol.cmdCarlifeDataSubscribeDone,
          subscribeDone(c.payload),
        );
      case CarLifeProtocol.cmdCarlifeDataSubscribeStart ||
            CarLifeProtocol.cmdCarlifeDataSubscribeStop:
        final hasNavi = ProtoReader(c.payload)
            .messages(2)
            .any((m) => m.intVal(1, -1) == _subscribeNavigation);
        if (hasNavi) {
          _naviSubscribed =
              c.serviceId == CarLifeProtocol.cmdCarlifeDataSubscribeStart;
        }
      case CarLifeProtocol.cmdHuGearInfo:
        final g = ProtoReader(c.payload).intVal(1, -1);
        if (g != _gear) {
          _gear = g;
          onGear?.call(g);
        }
      default:
        break;
    }
  }

  void _onProtocolVersion(ProtoReader r) {
    final major = r.intVal(1);
    final minor = r.intVal(2);
    if (_matched) return;
    _newVehicle = VideoPlans.newVehicle(major, minor);
    _media.forget();
    _media.oldVehicle = !_newVehicle;
    _cmd(
      CarLifeProtocol.cmdProtocolVersionMatchStatus,
      ProtoWriter().int32(1, 1).toBytes(),
    );
    _matched = true;
    _initSeen = false;
    _musicStartSeen = false;
    _musicEndSeen = false;
    if (_state is CarLifeIdle) {
      _setState(CarLifeLinked(link.name));
    }
    _cmd(CarLifeProtocol.cmdForeground);
    _cmd(CarLifeProtocol.cmdScreenOn);
    _cmd(CarLifeProtocol.cmdMdInfo, _deviceInfo());
    _moduleStatusDelay?.cancel();
    _moduleStatusDelay = Timer(const Duration(milliseconds: 500), () {
      if (_matched) {
        _cmd(CarLifeProtocol.cmdModuleStatus, _moduleStatusPayload());
      }
    });
    _armEncryptProbe();
  }

  void _onVideoInit(ProtoReader r) {
    _initSeen = true;
    _encryptProbe?.cancel();
    final carW = r.intVal(1, 0);
    final carH = r.intVal(2, 0);
    final asked = r.intVal(3, 0);
    if (_videoReady) {
      _cmd(
        CarLifeProtocol.cmdVideoEncoderInitDone,
        encoderInfo(streamWidth, streamHeight, fps),
      );
      return;
    }
    final plan = VideoPlans.plan(
      carWidth: carW,
      carHeight: carH,
      askedFps: asked,
      newVehicle: _newVehicle,
      sizeMode: sizeMode,
      forcedFps: forcedFps,
      bitrate: videoBitrate,
    );
    width = plan.contentWidth;
    height = plan.contentHeight;
    streamWidth = plan.streamWidth;
    streamHeight = plan.streamHeight;
    fps = plan.fps;
    _log(
      'Negotiated car screen ${carW}x$carH -> streaming ${streamWidth}x$streamHeight @ ${fps}fps',
    );
    _feed.open();
    _videoReady = true;
    onVideoConfig?.call(plan);
    _cmd(
      CarLifeProtocol.cmdVideoEncoderInitDone,
      encoderInfo(streamWidth, streamHeight, asked > 0 ? asked : fps),
    );
    _cmd(CarLifeProtocol.cmdForeground);
    _setState(
      CarLifeNegotiated(
        via: link.name,
        width: width,
        height: height,
        fps: fps,
        streamWidth: streamWidth,
        streamHeight: streamHeight,
      ),
    );
  }

  void _onModuleControl(ProtoReader r) {
    final module = r.intVal(1, -1);
    final status = r.intVal(2, -1);
    if (module != CarLifeProtocol.moduleMusic || (status != 0 && status != 1)) {
      return;
    }
    if (status == 1 && !_musicStartSeen) {
      _musicStartSeen = true;
      return;
    }
    if (status == 0 && !_musicEndSeen) {
      _musicEndSeen = true;
      return;
    }
    onMusicControl?.call(status == 1);
  }

  void _handleCtrl(CarLifeCmdFrame c) {
    switch (c.serviceId) {
      case CarLifeProtocol.touchAction:
        final r = ProtoReader(c.payload);
        final raw = r.intVal(1, -1);
        final x = r.intVal(2, -1);
        final y = r.intVal(3, -1);
        final px = r.intVal(4, 0);
        final py = r.intVal(5, 0);
        if (raw < 0 || x < 0 || y < 0) return;
        final action = raw & 0xff;
        final index = (raw >> 8) & 0xff;
        final second = px != 0 || py != 0;
        switch (action) {
          case CarTouch.down || CarTouch.up || CarTouch.move:
            onTouch?.call(
              CarTouch(
                action: action,
                x: x,
                y: y,
                x2: second ? px : -1,
                y2: second ? py : -1,
              ),
            );
          case CarTouch.pointerDown:
            onTouch?.call(
              CarTouch(
                action: action,
                x: x,
                y: y,
                x2: second ? px : x,
                y2: second ? py : y,
                index: index < 1 ? 1 : index,
              ),
            );
          case CarTouch.pointerUp:
            onTouch?.call(
              CarTouch(
                action: action,
                x: x,
                y: y,
                x2: second ? px : -1,
                y2: second ? py : -1,
                index: index,
              ),
            );
        }
      case CarLifeProtocol.touchDown:
        _withPoint(
          c.payload,
          (x, y) => onTouch?.call(CarTouch(action: CarTouch.down, x: x, y: y)),
        );
      case CarLifeProtocol.touchUp:
        _withPoint(
          c.payload,
          (x, y) => onTouch?.call(CarTouch(action: CarTouch.up, x: x, y: y)),
        );
      case CarLifeProtocol.touchMove:
        _withPoint(
          c.payload,
          (x, y) => onTouch?.call(CarTouch(action: CarTouch.move, x: x, y: y)),
        );
      case CarLifeProtocol.touchSingleClick:
        _withPoint(c.payload, (x, y) {
          onTouch?.call(CarTouch(action: CarTouch.down, x: x, y: y));
          onTouch?.call(CarTouch(action: CarTouch.up, x: x, y: y));
        });
      case CarLifeProtocol.touchDoubleClick:
        _withPoint(c.payload, (x, y) {
          onTouch?.call(CarTouch(action: CarTouch.down, x: x, y: y));
          onTouch?.call(CarTouch(action: CarTouch.up, x: x, y: y));
          Timer(const Duration(milliseconds: _doubleTapGapMs), () {
            onTouch?.call(CarTouch(action: CarTouch.down, x: x, y: y));
            onTouch?.call(CarTouch(action: CarTouch.up, x: x, y: y));
          });
        });
      case CarLifeProtocol.touchLongPress:
        _withPoint(c.payload, (x, y) {
          onTouch?.call(CarTouch(action: CarTouch.down, x: x, y: y));
          Timer(const Duration(milliseconds: _longPressMs), () {
            onTouch?.call(CarTouch(action: CarTouch.up, x: x, y: y));
          });
        });
      case CarLifeProtocol.carHardKeyCode:
        final key = ProtoReader(c.payload).intVal(1, -1);
        if (key >= 0) onHardKey?.call(key);
    }
  }

  void _withPoint(Uint8List payload, void Function(int x, int y) use) {
    final r = ProtoReader(payload);
    final x = r.intVal(1, -1);
    final y = r.intVal(2, -1);
    if (x >= 0 && y >= 0) use(x, y);
  }

  void _startVideoTimer() {
    _videoTimer?.cancel();
    _videoTimer = Timer.periodic(
      const Duration(milliseconds: _videoPollMs),
      (_) {
        final gap = (_quietFrames * 1000 ~/ fps.clamp(1, 60))
            .clamp(50, _heartbeatCapMs);
        _feed.idle(gap);
        if (_feed.needsKey()) {
          onNeedKeyframe?.call();
        }
      },
    );
  }

  void _startEncryption() {
    if (_crypto.started) return;
    _crypto.started = true;
    _encryptProbe?.cancel();
    _cmd(CarLifeProtocol.cmdMdRsaPublicKeyRequest);
  }

  void _armEncryptProbe() {
    _encryptProbe?.cancel();
    _encryptProbe = Timer(const Duration(milliseconds: 2500), () {
      if (_matched && !_initSeen && !_crypto.started) {
        _startEncryption();
      }
    });
  }

  Uint8List _btPairInfo(int status) => ProtoWriter()
      .string(1, '')
      .string(2, '')
      .string(5, '00001101-0000-1000-8000-00805F9B34FB')
      .string(6, carName)
      .int32(7, status)
      .toBytes();

  /// Spoofs Baidu CarLife's expected `MD_INFO` fields (`os="Android"` in field 1) so
  /// Chinese-spec Toyota Corolla (DesaySV) accepts the iPhone 15 Pro Max without rejecting the handshake.
  Uint8List _deviceInfo() => ProtoWriter()
      .string(1, 'Android')
      .string(2, 'A17Pro')
      .string(3, 'iBoot')
      .string(4, 'Apple')
      .string(5, 'arm64-v8a')
      .string(6, 'arm64-v8a')
      .string(7, 'iPhone16,2')
      .string(8, 'iOS18')
      .string(9, 'Apple/iPhone15ProMax/iOS18')
      .string(10, 't8130')
      .string(11, 'darwin')
      .string(12, 'ft-ios15pm')
      .string(13, 'Apple')
      .string(14, 'iPhone 15 Pro Max')
      .string(15, 'iPhone16,2')
      .string(16, 'unknown')
      .string(17, 'REL')
      .string(18, '22A3354')
      .string(19, '18.0')
      .string(20, '34')
      .int32(21, 34)
      .string(22, carName)
      .toBytes();

  Uint8List _moduleStatusPayload() {
    final modules = [
      (CarLifeProtocol.modulePhone, 0),
      (CarLifeProtocol.moduleNavi, 0),
      (CarLifeProtocol.moduleMusic, _media.open ? 1 : 0),
      (CarLifeProtocol.moduleVr, 0),
      (CarLifeProtocol.moduleMic, 0),
    ];
    final w = ProtoWriter().int32(1, modules.length);
    for (final (id, st) in modules) {
      w.message(2, ProtoWriter().int32(1, id).int32(2, st));
    }
    return w.toBytes();
  }

  static Uint8List songPayload({
    required String title,
    required String artist,
    required String album,
    Uint8List? art,
    required int durationMs,
    required int count,
    required String id,
  }) =>
      ProtoWriter()
          .string(1, 'FT')
          .string(2, title)
          .string(3, artist)
          .string(4, album)
          .bytes(5, art ?? Uint8List(0))
          .int32(6, durationMs.clamp(0, 0x7fffffff))
          .int32(7, count)
          .string(8, id)
          .int32(9, 0)
          .toBytes();

  static Uint8List encoderInfo(int width, int height, int fps) =>
      ProtoWriter().int32(1, width).int32(2, height).int32(3, fps).toBytes();

  static Uint8List subscribeDone(Uint8List payload) {
    final modules =
        ProtoReader(payload).messages(2).map((m) => m.intVal(1, 0)).toList();
    final w = ProtoWriter().int32(1, modules.length);
    for (final id in modules) {
      w.message(
        2,
        ProtoWriter().int32(1, id).boolean(
              2,
              id == _subscribeMusic || id == _subscribeNavigation,
            ),
      );
    }
    return w.toBytes();
  }
}
