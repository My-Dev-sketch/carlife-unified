import 'package:carlife_protocol/carlife_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ios_carlife_sender/features/touch_dispatcher/touch_dispatcher.dart';

void main() {
  testWidgets('TouchDispatcher translates CarTouch and triggers Flutter button tap', (tester) async {
    var tapped = false;
    final dispatcher = CarLifeTouchDispatcher();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 480,
            child: Center(
              child: SizedBox(
                width: 200,
                height: 100,
                child: ElevatedButton(
                  onPressed: () => tapped = true,
                  child: const Text('CarPlay Action'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    const rect = Rect.fromLTWH(0, 0, 800, 480);
    // Simulate a tap at center of a 1920x1080 car touchscreen (960, 540)
    dispatcher.dispatch(
      touch: const CarTouch(action: CarTouch.down, x: 960, y: 540),
      streamWidth: 1920,
      streamHeight: 1080,
      dashboardRect: rect,
    );
    dispatcher.dispatch(
      touch: const CarTouch(action: CarTouch.up, x: 960, y: 540),
      streamWidth: 1920,
      streamHeight: 1080,
      dashboardRect: rect,
    );
    await tester.pump();

    expect(tapped, isTrue);
  });
}
