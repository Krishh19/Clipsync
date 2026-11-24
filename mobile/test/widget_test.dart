import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('ClipSyncApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ClipSyncApp());
    expect(find.text('ClipSync'), findsOneWidget);
    // Unmount and flush any internal drift stream query cleanup timers
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
