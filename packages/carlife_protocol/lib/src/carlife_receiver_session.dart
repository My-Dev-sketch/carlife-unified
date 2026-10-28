import 'dart:async';
import 'dart:typed_data';
import 'carlife_framing.dart';
import 'carlife_link.dart';
import 'carlife_protocol_constants.dart';
import 'proto_lite.dart';

/// Receiver-side (Head Unit) Baidu CarLife session state machine for `byd_qin_receiver`.
/// Acts as the Car Head Unit when connecting to `ios_carlife_sender`:
/// - Sends `HU_PROTOCOL_VERSION` (3.2 / 4.0)
/// - Sends `STATISTIC_INFO`, `HU_INFO`, `CARLIFE_DATA_SUBSCRIBE`
/// - Sends `VIDEO_ENCODER_INIT` (e.g., 1920x1080 @ 60fps for BYD DiLink screen)
/// - Sends `VIDEO_ENCODER_START`
/// - Receives H.264 `VIDEO_DATA` NAL units and forwards them to Android `MediaCodec`
/// - Sends BYD touchscreen `TOUCH_ACTION` events back to the iPhone 15 Pro Max on `CH_CTRL` (Port 9340)
class CarLifeReceiverSession {
  final CarLifeLink link;
  final int targetWidth;
  final int targetHeight;
  final int targetFps;

  void Function(Uint8List h264AnnexB, int timestamp)? onVideoNal;
  void Function(Uint8List pcmBytes)? onMediaPcm;
  void Function(String title, String artist, String album, int durationMs)?
      onSongMetadata;
  void Function(int turnCode, String road, int remainingMeters)? onNavigationHud;
  void Function(String status)? onStatus;

  int negotiatedStreamWidth = 1920;
  int negotiatedStreamHeight = 1080;
  bool connected = false;

  CarLifeReceiverSession({
    required this.link,
    this.targetWidth = 1920,
    this.targetHeight = 1080,
    this.targetFps = 60,
  }) {
    negotiatedStreamWidth = targetWidth;
    negotiatedStreamHeight = targetHeight;
  }

  Future<void> start() async {
    await link.start(
      onMessage: _onMessage,
      onEvent: (e) => onStatus?.call(e),
      onConnected: _onConnected,
      onClosed: (reason) {
        connected = false;
        onStatus?.call('Disconnected: $reason');
      },
    );
  }

  void _onConnected() {
    connected = true;
    onStatus?.call('Connected to iPhone CarLife Server, starting handshake...');
    // Step 1: Send HU_PROTOCOL_VERSION (4.0 for 1080p60 newVehicle support)
    _sendCmd(
      CarLifeProtocol.cmdHuProtocolVersion,
      ProtoWriter().int32(1, 4).int32(2, 0).toBytes(),
    );
  }

  void _onMessage(int channel, Uint8List head, Uint8List body) {
    switch (channel) {
      case CarLifeProtocol.chCmd:
        final cmd = CarLifeFraming.parseCmd(head, body);
        _handleCmd(cmd);
      case CarLifeProtocol.chVideo:
        final stream = CarLifeFraming.parseStream(head, body);
        if (stream.serviceId == CarLifeProtocol.videoData &&
            stream.payload.isNotEmpty) {
          onVideoNal?.call(stream.payload, stream.timestamp);
        }
      case CarLifeProtocol.chMedia:
        final stream = CarLifeFraming.parseStream(head, body);
        if (stream.serviceId == CarLifeProtocol.mediaData &&
            stream.payload.isNotEmpty) {
          onMediaPcm?.call(stream.payload);
        }
      default:
        break;
    }
  }

