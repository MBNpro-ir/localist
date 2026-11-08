import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/widgets/remote_ready_indicator.dart';

void main() {
  testWidgets(
    'server connectivity cannot report Ready before the device has an ID',
    (tester) async {
      Widget indicator(bool identityReady) => MaterialApp(
        home: Scaffold(
          body: RemoteReadyIndicator(
            ready: true,
            online: true,
            hosting: true,
            identityReady: identityReady,
            server: 'private-server.example',
          ),
        ),
      );
      await tester.pumpWidget(indicator(false));
      expect(find.text('Waiting for device ID'), findsOneWidget);
      expect(find.text('Ready'), findsNothing);
      expect(find.textContaining('private-server'), findsNothing);
      await tester.pumpWidget(indicator(true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Waiting for device ID'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
