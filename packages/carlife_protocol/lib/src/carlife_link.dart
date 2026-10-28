import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'carlife_framing.dart';
import 'carlife_protocol_constants.dart';

typedef LinkMessageCallback = void Function(
  int channel,
  Uint8List head,
  Uint8List body,
);

abstract class CarLifeLink {
  String get name;
  bool get isOpen;
  bool get connected;

  Future<void> start({
    required LinkMessageCallback onMessage,
    required void Function(String event) onEvent,
    required void Function() onConnected,
    required void Function(String reason) onClosed,
  });

  bool send(int channel, Uint8List framedPacket);
  Future<void> stop();
}

/// Phone-side TCP Server Link ported from `ft-app` (`WifiChannelLink` in `CarLifeLink.kt`).
/// Listens on the 6 CarLife ports (7240, 8240, 9240, 9241, 9242, 9340) so both the Toyota Corolla
/// CarLife Head Unit and the BYD Qin Plus Receiver can dial in over Wi-Fi Hotspot.
class WifiServerChannelLink implements CarLifeLink {
  final Map<int, int> ports;
  @override
  final String name = 'WiFi-Server';

  final Map<int, ServerSocket> _servers = {};
  final Map<int, Socket> _sockets = {};
  final Map<int, _ChannelFrameAccumulator> _accumulators = {};
  bool _running = false;
  int _cmdGeneration = 0;

  WifiServerChannelLink({
    this.ports = CarLifeProtocol.defaultPorts,
  });

  @override
  bool get isOpen => _running && _sockets.isNotEmpty;

  @override
  bool get connected => _running && _sockets.containsKey(CarLifeProtocol.chCmd);

  @override
  Future<void> start({
    required LinkMessageCallback onMessage,
    required void Function(String event) onEvent,
    required void Function() onConnected,
    required void Function(String reason) onClosed,
  }) async {
    _running = true;
    for (final entry in ports.entries) {
      final channel = entry.key;
      final port = entry.value;
      try {
        final server = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          port,
          shared: true,
        );
        _servers[channel] = server;
        onEvent(
          'WIFI ${CarLifeProtocol.channelName(channel)} listening on 0.0.0.0:$port',
        );
        server.listen((Socket socket) {
          if (!_running) {
            socket.destroy();
            return;
          }
          socket.setOption(SocketOption.tcpNoDelay, true);
          final stale = _sockets[channel];
          if (stale != null) {
            onEvent(
              'WIFI ${CarLifeProtocol.channelName(channel)} reconnected while previous socket open; resetting session',
            );
            _dropAllSockets();
            onClosed('head unit connected again');
          }
          _sockets[channel] = socket;
          if (channel == CarLifeProtocol.chCmd) {
            _cmdGeneration++;
          }
          final gen = _cmdGeneration;
          onEvent(
            'WIFI ${CarLifeProtocol.channelName(channel)} connected from ${socket.remoteAddress.address}',
          );
          if (channel == CarLifeProtocol.chCmd) {
            onConnected();
          }
          final acc = _ChannelFrameAccumulator(channel, onMessage);
          _accumulators[channel] = acc;
          socket.listen(
            acc.addChunk,
            onError: (Object e) {
              _handleDisconnect(channel, socket, gen, onEvent, onClosed);
            },
            onDone: () {
              _handleDisconnect(channel, socket, gen, onEvent, onClosed);
            },
            cancelOnError: true,
          );
        });
      } catch (e) {
        onEvent(
          'Failed to bind ${CarLifeProtocol.channelName(channel)} port $port: $e',
        );
      }
    }
  }

  void _handleDisconnect(
    int channel,
    Socket socket,
    int generation,
    void Function(String) onEvent,
    void Function(String) onClosed,
  ) {
    final isCurrent = identical(_sockets[channel], socket);
    if (isCurrent) {
      _sockets.remove(channel);
      _accumulators.remove(channel);
    }
    try {
      socket.destroy();
    } catch (_) {}
    if (!isCurrent || !_running) return;
    onEvent('WIFI ${CarLifeProtocol.channelName(channel)} disconnected');
    if (channel == CarLifeProtocol.chCmd && generation == _cmdGeneration) {
      onClosed('head unit disconnected');
    }
  }

  void _dropAllSockets() {
    final all = _sockets.values.toList();
    _sockets.clear();
    _accumulators.clear();
    _cmdGeneration++;
    for (final s in all) {
      try {
        s.destroy();
      } catch (_) {}
    }
  }

  @override
  bool send(int channel, Uint8List framedPacket) {
    final s = _sockets[channel];
    if (s == null) return false;
    try {
      s.add(framedPacket);
      return true;
    } catch (_) {
      try {
        s.destroy();
      } catch (_) {}
      _sockets.remove(channel);
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    _dropAllSockets();
    for (final srv in _servers.values) {
      try {
        await srv.close();
      } catch (_) {}
    }
    _servers.clear();
  }
}

