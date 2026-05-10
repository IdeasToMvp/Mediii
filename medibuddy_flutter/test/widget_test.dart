import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('smoke: basic widget tree', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('MediBuddy smoke')),
      ),
    );
    expect(find.text('MediBuddy smoke'), findsOneWidget);
  });
}
