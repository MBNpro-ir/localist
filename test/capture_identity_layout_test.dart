import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/localist/connection_card.dart';
import 'package:localist/screens/live_capture_page.dart';

void main() {
  for (final locale in ['en', 'fa']) {
    testWidgets(
      'identity copy actions stay alongside their values on a narrow $locale screen',
      (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            supportedLocales: const [Locale('en'), Locale('fa')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: LocalistConnectionCard(
                  id: '1234567890',
                  password: 'test1234',
                  onCopyId: () {},
                  onCopyPassword: () {},
                  onCopyConnection: () {},
                ),
              ),
            ),
          ),
        );
        final copy = find.byTooltip(locale == 'fa' ? 'کپی شناسه' : 'Copy ID');
        final id = find.text('1 234 567 890');
        expect(
          (tester.getCenter(copy).dy - tester.getCenter(id).dy).abs(),
          lessThan(24),
        );
        final copyPassword = find.byTooltip(
          locale == 'fa' ? 'کپی رمز' : 'Copy password',
        );
        expect(
          (tester.getCenter(copyPassword).dy -
                  tester.getCenter(find.text('••••••••')).dy)
              .abs(),
          lessThan(24),
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('capture settings fit a small $locale screen with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('en'), Locale('fa')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const Scaffold(body: LiveCapturePage()),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
