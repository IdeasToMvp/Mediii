import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('smoke: basic widget tree', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('MediSathi smoke')),
      ),
    );
    expect(find.text('MediSathi smoke'), findsOneWidget);
  });
}
