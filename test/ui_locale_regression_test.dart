import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/l10n/app_localizations.dart';
import 'package:localist/models/quick_send_settings.dart';
import 'package:localist/screens/quick_send_page.dart';
import 'package:localist/screens/stream_page.dart';
import 'package:localist/screens/transfer_history_page.dart';
import 'package:localist/services/media_stream_service.dart';
import 'package:localist/services/quick_send_service.dart';
import 'package:localist/widgets/localist_windows_navigation.dart';
import 'package:localist/widgets/quick_send_profile.dart';
import 'package:localist/widgets/remote_ready_indicator.dart';

Widget localizedApp(Locale locale, Widget child) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('remote ready indicator uses only the chosen language', (
    tester,
  ) async {
    for (final locale in [const Locale('fa'), const Locale('en')]) {
      await tester.pumpWidget(
        localizedApp(
          locale,
          const RemoteReadyIndicator(ready: true, online: true, hosting: true),
        ),
      );
      await tester.pump();
      expect(
        find.text(locale.languageCode == 'fa' ? 'آمادهٔ اتصال' : 'Ready'),
        findsOneWidget,
      );
      expect(find.text('آمادهٔ اتصال · Ready'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('media stream intro switches language with locale', (
    tester,
  ) async {
    for (final locale in [const Locale('fa'), const Locale('en')]) {
      await tester.pumpWidget(
        localizedApp(locale, StreamPage(service: MediaStreamService.instance)),
      );
      await tester.pump();
      expect(
        find.text(
          locale.languageCode == 'fa' ? 'استریم رسانه' : 'Media Stream',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          locale.languageCode == 'fa'
              ? 'برای شروع فایل انتخاب کنید.'
              : 'Choose a file to start.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Quick Send status heading follows selected language', (
    tester,
  ) async {
    const settings = QuickSendSettings(
      alias: 'Device',
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
    for (final locale in [const Locale('fa'), const Locale('en')]) {
      await tester.pumpWidget(
        localizedApp(
          locale,
          const QuickSendStatusPanel(
            settings: settings,
            deviceVpnActive: false,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text(locale.languageCode == 'fa' ? 'ارسال سریع' : 'Quick Send'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('transfer history heading follows selected language', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final locale in [const Locale('fa'), const Locale('en')]) {
      await tester.pumpWidget(
        localizedApp(
          locale,
          TransferHistoryPage(service: QuickSendService.instance),
        ),
      );
      await tester.pump();
      expect(
        find.text(
          locale.languageCode == 'fa' ? 'تاریخچه انتقال' : 'Transfer history',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('accessibility preset labels and Stats follow locale', (
    tester,
  ) async {
    for (final locale in [const Locale('fa'), const Locale('en')]) {
      await tester.pumpWidget(
        localizedApp(
          locale,
          Row(
            children: [
              Builder(
                builder: (context) =>
                    Text(quickSendAvatarPresetLabel(context, 'rocket')),
              ),
              SizedBox(
                height: 280,
                child: LocalistWindowsNavigation(
                  currentIndex: 0,
                  onDestinationSelected: (_) {},
                  items: const [],
                  showActionButton: true,
                  onActionPressed: () {},
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text(locale.languageCode == 'fa' ? 'موشک' : 'Rocket'),
        findsOneWidget,
      );
      expect(
        find.byTooltip(locale.languageCode == 'fa' ? 'آمار' : 'Stats'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
