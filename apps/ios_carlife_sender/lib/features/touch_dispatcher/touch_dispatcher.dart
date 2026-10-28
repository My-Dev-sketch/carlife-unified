import 'package:carlife_protocol/carlife_protocol.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Bidirectional touch injection engine (`lib/features/touch_dispatcher/`) ported from `ft-app` (`CarDisplay.kt`).
/// Translates incoming `CarTouch` coordinates from the Toyota Corolla CarLife Head Unit
/// or BYD Qin Plus DiLink touchscreen (`streamWidth` x `streamHeight`) into logical Flutter coordinates
/// and injects them directly into `WidgetsBinding.instance.handlePointerEvent`.
class CarLifeTouchDispatcher {
  int _pointerId = 900;
  bool _isDown = false;
  Offset _lastPosition = Offset.zero;
  int _activePointers = 0;

  /// Dispatches a `CarTouch` packet into the Flutter widget tree bounded by [dashboardRect].
  void dispatch({
    required CarTouch touch,
    required int streamWidth,
    required int streamHeight,
    required Rect dashboardRect,
  }) {
    if (dashboardRect.isEmpty) return;

    final (normX, normY) = touch.normalize(
      streamWidth: streamWidth,
      streamHeight: streamHeight,
      targetWidth: dashboardRect.width,
      targetHeight: dashboardRect.height,
    );
    final pos = Offset(
      dashboardRect.left + normX,
      dashboardRect.top + normY,
    );
    final now = Duration(
      microseconds: DateTime.now().microsecondsSinceEpoch,
    );

    final binding = WidgetsBinding.instance;

    switch (touch.action) {
      case CarTouch.down:
        if (_isDown) {
          binding.handlePointerEvent(
            PointerUpEvent(
              pointer: _pointerId,
              position: _lastPosition,
              timeStamp: now,
              kind: PointerDeviceKind.touch,
            ),
          );
        }
        _pointerId++;
        _isDown = true;
        _activePointers = 1;
        _lastPosition = pos;
        binding.handlePointerEvent(
          PointerAddedEvent(
            pointer: _pointerId,
            position: pos,
            timeStamp: now,
            kind: PointerDeviceKind.touch,
          ),
        );
        binding.handlePointerEvent(
          PointerDownEvent(
            pointer: _pointerId,
            position: pos,
            timeStamp: now,
            kind: PointerDeviceKind.touch,
          ),
        );

      case CarTouch.move:
        if (!_isDown) {
          _pointerId++;
          _isDown = true;
          _activePointers = 1;
          _lastPosition = pos;
          binding.handlePointerEvent(
            PointerDownEvent(
              pointer: _pointerId,
              position: pos,
              timeStamp: now,
              kind: PointerDeviceKind.touch,
            ),
          );
          return;
        }
        final delta = pos - _lastPosition;
        _lastPosition = pos;
        binding.handlePointerEvent(
          PointerMoveEvent(
            pointer: _pointerId,
            position: pos,
            delta: delta,
            timeStamp: now,
            kind: PointerDeviceKind.touch,
          ),
        );

      case CarTouch.up:
        if (!_isDown) return;
        // Like ft-app CarDisplay.kt: ensure final move lands at lift position so drags/scrolls finish accurately
        if ((pos - _lastPosition).distanceSquared > 0.5) {
          binding.handlePointerEvent(
            PointerMoveEvent(
              pointer: _pointerId,
              position: pos,
              delta: pos - _lastPosition,
              timeStamp: now,
              kind: PointerDeviceKind.touch,
            ),
          );
        }
        _lastPosition = pos;
        _isDown = false;
        _activePointers = 0;
        binding.handlePointerEvent(
          PointerUpEvent(
            pointer: _pointerId,
            position: pos,
            timeStamp: now,
            kind: PointerDeviceKind.touch,
          ),
        );
        binding.handlePointerEvent(
          PointerRemovedEvent(
            pointer: _pointerId,
            position: pos,
            timeStamp: now,
            kind: PointerDeviceKind.touch,
          ),
        );

      case CarTouch.pointerDown:
        _activePointers = 2;
        if (touch.x2 >= 0 && touch.y2 >= 0) {
          final (nx2, ny2) = CarTouch(
            action: CarTouch.down,
            x: touch.x2,
            y: touch.y2,
          ).normalize(
            streamWidth: streamWidth,
            streamHeight: streamHeight,
            targetWidth: dashboardRect.width,
            targetHeight: dashboardRect.height,
          );
          final pos2 = Offset(
            dashboardRect.left + nx2,
            dashboardRect.top + ny2,
          );
          binding.handlePointerEvent(
            PointerDownEvent(
              pointer: _pointerId + 1,
              position: pos2,
              timeStamp: now,
              kind: PointerDeviceKind.touch,
            ),
          );
        }

      case CarTouch.pointerUp:
        if (_activePointers >= 2) {
          _activePointers = 1;
          binding.handlePointerEvent(
            PointerUpEvent(
              pointer: _pointerId + 1,
              position: _lastPosition,
              timeStamp: now,
              kind: PointerDeviceKind.touch,
            ),
          );
        }
    }
  }
}
