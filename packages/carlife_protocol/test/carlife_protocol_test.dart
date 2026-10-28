import 'dart:typed_data';
import 'package:carlife_protocol/carlife_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CarLifeFraming & ProtoLite Tests', () {
    test('8-byte CMD header framing and parsing matches ft-app', () {
      final payload = ProtoWriter().int32(1, 3).int32(2, 2).toBytes();
      final framed = CarLifeFraming.cmd(
        CarLifeProtocol.cmdHuProtocolVersion,
        payload,
      );
      expect(framed.length, equals(8 + payload.length));
      final head = framed.sublist(0, 8);
      final body = framed.sublist(8);
      expect(
        CarLifeFraming.bodyLen(CarLifeProtocol.chCmd, head),
        equals(payload.length),
      );
      final parsed = CarLifeFraming.parseCmd(head, body);
      expect(parsed.serviceId, equals(CarLifeProtocol.cmdHuProtocolVersion));
      final reader = ProtoReader(parsed.payload);
      expect(reader.intVal(1), equals(3));
      expect(reader.intVal(2), equals(2));
    });

    test('12-byte VIDEO stream header framing and parsing matches ft-app', () {
      final fakeNal = Uint8List.fromList([0x00, 0x00, 0x00, 0x01, 0x65, 0x88]);
      final framed = CarLifeFraming.stream(
        CarLifeProtocol.videoData,
        fakeNal,
        timestamp: 123456,
      );
      expect(framed.length, equals(12 + fakeNal.length));
      final head = framed.sublist(0, 12);
      final body = framed.sublist(12);
      expect(
        CarLifeFraming.bodyLen(CarLifeProtocol.chVideo, head),
        equals(fakeNal.length),
      );
      final parsed = CarLifeFraming.parseStream(head, body);
      expect(parsed.serviceId, equals(CarLifeProtocol.videoData));
      expect(parsed.timestamp, equals(123456));
      expect(parsed.payload, equals(fakeNal));
    });

    test('AES-128-ECB encryption and decryption round-trip', () {
      final crypto = CarLifeCrypto()
        ..setRawSessionKey('1234567890ABCDEF')
        ..armIncoming()
        ..enableOutgoing();
      final plain = ProtoWriter()
          .string(1, 'Toyota Corolla & BYD Qin Plus')
          .int32(2, 1920)
          .toBytes();
      final encrypted = crypto.encryptOut(plain);
      expect(encrypted.length % 16, equals(0));
      expect(encrypted, isNot(equals(plain)));
      final decrypted = crypto.decryptIn(encrypted);
      expect(decrypted, equals(plain));
      final reader = ProtoReader(decrypted);
      expect(reader.stringVal(1), equals('Toyota Corolla & BYD Qin Plus'));
      expect(reader.intVal(2), equals(1920));
    });

    test('End-to-end TCP Loopback Handshake between iPhone Sender and BYD/Corolla Receiver', () async {
      const testPorts = {
        CarLifeProtocol.chCmd: 17240,
        CarLifeProtocol.chVideo: 18240,
        CarLifeProtocol.chMedia: 19240,
        CarLifeProtocol.chTts: 19241,
        CarLifeProtocol.chVr: 19242,
        CarLifeProtocol.chCtrl: 19340,
      };

      final serverLink = WifiServerChannelLink(ports: testPorts);
      final senderSession = CarLifeSession(link: serverLink);

      VideoPlan? negotiatedPlan;
      CarTouch? receivedTouch;
      senderSession.onVideoConfig = (plan) {
        negotiatedPlan = plan;
        senderSession.videoConfig(
          Uint8List.fromList([0x00, 0x00, 0x00, 0x01, 0x67, 0x42]),
        );
      };
      senderSession.onTouch = (touch) {
        receivedTouch = touch;
      };

      await senderSession.start();

      final clientLink = WifiClientChannelLink(
        host: '127.0.0.1',
        ports: testPorts,
      );
      final receiverSession = CarLifeReceiverSession(
        link: clientLink,
        targetWidth: 1920,
        targetHeight: 1080,
        targetFps: 60,
      );

      final receivedNals = <Uint8List>[];
      receiverSession.onVideoNal = (nal, ts) {
        receivedNals.add(nal);
      };

      await receiverSession.start();

      // Wait for handshake + VIDEO_ENCODER_START
      for (var i = 0; i < 40 && !senderSession.projecting; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(senderSession.projecting, isTrue);
      expect(negotiatedPlan, isNotNull);
      expect(negotiatedPlan!.streamWidth, equals(1920));
      expect(negotiatedPlan!.streamHeight, equals(1080));

      // Send an IDR keyframe from iPhone Sender to Receiver
      final idrFrame = Uint8List.fromList([0x00, 0x00, 0x00, 0x01, 0x65, 0x99]);
      senderSession.videoFrame(idrFrame, key: true);

      // Send a touchscreen tap from BYD Receiver back to iPhone Sender
      receiverSession.sendTouch(
        action: CarTouch.down,
        localX: 960,
        localY: 540,
        viewWidth: 1920,
        viewHeight: 1080,
      );

      for (var i = 0;
          i < 30 && (receivedNals.isEmpty || receivedTouch == null);
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(receivedNals, isNotEmpty);
      // First frame includes SPS/PPS config prepended to IDR
      expect(receivedNals.first.length, equals(6 + idrFrame.length));
      expect(receivedTouch, isNotNull);
      expect(receivedTouch!.x, equals(960));
      expect(receivedTouch!.y, equals(540));

      await receiverSession.stop();
      await senderSession.stop();
    });
  });
}
