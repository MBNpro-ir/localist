import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/l10n/app_localizations.dart';
import 'package:localist/models/quick_send_settings.dart';
import 'package:localist/screens/quick_send_page.dart';

void main() {
  testWidgets('Quick Send settings status panel shows connection details', (
    tester,
  ) async {
    const settings = QuickSendSettings(
      alias: 'Test device',
      port: 53317,
      multicastGroup: '224.0.0.167',
      destinationDirectory: 'C:/Received',
      destinationCustomized: true,
      receiveEnabled: true,
      encryption: true,
      quickSave: false,
      quickSaveFavorites: true,
      overwrite: false,
      requirePin: false,
      pin: '',
      favoriteFingerprints: <String>{},
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: QuickSendStatusPanel(
            settings: settings,
            deviceVpnActive: false,
          ),
        ),
      ),
    );

    expect(find.text('Quick Send'), findsOneWidget);
    expect(find.text('53317'), findsOneWidget);
    expect(find.text('HTTPS'), findsOneWidget);
    expect(find.text('Selection'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
