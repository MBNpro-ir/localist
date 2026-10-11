import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/remote/remote_session_return.dart';

void main() {
  testWidgets(
    'returning from the final session closes only its activity once',
    (tester) async {
      final key = GlobalKey<NavigatorState>();
      var closes = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: RemoteSessionReturnPage(
            navigatorKey: key,
            onClose: () async {
              closes++;
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(closes, 0);
      key.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Session')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(closes, 0);
      key.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(closes, 1);
      await tester.pump(const Duration(milliseconds: 400));
      expect(closes, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
