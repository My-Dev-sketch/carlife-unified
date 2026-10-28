import 'dart:typed_data';
import 'carlife_protocol_constants.dart';
import 'proto_lite.dart';

/// Baidu CarLife 48kHz stereo PCM media stream state machine ported from `ft-app` (`MediaStream.kt`).
class MediaStream {
  final void Function(int serviceId, Uint8List payload) send;
  final void Function(int module, int state) status;
  final int Function() clock;

  bool oldVehicle = true;
  bool open = false;
  bool _resetWanted = false;
  int _lastDataAt = 0;
  int _resetAt = -900000000;
  int opened = 0;

  static const int quietMs = 750;
  static const int resetGuardMs = 5000;
  static final Uint8List initPayload =
      ProtoWriter().int32(1, 48000).int32(2, 2).int32(3, 16).toBytes();
  static final Uint8List _empty = Uint8List(0);

  MediaStream({
    required this.send,
    required this.status,
    int Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  void data(Uint8List pcm) {
    if (pcm.isEmpty) return;
    if (_resetWanted) _applyReset();
    if (!open) {
      send(CarLifeProtocol.mediaInit, initPayload);
      if (oldVehicle) {
        send(CarLifeProtocol.mediaStop, _empty);
        send(CarLifeProtocol.mediaInit, initPayload);
      }
      status(CarLifeProtocol.moduleMusic, 1);
      open = true;
      opened++;
    }
    _lastDataAt = clock();
    send(CarLifeProtocol.mediaData, pcm);
  }

  bool idle() {
    if (_resetWanted) return _applyReset();
    if (!open || (clock() - _lastDataAt) < quietMs) return false;
    _close();
    return true;
  }

  void launchedAgain() {
    final now = clock();
    final due = (now - _resetAt) > resetGuardMs;
    _resetAt = now;
    if (due) _resetWanted = true;
  }

  void forget() {
    open = false;
    _resetWanted = false;
    _lastDataAt = 0;
    _resetAt = -900000000;
  }

  bool _applyReset() {
    _resetWanted = false;
    if (!open) return false;
    _close();
    return true;
  }

  void _close() {
    send(CarLifeProtocol.mediaPause, _empty);
    status(CarLifeProtocol.moduleMusic, 0);
    open = false;
  }
}

/// Turn-by-turn instrument cluster & HUD navigation relay ported from `ft-app` (`NavigationRelay.kt`).
class CarLifeNavigationInfo {
  final bool active;
  final int maneuver;
  final String road;
  final int? distanceMeters;
  final int timeSeconds;
  final int exit;

  const CarLifeNavigationInfo({
    this.active = false,
    this.maneuver = 0,
    this.road = '',
    this.distanceMeters,
    this.timeSeconds = 0,
    this.exit = 0,
  });
}

class NavigationRelay {
  const NavigationRelay._();

  static int turnCode(int maneuver) {
    switch (maneuver) {
      case 1:
        return 23;
      case 3 || 5 || 13 || 21 || 25 || 27:
        return 8;
      case 4 || 6 || 14 || 22 || 26 || 28:
        return 2;
      case 7 || 15 || 23:
        return 7;
      case 8 || 16 || 24:
        return 3;
      case 9 || 17:
        return 6;
      case 10 || 18:
        return 4;
      case 11 || 12 || 19 || 20:
        return 5;
      case 30 || 32 || 33 || 34 || 35 || 43 || 45:
        return 9;
      case 31 || 44 || 46:
        return 10;
      case 37 || 47 || 48:
        return 29;
      case 38 || 49 || 50:
        return 30;
      case 39 || 40 || 41 || 42:
        return 24;
      default:
        return 1;
    }
  }

  static Uint8List payload({
    required int action,
    required CarLifeNavigationInfo info,
    required int totalDistance,
    Uint8List? iconPng,
  }) =>
      ProtoWriter()
          .int32(1, action)
          .int32(2, turnCode(info.maneuver))
          .string(3, info.road)
          .int32(4, totalDistance < 0 ? 0 : totalDistance)
          .int32(5, (info.distanceMeters ?? 0) < 0 ? 0 : (info.distanceMeters ?? 0))
          .int32(6, info.timeSeconds < 0 ? 0 : info.timeSeconds)
          .bytes(6, iconPng ?? _minimalWhiteArrowPng)
          .toBytes();

  /// Valid 1x1 white PNG fallback for HUD turn arrows when no custom raster is supplied.
  static final Uint8List _minimalWhiteArrowPng = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0xFF,
    0x7F, 0x00, 0x09, 0xFB, 0x03, 0xFD, 0x05, 0x43,
    0x45, 0xCA, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
    0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
}
