import 'dart:typed_data';

enum VideoFeedMode { off, held, starting, live, paused, resuming }

class _VideoOut {
  final Uint8List? frame;
  final bool heartbeat;
  const _VideoOut(this.frame, {required this.heartbeat});
}

/// Baidu CarLife H.264 stream state machine ported from `ft-app` (`VideoFeed.kt`).
/// Manages SPS/PPS codec header prepending on first IDR frame, pause/resume keyframe holding,
/// and 900ms watchdog heartbeats so Toyota Corolla & BYD receivers never drop the stream.
class VideoFeed {
  final void Function(Uint8List frame) sendFrame;
  final void Function(bool heartbeat) sendEmpty;
  final int Function() clock;

  VideoFeed({
    required this.sendFrame,
    required this.sendEmpty,
    int Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  VideoFeedMode mode = VideoFeedMode.off;
  Uint8List _config = Uint8List(0);
  bool _configSent = false;
  final List<Uint8List> _held = [];
  int _heldBytes = 0;
  int _dropped = 0;
  int lastSentAt = 0;
  int resumedAfter = 0;
  int _resumedAt = 0;
  int _keyAskedAt = 0;

  static const int resumeDrops = 10;
  static const int resumeWaitMs = 1000;
  static const int forceKeyMs = 2500;
  static const int _maxHeld = 90;
  static const int _maxHeldBytes = 6 * 1024 * 1024;

  void open() {
    mode = VideoFeedMode.held;
    _config = Uint8List(0);
    _configSent = false;
    _dropped = 0;
    _clearHeld();
  }

  void close() {
    mode = VideoFeedMode.off;
    _config = Uint8List(0);
    _configSent = false;
    _clearHeld();
  }

  void resendConfig() {
    _configSent = false;
  }

  void config(Uint8List bytes) {
    if (!_bytesEqual(bytes, _config)) {
      _config = Uint8List.fromList(bytes);
      _configSent = false;
    }
  }

  VideoFeedMode start() {
    switch (mode) {
      case VideoFeedMode.held:
        mode = VideoFeedMode.starting;
        _dropped = 0;
      case VideoFeedMode.paused:
        mode = VideoFeedMode.resuming;
        _dropped = 0;
        _resumedAt = clock();
        _keyAskedAt = _resumedAt;
      default:
        break;
    }
    return mode;
  }

  VideoFeedMode pause() {
    if (mode == VideoFeedMode.starting ||
        mode == VideoFeedMode.live ||
        mode == VideoFeedMode.resuming) {
      mode = VideoFeedMode.paused;
    }
    return mode;
  }

  bool needsKey() {
    final now = clock();
    final due = mode == VideoFeedMode.resuming && (now - _keyAskedAt) >= forceKeyMs;
    if (due) _keyAskedAt = now;
    return due;
  }

  void frame(Uint8List frameBytes, bool key) {
    final out = _decide(frameBytes, key);
    for (final item in out) {
      _emit(item);
    }
  }

  bool idle(int gapMs) {
    if (mode == VideoFeedMode.off || mode == VideoFeedMode.held) return false;
    if ((clock() - lastSentAt) < gapMs) return false;
    _emit(_VideoOut(null, heartbeat: mode != VideoFeedMode.starting));
    return true;
  }

  List<_VideoOut> _decide(Uint8List frameBytes, bool key) {
    switch (mode) {
      case VideoFeedMode.off:
        return const [];
      case VideoFeedMode.held:
        _hold(frameBytes, key);
        return const [];
      case VideoFeedMode.starting:
        _hold(frameBytes, key);
        if (_held.isEmpty) {
          return const [_VideoOut(null, heartbeat: false)];
        }
        final out = <_VideoOut>[];
        for (var i = 0; i < _held.length; i++) {
          out.add(_VideoOut(_payload(_held[i], i == 0), heartbeat: false));
        }
        _clearHeld();
        mode = VideoFeedMode.live;
        return out;
      case VideoFeedMode.live:
        return [_VideoOut(_payload(frameBytes, key), heartbeat: false)];
      case VideoFeedMode.paused:
        return const [_VideoOut(null, heartbeat: true)];
      case VideoFeedMode.resuming:
        if (key &&
            (_dropped > resumeDrops || (clock() - _resumedAt) >= resumeWaitMs)) {
          resumedAfter = _dropped;
          mode = VideoFeedMode.live;
          return [_VideoOut(_payload(frameBytes, true), heartbeat: false)];
        }
        _dropped++;
        if (_dropped % 3 == 0) {
          return const [_VideoOut(null, heartbeat: true)];
        }
        return const [];
    }
  }

  Uint8List _payload(Uint8List frameBytes, bool key) {
    if (!key || _configSent || _config.isEmpty) return frameBytes;
    _configSent = true;
    final combined = Uint8List(_config.length + frameBytes.length);
    combined.setRange(0, _config.length, _config);
    combined.setRange(_config.length, combined.length, frameBytes);
    return combined;
  }

  void _hold(Uint8List frameBytes, bool key) {
    if (key) _clearHeld();
    if (_held.isEmpty && !key) return;
    _held.add(frameBytes);
    _heldBytes += frameBytes.length;
    if (_held.length > _maxHeld || _heldBytes > _maxHeldBytes) {
      _clearHeld();
    }
  }

  void _clearHeld() {
    _held.clear();
    _heldBytes = 0;
  }

  void _emit(_VideoOut o) {
    lastSentAt = clock();
    if (o.frame != null) {
      sendFrame(o.frame!);
    } else {
      sendEmpty(o.heartbeat);
    }
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