/// Head-Unit / Receiver-side TCP Client Link (`WifiClientChannelLink`) used by the
/// BYD Qin Plus Receiver APK (`byd_qin_receiver`) to dial the iPhone 15 Pro Max's 6 TCP ports.
class WifiClientChannelLink implements CarLifeLink {
  final String host;
  final Map<int, int> ports;
  @override
  final String name = 'WiFi-Client';

  final Map<int, Socket> _sockets = {};
  final Map<int, _ChannelFrameAccumulator> _accumulators = {};
  bool _running = false;

  WifiClientChannelLink({
    required this.host,
    this.ports = CarLifeProtocol.defaultPorts,
  });

  @override
  bool get isOpen => _running && _sockets.isNotEmpty;

  @override
  bool get connected => _running && _sockets.containsKey(CarLifeProtocol.chCmd);

  @override
  Future<void> start({
    required LinkMessageCallback onMessage,
    required void Function(String event) onEvent,
    required void Function() onConnected,
    required void Function(String reason) onClosed,
  }) async {
    _running = true;
    try {
      for (final entry in ports.entries) {
        final ch = entry.key;
        final port = entry.value;
        final sock = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 6),
        );
        sock.setOption(SocketOption.tcpNoDelay, true);
        _sockets[ch] = sock;
        final acc = _ChannelFrameAccumulator(ch, onMessage);
        _accumulators[ch] = acc;
        sock.listen(
          acc.addChunk,
          onDone: () {
            if (_running && ch == CarLifeProtocol.chCmd) {
              _running = false;
              onClosed('CMD channel closed by phone');
            }
          },
          onError: (Object e) {
            if (_running && ch == CarLifeProtocol.chCmd) {
              _running = false;
              onClosed('CMD channel error: $e');
            }
          },
          cancelOnError: true,
        );
        onEvent(
          'Connected ${CarLifeProtocol.channelName(ch)} to $host:$port',
        );
      }
      onConnected();
    } catch (e) {
      await stop();
      onClosed('Failed to connect to phone at $host: $e');
    }
  }

  @override
  bool send(int channel, Uint8List framedPacket) {
    final s = _sockets[channel];
    if (s == null) return false;
    try {
      s.add(framedPacket);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    for (final s in _sockets.values) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _sockets.clear();
    _accumulators.clear();
  }
}

/// Zero-drop streaming ring buffer that reassembles arbitrary TCP segments into exact
/// 8-byte (CMD/CTRL) or 12-byte (VIDEO/MEDIA/TTS/VR) CarLife frames.
class _ChannelFrameAccumulator {
  final int channel;
  final LinkMessageCallback onMessage;
  Uint8List _buf = Uint8List(64 * 1024);
  int _size = 0;

  _ChannelFrameAccumulator(this.channel, this.onMessage);

  void addChunk(Uint8List chunk) {
    if (_size + chunk.length > _buf.length) {
      var nextCap = _buf.length * 2;
      while (nextCap < _size + chunk.length) {
        nextCap *= 2;
      }
      final grown = Uint8List(nextCap);
      grown.setRange(0, _size, _buf);
      _buf = grown;
    }
    _buf.setRange(_size, _size + chunk.length, chunk);
    _size += chunk.length;

    final hl = CarLifeFraming.headLen(channel);
    var offset = 0;
    while (_size - offset >= hl) {
      final head = Uint8List.fromList(_buf.sublist(offset, offset + hl));
      final bodyLen = CarLifeFraming.bodyLen(channel, head);
      if (bodyLen < 0 || bodyLen > CarLifeFraming.maxBody(channel)) {
        // Reset buffer if corrupted frame length encountered
        _size = 0;
        return;
      }
      if (_size - offset - hl < bodyLen) {
        break;
      }
      final body = Uint8List.fromList(
        _buf.sublist(offset + hl, offset + hl + bodyLen),
      );
      offset += hl + bodyLen;
      onMessage(channel, head, body);
    }

    if (offset > 0) {
      final remaining = _size - offset;
      if (remaining > 0) {
        _buf.setRange(0, remaining, _buf, offset);
      }
      _size = remaining;
    }
  }
}
