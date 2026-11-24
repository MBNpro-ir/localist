import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/l10n/app_localizations.dart';
import 'package:localist/widgets/localist_landing.dart';

void main() {
  testWidgets('landing actions fit a short RTL phone with text scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(1.45),
            ),
            child: Scaffold(
              body: LocalistLanding(onChooseDirection: selected.add),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['ارسال', 'دریافت']) {
      final action = find.widgetWithText(FilledButton, label);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
    }
    expect(selected, [false, true]);
    expect(tester.takeException(), isNull);
  });
}
