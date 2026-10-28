/// Video resolution, bitrate, and frame-rate negotiation plans ported from `ft-app` (`VideoPlan.kt`).
class VideoPlan {
  final int contentWidth;
  final int contentHeight;
  final int streamWidth;
  final int streamHeight;
  final int fps;
  final int bitrate;
  final int qpFloor;

  const VideoPlan({
    required this.contentWidth,
    required this.contentHeight,
    required this.streamWidth,
    required this.streamHeight,
    required this.fps,
    required this.bitrate,
    this.qpFloor = 0,
  });

  VideoPlan copyWith({
    int? contentWidth,
    int? contentHeight,
    int? streamWidth,
    int? streamHeight,
    int? fps,
    int? bitrate,
    int? qpFloor,
  }) =>
      VideoPlan(
        contentWidth: contentWidth ?? this.contentWidth,
        contentHeight: contentHeight ?? this.contentHeight,
        streamWidth: streamWidth ?? this.streamWidth,
        streamHeight: streamHeight ?? this.streamHeight,
        fps: fps ?? this.fps,
        bitrate: bitrate ?? this.bitrate,
        qpFloor: qpFloor ?? this.qpFloor,
      );

  @override
  String toString() =>
      'VideoPlan(content=${contentWidth}x$contentHeight, stream=${streamWidth}x$streamHeight @ ${fps}fps, ${bitrate ~/ 1000}kbps)';
}

class VideoPlans {
  const VideoPlans._();

  static const int sizeBaidu = 0;
  static const int sizeCar = 1;
  static const int sizeCustom = 2;
  static const int startFpsVal = 30;
  static const int defaultBitrate = 4000000;
  static const int lowestPace = 15;
  static const int unaskedFps = 60;
  static const int unaskedAfterMs = 8000;

  static VideoPlan plan({
    required int carWidth,
    required int carHeight,
    required int askedFps,
    required bool newVehicle,
    int sizeMode = sizeCar,
    int customWidth = 0,
    int customHeight = 0,
    int forcedFps = 60,
    int floorFps = 30,
    int bitrate = defaultBitrate,
    int qpFloor = 22,
    int unaskedStart = startFpsVal,
  }) {
    final cw = _even(carWidth > 0 ? carWidth : 1280).clamp(320, 4096);
    final ch = _even(carHeight > 0 ? carHeight : 720).clamp(240, 2160);
    final (sw, sh) = switch (sizeMode) {
      sizeCar => (cw, ch),
      sizeCustom when customWidth > 0 && customHeight > 0 => (
          _even(customWidth).clamp(320, 4096),
          _even(customHeight).clamp(240, 2160),
        ),
      _ => baiduSize(cw, ch, newVehicle),
    };
    return VideoPlan(
      contentWidth: cw,
      contentHeight: ch,
      streamWidth: sw,
      streamHeight: sh,
      fps: startFps(askedFps, forcedFps, floorFps, unaskedStart),
      bitrate: (bitrate > 0 ? bitrate : baiduBitrate(sw)).clamp(300000, 40000000),
      qpFloor: qpFloor.clamp(0, 51),
    );
  }

  static (int, int) baiduSize(int carWidth, int carHeight, bool newVehicle) {
    final wide = newVehicle && carHeight > 0 && (carWidth / carHeight) >= 2.3;
    if (carWidth < 800) return (768, 432);
    if (carWidth < 1024) return wide ? (1024, 384) : (848, 480);
    if (carWidth < 1280) return wide ? (1024, 384) : (1024, 576);
    if (carWidth < 1920) return wide ? (1280, 480) : (1280, 720);
    if (newVehicle) return wide ? (1920, 720) : (1920, 1080);
    return (1280, 720);
  }

  static int baiduBitrate(int streamWidth) {
    if (streamWidth <= 768) return 1150000;
    if (streamWidth <= 848) return 1280000;
    if (streamWidth <= 1024) return 1920000;
    if (streamWidth <= 1280) return 2560000;
    return 4000000;
  }

  static int startFps(
    int asked,
    int forced,
    int floor, [
    int unaskedStart = startFpsVal,
  ]) {
    if (forced > 0) return forced.clamp(1, 60);
    final base = asked > 2 ? asked : unaskedStart;
    return (base > floor ? base : floor).clamp(1, 60);
  }

  static int? rateChange(int asked, int forced, int floor, int current) {
    if (asked < 3 || asked > 60) return null;
    if (forced > 0) return forced.clamp(1, 60);
    if (asked < lowestPace) return (current > floor ? current : floor).clamp(1, 60);
    return (asked > floor ? asked : floor).clamp(1, 60);
  }

  static bool newVehicle(int major, int minor) =>
      major == 4 || (major == 3 && minor == 2);

  static int _even(int v) => v - (v & 1);
}
