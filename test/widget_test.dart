import 'package:flutter_test/flutter_test.dart';

import 'package:meteo_alert/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MeteoAlertApp());
    expect(find.text('Meteo Alert'), findsOneWidget);
  });
}
