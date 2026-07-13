import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/widgets/glass.dart';

void main() {
  for (final simple in [true, false]) {
    testWidgets(
      'GlassPanel provides a visible Material for ListTile (simple=$simple)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: GlassBackground(
              simple: simple,
              child: const Scaffold(
                body: GlassPanel(
                  child: ListTile(title: Text('Connected device')),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(ListTile), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
