import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localist/l10n/app_localizations.dart';
import 'package:localist/models/app_settings.dart';
import 'package:localist/screens/settings_page.dart';
import 'package:localist/services/log_service.dart';
import 'package:material_you_dynamic_theme/material_you_dynamic_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Debug warns before activation and cancel leaves it off', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettings.load();
    final themeSettings = await getThemeSettings();
    addTearDown(() {
      settings.dispose();
      themeSettings.dispose();
      LogService.instance.setDebugMode(false);
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeSettingsModel>.value(
            value: themeSettings,
          ),
          Provider<BrightnessGetColorScheme>.value(
            value: BrightnessGetColorScheme(
              light: ColorScheme.fromSeed(seedColor: Colors.blue),
              dark: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.dark,
              ),
              isDynamicColorSupported: false,
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('fa'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SettingsPage(
              settings: settings,
              portsLocked: false,
              section: SettingsSection.behavior,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final debugSwitch = find.widgetWithText(SwitchListTile, 'حالت دیباگ فعال');
    expect(debugSwitch, findsOneWidget);
    // Two input events can reach the callback before the next frame disables
    // the switch. They must not stack confirmation dialogs.
    final enable = tester.widget<SwitchListTile>(debugSwitch).onChanged!;
    enable(true);
    enable(true);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    expect(settings.activeDebugMode, false);
    expect(find.text('هشدار فعال‌سازی دیباگ'), findsOneWidget);
    expect(find.textContaining('به‌شدت کند'), findsWidgets);

    await tester.tap(find.text('لغو'));
    await tester.pumpAndSettle();
    expect(settings.activeDebugMode, false);

    await tester.tap(debugSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.text('متوجه شدم، فعال کن'));
    await tester.pumpAndSettle();
    expect(settings.activeDebugMode, true);

    await tester.tap(debugSwitch);
    await tester.pumpAndSettle();
    expect(settings.activeDebugMode, false);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
