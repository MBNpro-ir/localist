import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_you_dynamic_theme/material_you_dynamic_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'models/app_settings.dart';
import 'models/service_state.dart';
import 'screens/android_permission_gate.dart';
import 'screens/logs_page.dart';
import 'screens/remote_debug_page.dart';
import 'screens/developer_bridge_page.dart';
import 'screens/android_developer_agent_page.dart';
import 'remote/embedded_remote_app.dart';
import 'remote/desktop_host_launch.dart';
import 'remote/android_remote_host.dart';
import 'services/feature_permission_service.dart';
import 'remote/remote_theme.dart';
import 'package:flutter_hbb/main.dart' as embedded;
import 'package:flutter_hbb/common.dart' as remote_engine;
import 'screens/quick_send_page.dart';
import 'screens/receiving_page.dart';
import 'screens/settings_page.dart';
import 'screens/sharing_page.dart';
import 'screens/stats_sheet.dart';
import 'screens/startup_gate.dart';
import 'screens/stream_page.dart';
import 'screens/live_capture_page.dart';
import 'services/capture_hub_service.dart';
import 'screens/vpn_sharing_page.dart';
import 'services/feature_activity_service.dart';
import 'services/dlna_cast_service.dart';
import 'services/rustdesk_debug_service.dart';
import 'services/remote_device_service.dart';
import 'widgets/update_action.dart';
import 'services/apple_web_transfer_service.dart';
import 'services/automatic_update_controller.dart';
import 'services/crash_reporter_service.dart';
import 'services/log_service.dart';
import 'services/localist_discovery_service.dart';
import 'services/localist_peer_service.dart';
import 'services/media_stream_service.dart';
import 'services/native_bridge_service.dart';
import 'services/quick_send_service.dart';
import 'services/quick_send_settings_exit_guard.dart';
import 'widgets/glass.dart';
import 'widgets/localist_bottom_navigation.dart';
import 'widgets/localist_windows_navigation.dart';
import 'widgets/quick_send_profile.dart';

const _windowsSettingsSignatureKey = 'windows.settings.signature';
const _windowsAdminBootstrapArg = '--enable-admin';

@pragma('vm:entry-point')
Future<void> remoteMain() => runEmbeddedRemote();

Future<void> main(List<String> args) async {
  if (Platform.isWindows &&
      (Platform.resolvedExecutable.toLowerCase().endsWith(
            'localistremote.exe',
          ) ||
          (args.isNotEmpty &&
              (args.first == 'multi_window' || args.first == '--cm')))) {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final remoteSettings = await AppSettings.load();
      remote_engine.localistLanguageOverride =
          (AppLocalizations.resolve(
                    remoteSettings.locale ??
                        WidgetsBinding.instance.platformDispatcher.locale,
                    AppLocalizations.supportedLocales,
                  ) ??
                  const Locale('en'))
              .languageCode;
    } catch (error) {
      LogService.instance.debug(
        'Remote process language initialization failed type=${error.runtimeType}',
      );
    }
    configureEmbeddedDesktop(host: isRetainedDesktopHostLaunch(args));
    await embedded.main(args);
    return;
  }
  await runZonedGuarded<Future<void>>(
    () async {
      final binding = WidgetsFlutterBinding.ensureInitialized();
      if (Platform.isAndroid) {
        FeaturePermissionService.instance.useSessionNavigator(
          remote_engine.globalKey,
        );
      }
      binding.deferFirstFrame();
      try {
        await CrashReporterService.instance.initialize();
        await _bootstrapWindowsWindow();
        await _bootstrapWindowsSettings(args);
        final useSimpleTheme = Platform.isAndroid || Platform.isWindows;
        if (!useSimpleTheme) {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
        final settings = await AppSettings.load();
        remote_engine.localistLanguageOverride =
            (AppLocalizations.resolve(
                      settings.locale ?? binding.platformDispatcher.locale,
                      AppLocalizations.supportedLocales,
                    ) ??
                    const Locale('en'))
                .languageCode;
        // Set the language before the embedded remote engine starts.
        unawaited(
          LocalistRemoteRuntime.ensureStarted().catchError((
            Object error,
            StackTrace stack,
          ) {
            LogService.instance.debug('Remote hosting startup failed: $error');
          }),
        );
        LogService.instance.debug(
          'App bootstrap complete platform=${Platform.operatingSystem} version=${Platform.version}',
        );
        final themeSettings = await getThemeSettings();
        final colorScheme = await loadColorScheme(
          fallbackSeedColor: themeSettings.seedColor,
        );
        runApp(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeSettingsModel>.value(
                value: themeSettings,
              ),
              Provider<BrightnessGetColorScheme>.value(value: colorScheme),
              ChangeNotifierProvider<AppSettings>.value(value: settings),
            ],
            child: _LocalistApp(
              settings: settings,
              useSimpleTheme: useSimpleTheme,
            ),
          ),
        );
      } finally {
        binding.allowFirstFrame();
      }
    },
    (error, stack) {
      unawaited(CrashReporterService.instance.reportFatalError(error, stack));
    },
  );
}

class _LocalistApp extends StatefulWidget {
  const _LocalistApp({required this.settings, required this.useSimpleTheme});

  final AppSettings settings;
  final bool useSimpleTheme;

  @override
  State<_LocalistApp> createState() => _LocalistAppState();
}

class _LocalistAppState extends State<_LocalistApp>
    with WidgetsBindingObserver {
  bool get _disableAnimations => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (widget.settings.locale != null) return;
    final deviceLocale =
        locales?.firstOrNull ??
        WidgetsBinding.instance.platformDispatcher.locale;
    remote_engine.localistLanguageOverride =
        (AppLocalizations.resolve(
                  deviceLocale,
                  AppLocalizations.supportedLocales,
                ) ??
                const Locale('en'))
            .languageCode;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentSettings = context.watch<AppSettings>();
    // The embedded remote engine reads this override outside Flutter's
    // Localizations tree. Keep it synchronized with the app's selected locale.
    remote_engine.localistLanguageOverride =
        (AppLocalizations.resolve(
                  currentSettings.locale ??
                      WidgetsBinding.instance.platformDispatcher.locale,
                  AppLocalizations.supportedLocales,
                ) ??
                const Locale('en'))
            .languageCode;
    final motionStyle = _disableAnimations
        ? AnimationStyle.no