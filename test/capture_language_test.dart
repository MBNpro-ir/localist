import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/l10n/capture_error_text.dart';
import 'package:localist/services/capture_audio_settings.dart';
import 'package:localist/widgets/capture_audio_controls.dart';
import 'package:localist/widgets/capture_latency_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('camera errors select one language even when native sends both', (
    tester,
  ) async {
    Widget app(String code) => MaterialApp(
      locale: Locale(code),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => Text(
            captureErrorText(
              context,
              'Bad state: ارتباط رسانه قطع شد. / Media connection disconnected.',
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app('fa'));
    expect(find.text('ارتباط رسانه قطع شد.'), findsOneWidget);
    expect(find.textContaining('Media connection'), findsNothing);

    await tester.pumpWidget(app('en'));
    expect(find.text('Media connection disconnected.'), findsOneWidget);
    expect(find.textContaining('ارتباط رسانه'), findsNothing);
  });

  testWidgets('unlocalized platform errors receive localized help', (
    tester,
  ) async {
    Widget app(String code) => MaterialApp(
      locale: Locale(code),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => Text(
            captureErrorText(context, 'PlatformException(camera unavailable)'),
          ),
        ),
      ),
    );

    await tester.pumpWidget(app('fa'));
    expect(find.textContaining('دوربین یا میکروفون'), findsOneWidget);
    expect(find.textContaining('PlatformException'), findsNothing);
    await tester.pumpWidget(app('en'));
    expect(
      find.textContaining('Camera or microphone is unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('دوربین'), findsNothing);
  });

  for (final code in ['fa', 'en']) {
    testWidgets('camera audio controls and latency labels use $code only', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(code),
          supportedLocales: const [Locale('fa'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  CaptureAudioControls(
                    settings: const CaptureAudioSettings(),
                    sender: true,
                    onChanged: (_) {},
                  ),
                  const CaptureLatencyChart(values: [], video: true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (code == 'fa') {
        expect(find.text('صدای فشرده'), findsOneWidget);
        expect(find.text('در انتظار اتصال گیرنده'), findsOneWidget);
        expect(find.textContaining('دسی‌بل'), findsWidgets);
        expect(find.textContaining('Opus'), findsNothing);
        expect(find.textContaining('Player'), findsNothing);
      } else {
        expect(find.text('Compressed · Opus'), findsOneWidget);
        expect(find.text('Waiting for a receiver'), findsOneWidget);
        expect(find.textContaining('dB'), findsWidgets);
        expect(find.textContaining('صدای فشرده'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
