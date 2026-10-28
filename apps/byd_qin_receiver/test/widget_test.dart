import 'package:byd_qin_receiver/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BYD Qin Plus Receiver renders discovery landing UI and Waze Split-Screen button', (tester) async {
    await tester.pumpWidget(const BydQinReceiverApp());
    expect(
      find.textContaining('BYD Qin Plus • Wireless CarPlay / CarLife 60fps Receiver'),
      findsOneWidget,
    );
    expect(find.text('Open BYD Waze Split-Screen'), findsOneWidget);
    expect(find.text('Connect Now'), findsOneWidget);
  });
}
