import 'dart:typed_data';
import 'bytes.dart';
import 'carlife_protocol_constants.dart';

class CarLifeCmdFrame {
  final int serviceId;
  final Uint8List payload;

  const CarLifeCmdFrame(this.serviceId, this.payload);

  CarLifeCmdFrame copyWith({int? serviceId, Uint8List? payload}) =>
      CarLifeCmdFrame(serviceId ?? this.serviceId, payload ?? this.payload);
}

class CarLifeStreamFrame {
  final int serviceId;
  final int timestamp;
  final Uint8List payload;

  const CarLifeStreamFrame(this.serviceId, this.timestamp, this.payload);
}

/// Wire framing for Baidu CarLife TCP channels ported from `ft-app` (`CarLifeFraming.kt`).
/// - CMD (ch 1) & CTRL (ch 6): 8-byte header `[Length(2B)][Reserved(2B=0)][ServiceId(4B)]`
/// - VIDEO (ch 2), MEDIA (ch 3), TTS (ch 4), VR (ch 5): 12-byte header `[Length(4B)][Timestamp(4B)][ServiceId(4B)]`
class CarLifeFraming {
  const CarLifeFraming._();

  static int headLen(int channel) =>
      (channel == CarLifeProtocol.chCmd || channel == CarLifeProtocol.chCtrl)
          ? CarLifeProtocol.headCmd
          : CarLifeProtocol.headStream;

  static int bodyLen(int channel, Uint8List head) =>
      headLen(channel) == CarLifeProtocol.headCmd
          ? CarLifeBytes.u16(head, 0)
          : CarLifeBytes.u32(head, 0);

  static int maxBody(int channel) =>
      headLen(channel) == CarLifeProtocol.headCmd
          ? CarLifeProtocol.maxCmdBody
          : CarLifeProtocol.maxStreamBody;

  static Uint8List cmd(int serviceId, [Uint8List? payload]) {
    final body = payload ?? Uint8List(0);
    if (body.length > 0xffff) {
      throw ArgumentError('CMD payload exceeds 65535 bytes: ${body.length}');
    }
    final out = Uint8List(CarLifeProtocol.headCmd + body.length);
    CarLifeBytes.putU16(body.length, out, 0);
    CarLifeBytes.putU16(0, out, 2);
    CarLifeBytes.putU32(serviceId, out, 4);
    out.setRange(CarLifeProtocol.headCmd, out.length, body);
    return out;
  }

  static Uint8List stream(
    int serviceId,
    Uint8List payload, {
    int? timestamp,
  }) {
    final ts = timestamp ?? (DateTime.now().millisecondsSinceEpoch & 0xffffffff);
    final out = Uint8List(CarLifeProtocol.headStream + payload.length);
    CarLifeBytes.putU32(payload.length, out, 0);
    CarLifeBytes.putU32(ts, out, 4);
    CarLifeBytes.putU32(serviceId, out, 8);
    out.setRange(CarLifeProtocol.headStream, out.length, payload);
    return out;
  }

  static CarLifeCmdFrame parseCmd(Uint8List head, Uint8List body) =>
      CarLifeCmdFrame(CarLifeBytes.u32(head, 4), body);

  static CarLifeStreamFrame parseStream(Uint8List head, Uint8List body) =>
      CarLifeStreamFrame(
        CarLifeBytes.u32(head, 8),
        CarLifeBytes.u32(head, 4),
        body,
      );

  static int serviceId(int channel, Uint8List head) =>
      headLen(channel) == CarLifeProtocol.headCmd
          ? CarLifeBytes.u32(head, 4)
          : CarLifeBytes.u32(head, 8);
}
