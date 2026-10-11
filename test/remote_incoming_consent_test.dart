import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/remote/android_remote_host.dart';

void main() {
  for (final accepted in [false, true]) {
    testWidgets('incoming request returns explicit $accepted consent', (
      tester,
    ) async {
      bool? result;
      var shares = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (_) => RemoteIncomingConsent(
                      name: 'Office PC',
                      peerId: '183976',
                      onSharePassword: () async {
                        shares++;
                      },
                    ),
                  );
                },
                child: const Text('Request'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Request'));
      await tester.pumpAndSettle();
      expect(find.text('Office PC · 183976'), findsOneWidget);
      expect(find.textContaining('permanent password'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.text('Share one-time password'));
      await tester.pump();
      expect(shares, 1);
      expect(result, isNull);
      await tester.tap(find.text(accepted ? 'Accept connection' : 'Decline'));
      await tester.pumpAndSettle();
      expect(result, accepted);
    });
  }
}
