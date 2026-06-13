import 'package:flutter_test/flutter_test.dart';
import 'package:quick_launch/app.dart';

void main() {
  testWidgets('App should render', (WidgetTester tester) async {
    await tester.pumpWidget(const QuickLaunchApp());
    expect(find.text('快速启动'), findsOneWidget);
  });
}
