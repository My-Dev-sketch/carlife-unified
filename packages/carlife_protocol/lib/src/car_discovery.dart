import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'carlife_protocol_constants.dart';

/// ICCOA / CarLife BLE Wi-Fi network offer model ported from `ft-app` (`CarIccoaBle.kt`).
class CarWifiOffer {
  final String ssid;
  final String psk;
  final String ip;
  final int port;

  const CarWifiOffer({
    required this.ssid,
    required this.psk,
    required this.ip,
    required this.port,
  });

  static CarWifiOffer? tryParseJsonChunk(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final map = jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
      final ssid = (map['ssid'] ?? map['SSID'] ?? '').toString().trim();
      final psk = (map['psk'] ?? map['password'] ?? '').toString();
      final ip = (map['ip'] ?? map['IP'] ?? '').toString().trim();
      final portRaw = map['port'] ?? map['Port'] ?? 0;
      final port = portRaw is int ? portRaw : int.tryParse(portRaw.toString()) ?? 0;
      if (ssid.isEmpty) return null;
      return CarWifiOffer(ssid: ssid, psk: psk, ip: ip, port: port);
    } catch (_) {
      return null;
    }
  }
}

/// UDP 7999 (`"CarlifeHost"`) & UDP 8999 (`{"carlifehost":"carlife","status":"ready"}`)
/// wireless discovery beacon and responder ported from `ft-app` (`CarBeacon.kt` & `CarDiscovery.kt`).
class CarDiscoveryService {
  static final Uint8List hostBeaconBytes =
      Uint8List.fromList(utf8.encode('CarlifeHost'));
  static final Uint8List readyReplyBytes = Uint8List.fromList(
    utf8.encode('{"carlifehost":"carlife","status":"ready"}'),
  );

  RawDatagramSocket? _discoverySocket;
  RawDatagramSocket? _beaconSocket;
  bool _running = false;

  bool get isRunning => _running;

  /// Starts the phone-side UDP 8999 responder and periodic UDP 7999 `"CarlifeHost"` broadcaster
  /// so both the Toyota Corolla CarLife Head Unit and the BYD Qin Plus receiver auto-discover the iPhone.
  Future<void> startPhoneBeacon({
    required List<InternetAddress> Function() targetAddresses,
    void Function(InternetAddress carIp, int carPort, String message)? onCarDiscovered,
    void Function(String log)? onLog,
  }) async {
    if (_running) return;
    _running = true;

    try {
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        CarLifeProtocol.helloPort,
        reuseAddress: true,
      );
      _discoverySocket!.broadcastEnabled = true;
      _discoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _discoverySocket?.receive();
          if (dg == null) return;
          final text = utf8.decode(dg.data, allowMalformed: true);
          if (text.toLowerCase().contains('carlife') ||
              text.toLowerCase().contains('byd')) {
            _discoverySocket?.send(readyReplyBytes, dg.address, dg.port);
            onCarDiscovered?.call(dg.address, dg.port, text);
            onLog?.call(
              'Answered car discovery from ${dg.address.address}:${dg.port} ($text)',
            );
          }
        }
      });
    } catch (e) {
      onLog?.call('Could not bind UDP ${CarLifeProtocol.helloPort}: $e');
    }

    try {
      _beaconSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      _beaconSocket!.broadcastEnabled = true;
    } catch (e) {
      onLog?.call('Could not open UDP beacon socket: $e');
    }

    _beaconLoop(targetAddresses, onLog);
  }

  Future<void> _beaconLoop(
    List<InternetAddress> Function() targetAddresses,
    void Function(String log)? onLog,
  ) async {
    var count = 0;
    while (_running) {
      final targets = <String, InternetAddress>{
        '255.255.255.255': InternetAddress('255.255.255.255'),
        // Standard iPhone Personal Hotspot subnet broadcast
        '172.20.10.15': InternetAddress('172.20.10.15'),
        '172.20.10.255': InternetAddress('172.20.10.255'),
        // Common BYD / Android Hotspot subnet broadcasts
        '192.168.43.255': InternetAddress('192.168.43.255'),
        '192.168.49.1': InternetAddress('192.168.49.1'),
        '192.168.49.255': InternetAddress('192.168.49.255'),
      };
      for (final t in targetAddresses()) {
        targets[t.address] = t;
      }
      try {
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              final bcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
              targets[bcast] = InternetAddress(bcast);
            }
          }
        }
      } catch (_) {}
      for (final addr in targets.values) {
        try {
          _beaconSocket?.send(
            hostBeaconBytes,
            addr,
            CarLifeProtocol.discoveryPort,
          );
        } catch (_) {}
      }
      count++;
      if (count == 1 || count == 4 || count % 40 == 0) {
        onLog?.call(
          'Sent CarlifeHost UDP ${CarLifeProtocol.discoveryPort} beacon #$count to ${targets.keys.join(", ")}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
  }

  void stop() {
    _running = false;
    _discoverySocket?.close();
    _discoverySocket = null;
    _beaconSocket?.close();
    _beaconSocket = null;
  }
}
