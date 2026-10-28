import 'package:byd_qin_receiver/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BYD Qin Plus Receiver renders discovery landing UI and toggles menu bar', (tester) async {
    await tester.pumpWidget(const BydQinReceiverApp());
    expect(
      find.textContaining('BYD Qin Plus • Wireless Android Auto & CarPlay Receiver'),
      findsOneWidget,
    );
    expect(find.text('Connect Now'), findsOneWidget);
    await tester.tap(find.text('Menu'));
    await tester.pump();
    expect(find.text('BYD Waze Split-Screen'), findsOneWidget);
  });
}