  void _handleCmd(CarLifeCmdFrame cmd) {
    switch (cmd.serviceId) {
      case CarLifeProtocol.cmdProtocolVersionMatchStatus:
        // Send STATISTIC_INFO, HU_INFO, CARLIFE_DATA_SUBSCRIBE
        _sendCmd(
          CarLifeProtocol.cmdStatisticInfo,
          ProtoWriter()
              .string(1, 'BYD_QIN_PLUS_DILINK')
              .string(2, '4.0')
              .int32(3, 1)
              .string(4, 'BYD')
              .int32(5, 1)
              .int32(6, 1)
              .int32(7, 1)
              .toBytes(),
        );
      case CarLifeProtocol.cmdMdFeatureConfigRequest:
        // Disable content encryption on BYD local link for zero-CPU overhead 60fps
        final featureReply = ProtoWriter()
            .int32(1, 1)
            .message(
              2,
              ProtoWriter().string(1, 'CONTENT_ENCRYPTION').int32(2, 0),
            )
            .toBytes();
        _sendCmd(CarLifeProtocol.cmdHuFeatureConfigResponse, featureReply);
        _sendCmd(
          CarLifeProtocol.cmdHuInfo,
          ProtoWriter()
              .string(1, 'BYD Qin Plus DiLink')
              .string(2, 'BYD')
              .string(14, 'DiLink4.0')
              .toBytes(),
        );
        // Request VIDEO_ENCODER_INIT at BYD display resolution & 60fps
        _sendCmd(
          CarLifeProtocol.cmdVideoEncoderInit,
          ProtoWriter()
              .int32(1, targetWidth)
              .int32(2, targetHeight)
              .int32(3, targetFps)
              .toBytes(),
        );
      case CarLifeProtocol.cmdVideoEncoderInitDone:
        final r = ProtoReader(cmd.payload);
        negotiatedStreamWidth = r.intVal(1, targetWidth);
        negotiatedStreamHeight = r.intVal(2, targetHeight);
        onStatus?.call(
          'Stream ready: ${negotiatedStreamWidth}x$negotiatedStreamHeight @ ${r.intVal(3, targetFps)}fps',
        );
        _sendCmd(CarLifeProtocol.cmdLaunchModeNormal);
        _sendCmd(CarLifeProtocol.cmdVideoEncoderStart);
      case CarLifeProtocol.cmdMediaInfo:
        final r = ProtoReader(cmd.payload);
        onSongMetadata?.call(
          r.stringVal(2) ?? '',
          r.stringVal(3) ?? '',
          r.stringVal(4) ?? '',
          r.intVal(6, 0),
        );
      case CarLifeProtocol.cmdNaviNextTurnInfo:
        final r = ProtoReader(cmd.payload);
        onNavigationHud?.call(
          r.intVal(2, 1),
          r.stringVal(3) ?? '',
          r.intVal(5, 0),
        );
      default:
        break;
    }
  }

  /// Sends a BYD touchscreen event (`TOUCH_ACTION` `0x00068001`) back to the iPhone 15 Pro Max.
  void sendTouch({
    required int action,
    required double localX,
    required double localY,
    required double viewWidth,
    required double viewHeight,
  }) {
    if (!connected || viewWidth <= 0 || viewHeight <= 0) return;
    final scaledX =
        ((localX / viewWidth).clamp(0.0, 1.0) * negotiatedStreamWidth).round();
    final scaledY =
        ((localY / viewHeight).clamp(0.0, 1.0) * negotiatedStreamHeight).round();
    final payload = ProtoWriter()
        .int32(1, action)
        .int32(2, scaledX)
        .int32(3, scaledY)
        .toBytes();
    link.send(
      CarLifeProtocol.chCtrl,
      CarLifeFraming.cmd(CarLifeProtocol.touchAction, payload),
    );
  }

  /// Requests an immediate IDR keyframe from the iPhone encoder (`VIDEO_ENCODER_RESET`).
  void requestKeyframe() {
    if (!connected) return;
    _sendCmd(CarLifeProtocol.cmdVideoEncoderReset);
  }

  void _sendCmd(int serviceId, [Uint8List? payload]) {
    link.send(
      CarLifeProtocol.chCmd,
      CarLifeFraming.cmd(serviceId, payload),
    );
  }

  Future<void> stop() async {
    connected = false;
    await link.stop();
  }
}
