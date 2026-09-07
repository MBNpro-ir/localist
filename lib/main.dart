import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_you_dynamic_theme/material_you_dynamic_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'l10n/app_localizations.dart';
import 'models/app_settings.dart';
import 'models/service_state.dart';
import 'screens/android_permission_gate.dart';
import 'screens/logs_page.dart';
import 'screens/quick_send_page.dart';
import 'screens/receiving_page.dart';
import 'screens/settings_page.dart';
import 'screens/sharing_page.dart';
import 'screens/stats_sheet.dart';
import 'screens/startup_gate.dart';
import 'services/apple_web_transfer_service.dart';
import 'services/app_update_service.dart';
import 'services/crash_reporter_service.dart';
import 'services/log_service.dart';
import 'services/localist_discovery_service.dart';
import 'services/localist_peer_service.dart';
import 'services/native_bridge_service.dart';
import 'services/quick_send_service.dart';
import 'services/quick_send_settings_exit_guard.dart';
import 'widgets/glass.dart';
import 'widgets/localist_bottom_navigation.dart';
import 'widgets/localist_windows_navigation.dart';
import 'widgets/quick_send_profile.dart';

const _windowsSettingsSignatureKey = 'windows.settings.signature';
const _windowsAdminBootstrapArg = '--enable-admin';

Future<void> main(List<String> args) async {
  await runZonedGuarded<Future<void>>(
    () async {
      final binding = WidgetsFlutterBinding.ensureInitialized();
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
  Widget build(BuildContext context) {
    final currentSettings = context.watch<AppSettings>();
    final motionStyle = _disableAnimations
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: Duration(milliseconds: 520),
            reverseDuration: Duration(milliseconds: 420),
            curve: Curves.easeInOutCubicEmphasized,
            reverseCurve: Curves.easeInOutCubic,
          );
    return AppDynamic(
      title: 'Localist',
      locale: currentSettings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: AppLocalizations.resolve,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      builder: (context, child) => Theme(
        data: _modernLocalistTheme(Theme.of(context)),
        child: child ?? const Offstage(),
      ),
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: motionStyle.duration ?? Duration.zero,
      themeAnimationCurve: motionStyle.curve ?? Curves.linear,
      themeAnimationStyle: motionStyle,
      home: StartupGate(
        settings: widget.settings,
        simple: widget.useSimpleTheme,
        childBuilder: (onBackToLanguage) {
          return AndroidPermissionGate(
            simple: widget.useSimpleTheme,
            onBackToLanguage: onBackToLanguage,
            child: QuickSendProfileGate(
              simple: widget.useSimpleTheme,
              child: LocalistShell(
                settings: widget.settings,
                useSimpleTheme: widget.useSimpleTheme,
              ),
            ),
          );
        },
      ),
    );
  }
}

ThemeData _modernLocalistTheme(ThemeData base) {
  final scheme = base.colorScheme;
  const panelRadius = 24.0;
  const controlRadius = 18.0;
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: base.cardTheme.copyWith(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(panelRadius),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .7)),
      ),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: .46),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: .82),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(controlRadius),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
  );
}

Future<void> _bootstrapWindowsWindow() async {
  if (!Platform.isWindows) {
    return;
  }
  await windowManager.ensureInitialized();
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
}

Future<void> _bootstrapWindowsSettings(List<String> args) async {
  if (!Platform.isWindows) {
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  if (args.contains(_windowsAdminBootstrapArg)) {
    await prefs.setBool('root.routingEnabled', true);
  }
  final signature = await NativeBridgeService.instance
      .getWindowsSettingsSignature();
  if (signature == null || signature.isEmpty) {
    return;
  }
  final previous = prefs.getString(_windowsSettingsSignatureKey);
  if (previous != null && previous != signature) {
    await prefs.remove('theme');
    await prefs.remove('colorSchemeType');
    await prefs.remove('seedColor');
  }
  await prefs.setString(_windowsSettingsSignatureKey, signature);
}

class LocalistShell extends StatefulWidget {
  const LocalistShell({
    super.key,
    required this.settings,
    required this.useSimpleTheme,
  });

  final AppSettings settings;
  final bool useSimpleTheme;

  @override
  State<LocalistShell> createState() => _LocalistShellState();
}

class _LocalistShellState extends State<LocalistShell>
    with WidgetsBindingObserver, WindowListener, tray.TrayListener {
  static const _quickSendPageIndex = 0;
  static const _receivingPageIndex = 2;
  final NativeBridgeService _bridge = NativeBridgeService.instance;
  final LocalistDiscoveryService _discovery = LocalistDiscoveryService.instance;
  final LocalistPeerService _peerService = LocalistPeerService.instance;
  final QuickSendService _quickSend = QuickSendService.instance;
  final AppleWebTransferService _appleWebTransfer =
      AppleWebTransferService.instance;
  final AppUpdateService _updates = AppUpdateService();
  final LogService _logs = LogService.instance;
  final GlobalKey<QuickSendPageState> _quickSendPageKey =
      GlobalKey<QuickSendPageState>();
  late final PageController _pageController;
  StreamSubscription<List<QuickSendSharedFile>>?
  _sharedQuickSendFilesSubscription;
  StreamSubscription<void>? _quickSendNotificationSubscription;
  Timer? _refreshTimer;

  int _index = 0;
  ServiceSnapshot _snapshot = ServiceSnapshot.initial(
    protocol: ProxyProtocol.socks5,
    port: ProxyProtocol.socks5.defaultPort,
  );
  bool _busy = false;
  bool _handlingWindowClose = false;
  bool _exitingApplication = false;
  bool _trayReady = false;
  bool _trayDestroyed = false;
  bool _windowActionInProgress = false;
  bool _trayMenuInProgress = false;
  bool _startupUpdateChecked = false;
  List<LocalistDiscoveredDevice> _discoveredDevices = const [];
  bool _discoveryScanning = false;
  List<LocalistConnectedPeer> _connectedPeers = const [];
  final Set<String> _announcedDeviceIds = {};
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _windowFocused = true;
  String? _announcedQuickSendRequestId;
  String? _announcedAutoAcceptedRequestId;
  String? _activeQuickSendDialogRequestId;
  final Map<String, QuickSendTransferState> _knownTransferStates = {};
  bool _transferSoundsPrimed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    if (Platform.isWindows) {
      windowManager.addListener(this);
      tray.trayManager.addListener(this);
      unawaited(_configureWindowsWindow());
    }
    widget.settings.addListener(_handleSettingsChanged);
    _discovery.addListener(_handleDiscoveryChanged);
    _peerService.addListener(_handlePeersChanged);
    _quickSend.addListener(_handleQuickSendChanged);
    _sharedQuickSendFilesSubscription = _bridge.sharedQuickSendFiles.listen(
      _handleQuickSendSharedFiles,
    );
    _quickSendNotificationSubscription = _bridge.quickSendNotificationTaps
        .listen((_) => unawaited(_openQuickSendRequest()));
    unawaited(_bridge.initializeNotifications());
    unawaited(_quickSend.initialize());
    _refreshState();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshState(quiet: true),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForStartupUpdate();
      _openQuickSendForPendingSharedFiles();
      _openQuickSendForPendingNotification();
      _showWindowsUpdateSuccessNotice();
      unawaited(_configureWindowsStartupPreference());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      tray.trayManager.removeListener(this);
    }
    widget.settings.removeListener(_handleSettingsChanged);
    _discovery.removeListener(_handleDiscoveryChanged);
    _peerService.removeListener(_handlePeersChanged);
    _quickSend.removeListener(_handleQuickSendChanged);
    _sharedQuickSendFilesSubscription?.cancel();
    _quickSendNotificationSubscription?.cancel();
    unawaited(_discovery.stop());
    unawaited(_peerService.stop());
    unawaited(_quickSend.disposeService());
    unawaited(_appleWebTransfer.disposeService());
    _refreshTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (!Platform.isWindows || _exitingApplication) {
      return;
    }
    unawaited(_handleWindowsCloseRequest());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      final pending = _quickSend.pendingRequest;
      if (pending != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_showIncomingQuickSendDialog(pending));
          }
        });
      }
    }
  }

  @override
  void onWindowFocus() {
    _windowFocused = true;
    final pending = _quickSend.pendingRequest;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_showIncomingQuickSendDialog(pending));
        }
      });
    }
  }

  @override
  void onWindowBlur() {
    _windowFocused = false;
  }

  @override
  void onTrayIconMouseDown() {
    _runTrayAction(_showWindowFromTray);
  }

  @override
  void onTrayIconRightMouseDown() {
    _runTrayAction(_showTrayContextMenu);
  }

  @override
  void onTrayIconRightMouseUp() {
    // The Windows tray plugin reports right-click release as mouse-down.
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        _runTrayAction(_showWindowFromTray);
        break;
      case 'close':
        _runTrayAction(_exitApplication);
        break;
    }
  }

  Future<void> _configureWindowsWindow() async {
    const minimumSize = Size(920, 620);
    try {
      final iconPath = _windowsBundledAssetPath('ico/logo.ico');
      await windowManager.setTitle('Localist');
      await windowManager.setMinimumSize(minimumSize);
      await windowManager.setResizable(true);
      await windowManager.setMaximizable(true);
      await windowManager.setPreventClose(true);
      await windowManager.setIcon(iconPath);

      await tray.trayManager.setIcon(iconPath);
      await tray.trayManager.setToolTip('Localist');
      await _configureWindowsTrayMenu();
      _trayReady = true;
    } catch (error) {
      _logs.warning('Windows tray setup failed: $error');
    }
  }

  Future<void> _configureWindowsTrayMenu() async {
    final menu = tray.Menu(
      items: [
        tray.MenuItem(
          key: 'open',
          label: _usePersianText ? 'باز کردن' : 'Open',
        ),
        tray.MenuItem.separator(),
        tray.MenuItem(key: 'close', label: _usePersianText ? 'بستن' : 'Close'),
      ],
    );
    await tray.trayManager.setContextMenu(menu);
  }

  bool get _usePersianText {
    return switch (widget.settings.language) {
      AppLanguage.persian => true,
      AppLanguage.english => false,
      AppLanguage.system =>
        WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'fa',
    };
  }

  String _windowsBundledAssetPath(String relativePath) {
    final separator = Platform.pathSeparator;
    final normalized = relativePath.split('/').join(separator);
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final bundledAsset = File(
      '$executableDir${separator}data${separator}flutter_assets$separator$normalized',
    );
    if (bundledAsset.existsSync()) {
      return bundledAsset.path;
    }
    final projectAsset = File(normalized);
    if (projectAsset.existsSync()) {
      return projectAsset.absolute.path;
    }
    return normalized;
  }

  Future<void> _handleWindowsCloseRequest() async {
    if (_handlingWindowClose) {
      return;
    }
    _handlingWindowClose = true;
    try {
      if (!await QuickSendSettingsExitGuard.instance.prepareForExit()) {
        return;
      }
      switch (widget.settings.windowsCloseBehavior) {
        case WindowsCloseBehavior.tray:
          await _hideWindowToTray();
          return;
        case WindowsCloseBehavior.exit:
          await _exitApplication();
          return;
        case WindowsCloseBehavior.ask:
          break;
      }

      final decision = await _showWindowsCloseDialog();
      if (decision == null) {
        return;
      }
      if (decision.remember) {
        await widget.settings.setWindowsCloseBehavior(decision.behavior);
      }
      switch (decision.behavior) {
        case WindowsCloseBehavior.tray:
          await _hideWindowToTray();
          return;
        case WindowsCloseBehavior.exit:
          await _exitApplication();
          return;
        case WindowsCloseBehavior.ask:
          return;
      }
    } finally {
      _handlingWindowClose = false;
    }
  }

  Future<_WindowsCloseDecision?> _showWindowsCloseDialog() {
    final l10n = context.l10n;
    var remember = false;
    return showDialog<_WindowsCloseDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(l10n.closeLocalist),
              actionsAlignment: MainAxisAlignment.center,
              actionsOverflowAlignment: OverflowBarAlignment.center,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: remember,
                    title: Text(l10n.rememberMyChoice),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) {
                      setDialogState(() => remember = value ?? false);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).pop(
                    _WindowsCloseDecision(
                      WindowsCloseBehavior.tray,
                      remember: remember,
                    ),
                  ),
                  icon: const Icon(Icons.system_update_alt_outlined),
                  label: Text(l10n.taskbarTray),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(
                    _WindowsCloseDecision(
                      WindowsCloseBehavior.exit,
                      remember: remember,
                    ),
                  ),
                  icon: const Icon(Icons.close),
                  label: Text(l10n.exit),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _runTrayAction(Future<void> Function() action) {
    unawaited(Future<void>.delayed(const Duration(milliseconds: 80), action));
  }

  Future<void> _showTrayContextMenu() async {
    if (!_trayReady ||
        _trayDestroyed ||
        _exitingApplication ||
        _trayMenuInProgress) {
      return;
    }
    _trayMenuInProgress = true;
    try {
      await tray.trayManager.popUpContextMenu();
    } catch (error) {
      _logs.warning('Tray menu failed: $error');
    } finally {
      _trayMenuInProgress = false;
    }
  }

  Future<void> _hideWindowToTray() async {
    if (_windowActionInProgress || _exitingApplication) {
      return;
    }
    if (!_trayReady || _trayDestroyed) {
      _logs.warning('Taskbar tray is not ready; keeping Localist open.');
      if (mounted) {
        showLocalistNotice(
          context,
          message: context.l10n.taskbarTrayNotReady,
          tone: InAppNoticeTone.warning,
          icon: Icons.desktop_access_disabled_outlined,
        );
      }
      return;
    }
    _windowActionInProgress = true;
    try {
      await windowManager.setPreventClose(true);
      await windowManager.hide();
      _logs.info('Localist moved to the taskbar tray');
    } catch (error) {
      _logs.warning('Unable to move Localist to the taskbar tray: $error');
    } finally {
      _windowActionInProgress = false;
    }
  }

  Future<void> _showWindowFromTray() async {
    if (_windowActionInProgress || _exitingApplication) {
      return;
    }
    _windowActionInProgress = true;
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (error) {
      _logs.warning('Unable to show Localist from the taskbar tray: $error');
    } finally {
      _windowActionInProgress = false;
    }
  }

  Future<void> _exitApplication() async {
    if (_exitingApplication) {
      return;
    }
    if (!await QuickSendSettingsExitGuard.instance.prepareForExit()) {
      return;
    }
    _exitingApplication = true;
    try {
      await _bridge.stopRootSharing();
      await _bridge.stopProxyService();
    } catch (error) {
      _logs.warning('Cleanup before exit failed: $error');
    }
    try {
      _detachTrayIcon();
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } catch (error) {
      _logs.warning('Window close failed: $error');
      exit(0);
    }
  }

  void _detachTrayIcon() {
    if (_trayDestroyed) {
      return;
    }
    _trayDestroyed = true;
    _trayReady = false;
    tray.trayManager.removeListener(this);
  }

  Future<void> _handleSettingsChanged() async {
    if (!mounted) {
      return;
    }
    _logs.debug(
      'Settings changed snapshot sync protocols=${widget.settings.enabledProtocols.map((value) => value.name).join(',')} ports=${widget.settings.protocolPorts}',
    );
    setState(() {
      _snapshot = _snapshot.copyWith(
        protocols: widget.settings.enabledProtocols,
        protocolPorts: widget.settings.protocolPorts,
        port: widget.settings.port,
      );
    });
    if (Platform.isWindows && _trayReady && !_trayDestroyed) {
      unawaited(_configureWindowsTrayMenu());
    }
    unawaited(_syncDiscoveryLifecycle());
  }

  Future<void> _refreshState({bool quiet = false}) async {
    _logs.debug('Native state refresh started quiet=$quiet');
    try {
      final snapshot = await _loadServiceSnapshot();
      if (!mounted) {
        return;
      }
      setState(() => _snapshot = snapshot);
      unawaited(
        _peerService.update(
          sharing:
              snapshot.proxyRunning ||
              (!Platform.isWindows && snapshot.root.active),
          receiving: snapshot.receivingRunning || snapshot.localProxyRunning,
          remote: snapshot.remoteProxy,
        ),
      );
      _logs.debug(
        'Native state refresh completed proxy=${snapshot.proxyRunning} receiving=${snapshot.receivingRunning} localProxy=${snapshot.localProxyRunning} vpn=${snapshot.deviceVpnActive}',
      );
      unawaited(_syncDiscoveryLifecycle());
    } catch (error) {
      _logs.debug('Native state refresh failed quiet=$quiet', error: error);
      if (!quiet) {
        _logs.warning('Unable to refresh native state: $error');
      }
    }
  }

  void _handleDiscoveryChanged() {
    if (!mounted) {
      return;
    }
    final nextDevices = _discovery.devices;
    _logs.debug(
      'Discovery changed scanning=${_discovery.scanning} devices=${nextDevices.length}',
    );
    LocalistDiscoveredDevice? newlyFound;
    for (final device in nextDevices) {
      if (!_announcedDeviceIds.contains(device.id)) {
        newlyFound = device;
        break;
      }
    }
    if (nextDevices.isEmpty) {
      _announcedDeviceIds.clear();
    }
    setState(() {
      _discoveredDevices = nextDevices;
      _discoveryScanning = _discovery.scanning;
    });
    if (newlyFound != null) {
      _announcedDeviceIds.add(newlyFound.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showDiscoveredDeviceNotice(newlyFound!);
        }
      });
    }
  }

  void _handlePeersChanged() {
    if (!mounted) {
      return;
    }
    setState(() => _connectedPeers = _peerService.peers);
  }

  bool get _shouldRunDiscovery {
    return !_busy && !_sharingActive && !_receivingActive;
  }

  Future<void> _syncDiscoveryLifecycle() async {
    final l10n = context.l10n;
    try {
      _logs.debug(
        'Discovery lifecycle sync shouldRun=$_shouldRunDiscovery busy=$_busy sharing=$_sharingActive receiving=$_receivingActive',
      );
      if (_shouldRunDiscovery) {
        await _discovery.resume();
      } else {
        await _discovery.suspend();
      }
    } catch (error) {
      _logs.warning('Local discovery lifecycle update failed: $error');
      if (_shouldRunDiscovery) {
        _showInAppNotice(
          l10n.nearbySearchCouldNotStart,
          tone: InAppNoticeTone.warning,
        );
      }
    }
  }

  Future<void> _refreshDiscovery() async {
    final l10n = context.l10n;
    _logs.debug(
      'Discovery retry button pressed scanning=${_discovery.scanning} devices=${_discoveredDevices.length}',
    );
    try {
      await _discovery.restart();
      _logs.debug('Discovery retry completed');
    } catch (error) {
      _logs.debug('Discovery retry failed', error: error);
      _logs.warning('Local discovery refresh failed: $error');
      _showInAppNotice(l10n.nearbySearchFailed);
    }
  }

  void _showDiscoveredDeviceNotice(LocalistDiscoveredDevice device) {
    final l10n = context.l10n;
    showLocalistNotice(
      context,
      message: l10n.nearbyDeviceFound(device.name),
      tone: InAppNoticeTone.success,
      icon: Icons.devices_outlined,
      duration: const Duration(seconds: 7),
      actionLabel: l10n.openReceiving,
      actionIcon: Icons.arrow_forward,
      onTap: () => _setPage(_receivingPageIndex, force: true),
    );
  }

  Future<void> _checkForStartupUpdate() async {
    if (_startupUpdateChecked || (!Platform.isAndroid && !Platform.isWindows)) {
      return;
    }
    _startupUpdateChecked = true;
    try {
      final result = await _updates.checkForUpdate();
      if (!mounted ||
          !result.updateAvailable ||
          !result.canInstallOnThisDevice) {
        return;
      }
      showLocalistNotice(
        context,
        message: context.l10n.updaterAvailable(
          result.release.version.toString(),
        ),
        tone: InAppNoticeTone.info,
        icon: Icons.system_update_alt_outlined,
        duration: const Duration(seconds: 9),
        actionLabel: context.l10n.installUpdate,
        actionIcon: Icons.arrow_forward,
        onTap: _openSettings,
      );
    } catch (error) {
      _logs.warning('Startup update check failed: $error');
    }
  }

  void _handleQuickSendSharedFiles(List<QuickSendSharedFile> files) {
    if (files.isEmpty || !mounted) {
      return;
    }
    _logs.debug(
      'Opening Quick Send for ${files.length} externally shared files',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _setPage(_quickSendPageIndex, force: true);
      if (_usePersianText) {
        _showInAppNotice(
          '${files.length} \u0641\u0627\u06cc\u0644 \u0628\u0631\u0627\u06cc \u0627\u0631\u0633\u0627\u0644 \u0622\u0645\u0627\u062f\u0647 \u0634\u062f.',
          tone: InAppNoticeTone.success,
        );
        return;
      }
      _showInAppNotice(
        _usePersianText
            ? '${files.length} فایل برای ارسال آماده شد.'
            : '${files.length} file${files.length == 1 ? '' : 's'} ready to send.',
        tone: InAppNoticeTone.success,
      );
    });
  }

  void _handleQuickSendChanged() {
    _handleQuickSendTransferSounds();
    final autoAccepted = _quickSend.lastAutoAcceptedRequest;
    if (autoAccepted != null &&
        _announcedAutoAcceptedRequestId != autoAccepted.id) {
      _announcedAutoAcceptedRequestId = autoAccepted.id;
      _showAutoAcceptedQuickSendNotice(autoAccepted);
    }
    final pending = _quickSend.pendingRequest;
    if (pending == null) {
      _announcedQuickSendRequestId = null;
      return;
    }
    if (_announcedQuickSendRequestId == pending.id) {
      return;
    }
    _announcedQuickSendRequestId = pending.id;
    _showQuickSendRequestNotice(pending);
  }

  void _handleQuickSendTransferSounds() {
    final transfers = _quickSend.transfers;
    if (!_transferSoundsPrimed) {
      _knownTransferStates
        ..clear()
        ..addEntries(transfers.map((item) => MapEntry(item.id, item.state)));
      _transferSoundsPrimed = true;
      return;
    }
    AppSoundEvent? event;
    for (final transfer in transfers) {
      final previous = _knownTransferStates[transfer.id];
      if (previous != transfer.state) {
        if (transfer.state == QuickSendTransferState.failed) {
          event = AppSoundEvent.failed;
        } else if (transfer.state == QuickSendTransferState.completed &&
            event != AppSoundEvent.failed) {
          event = AppSoundEvent.completed;
        }
      }
      _knownTransferStates[transfer.id] = transfer.state;
    }
    _knownTransferStates.removeWhere(
      (id, _) => !transfers.any((transfer) => transfer.id == id),
    );
    if (event != null && widget.settings.soundEffectsEnabled) {
      unawaited(_bridge.playAppSound(event));
    }
  }

  bool get _appIsActive {
    return _appLifecycleState == AppLifecycleState.resumed &&
        (!Platform.isWindows || _windowFocused);
  }

  void _showQuickSendRequestNotice(QuickSendPendingRequest pending) {
    final persian = _usePersianText;
    final title = persian
        ? 'درخواست جدید Quick Send'
        : 'New Quick Send request';
    final message = persian
        ? 'از ${pending.sender.alias} برای دریافت ${pending.files.length} مورد درخواست دارید.'
        : '${pending.sender.alias} wants to send ${pending.files.length} item${pending.files.length == 1 ? '' : 's'}.';
    if (!_appIsActive) {
      unawaited(
        _bridge.showQuickSendRequestNotification(
          title: title,
          message: message,
          soundEnabled: widget.settings.soundEffectsEnabled,
        ),
      );
      return;
    }
    if (widget.settings.soundEffectsEnabled) {
      unawaited(_bridge.playAppSound(AppSoundEvent.request));
    }
    unawaited(_showIncomingQuickSendDialog(pending));
  }

  void _showAutoAcceptedQuickSendNotice(QuickSendAutoAcceptedRequest request) {
    final persian = _usePersianText;
    final message = persian
        ? '${request.files.length} مورد از ${request.sender.alias} به‌صورت خودکار پذیرفته شد.'
        : '${request.files.length} item${request.files.length == 1 ? '' : 's'} from ${request.sender.alias} accepted automatically.';
    if (!_appIsActive) {
      unawaited(
        _bridge.showQuickSendRequestNotification(
          title: persian
              ? 'دریافت خودکار Quick Send'
              : 'Quick Send auto receive',
          message: message,
          soundEnabled: widget.settings.soundEffectsEnabled,
        ),
      );
      return;
    }
    if (widget.settings.soundEffectsEnabled) {
      unawaited(_bridge.playAppSound(AppSoundEvent.accepted));
    }
    if (_index == _quickSendPageIndex) {
      return;
    }
    showLocalistNotice(
      context,
      message: message,
      tone: InAppNoticeTone.success,
      icon: Icons.download_done_rounded,
      duration: const Duration(seconds: 9),
      actionLabel: persian ? 'نمایش' : 'Open',
      actionIcon: Icons.arrow_forward,
      onTap: () => _setPage(_quickSendPageIndex, force: true),
    );
  }

  Future<void> _showIncomingQuickSendDialog(
    QuickSendPendingRequest pending,
  ) async {
    if (!mounted ||
        _activeQuickSendDialogRequestId != null ||
        _quickSend.pendingRequest?.id != pending.id) {
      return;
    }
    _activeQuickSendDialogRequestId = pending.id;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _QuickSendIncomingRequestDialog(
          pending: pending,
          persian: _usePersianText,
        ),
      );
      final current = _quickSend.pendingRequest;
      if (current == null ||
          current.id != pending.id ||
          current.decision.isCompleted) {
        return;
      }
      if (accepted == true) {
        if (widget.settings.soundEffectsEnabled) {
          unawaited(_bridge.playAppSound(AppSoundEvent.accepted));
        }
        _quickSend.acceptPending();
      } else {
        if (widget.settings.soundEffectsEnabled) {
          unawaited(_bridge.playAppSound(AppSoundEvent.cancelled));
        }
        _quickSend.declinePending();
      }
    } finally {
      if (_activeQuickSendDialogRequestId == pending.id) {
        _activeQuickSendDialogRequestId = null;
      }
    }
  }

  Future<void> _openQuickSendRequest([String? requestId]) async {
    if (Platform.isWindows) {
      try {
        if (await windowManager.isMinimized()) {
          await windowManager.restore();
        }
        await windowManager.show();
        await windowManager.focus();
      } catch (error) {
        _logs.warning('Could not bring Localist to the foreground: $error');
      }
    }
    if (!mounted) {
      return;
    }
    _setPage(_quickSendPageIndex, force: true);
    await _quickSendPageKey.currentState?.revealPendingRequest();
    final pending = _quickSend.pendingRequest;
    if (pending != null && (requestId == null || requestId == pending.id)) {
      await _showIncomingQuickSendDialog(pending);
    }
  }

  Future<void> _openQuickSendForPendingNotification() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      if (await _bridge.takeQuickSendNotificationTap()) {
        await _openQuickSendRequest();
      }
    } catch (error) {
      _logs.warning(
        'Could not inspect pending Quick Send notification: $error',
      );
    }
  }

  Future<void> _openQuickSendForPendingSharedFiles() async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return;
    }
    try {
      if (await _bridge.hasQuickSendSharedFiles()) {
        _setPage(_quickSendPageIndex, force: true);
      }
    } catch (error) {
      _logs.warning('Could not inspect pending Quick Send share: $error');
    }
  }

  void _showWindowsUpdateSuccessNotice() {
    if (!Platform.isWindows) {
      return;
    }
    const prefix = '--updated-to=';
    final argument = Platform.executableArguments.where(
      (value) => value.startsWith(prefix),
    );
    if (argument.isEmpty) {
      return;
    }
    final version = argument.first.substring(prefix.length).trim();
    if (version.isEmpty) {
      return;
    }
    if (_usePersianText) {
      _showInAppNotice(
        'Localist \u0628\u0627 \u0645\u0648\u0641\u0642\u06cc\u062a \u0628\u0647 \u0646\u0633\u062e\u0647 $version \u0628\u0647\u200c\u0631\u0648\u0632\u0631\u0633\u0627\u0646\u06cc \u0634\u062f.',
        tone: InAppNoticeTone.success,
      );
      return;
    }
    _showInAppNotice(
      _usePersianText
          ? 'Localist با موفقیت به نسخه $version به‌روزرسانی شد.'
          : 'Localist was updated to version $version.',
      tone: InAppNoticeTone.success,
    );
  }

  void _showInAppNotice(
    String message, {
    InAppNoticeTone tone = InAppNoticeTone.info,
  }) {
    if (!mounted) {
      return;
    }
    showLocalistNotice(context, message: message, tone: tone);
  }

  String _describeError(Object error) {
    if (error is PlatformException) {
      final message = error.message;
      if (message == null || message.isEmpty) {
        return error.code;
      }
      return '${error.code}: $message';
    }
    return error.toString();
  }

  String _serviceErrorMessage(Object error, {required String fallback}) {
    final l10n = context.l10n;
    if (error is PlatformException) {
      final message = error.message;
      return switch (error.code) {
        'port_unavailable' => l10n.portUnavailable,
        'local_proxy_port_unavailable' => l10n.localProxyPortUnavailable,
        'internal_vpn_proxy_unavailable' => l10n.internalVpnProxyUnavailable,
        'vpn_permission_required' => l10n.vpnPermissionRequiredNotice,
        'vpn_permission_pending' => l10n.vpnPermissionPending,
        'windows_admin_required' => l10n.approveWindowsAdminPrompt,
        'missing_proxy_host' => l10n.missingProxyHost,
        'wintun_start_failed' => l10n.wintunStartFailed,
        'wintun_interface_missing' => l10n.wintunInterfaceMissing,
        'netsh_failed' => l10n.netshFailed,
        'windows_proxy_failed' => l10n.windowsProxyFailed,
        'proxy_service_start_failed' ||
        'receiving_service_start_failed' ||
        'local_proxy_start_failed' => l10n.androidServiceStartFailed,
        _ => message ?? fallback,
      };
    }
    final text = error.toString();
    if (text.contains('port_unavailable')) {
      return l10n.portUnavailable;
    }
    if (text.contains('internal_vpn_proxy_unavailable')) {
      return l10n.internalVpnProxyUnavailable;
    }
    if (text.contains('local_proxy_port_unavailable')) {
      return l10n.localProxyPortUnavailable;
    }
    return fallback;
  }

  Future<ServiceSnapshot> _loadServiceSnapshot() {
    return _bridge.getServiceState(
      fallbackProtocol: widget.settings.protocol,
      fallbackPort: widget.settings.port,
      fallbackPorts: widget.settings.protocolPorts,
    );
  }

  Future<bool> _requestRuntimePermissions() async {
    _logs.debug('Runtime permission request started');
    final notification = await Permission.notification.request();
    final ok = notification.isGranted;
    _logs.debug('Runtime permission request result notification=$notification');
    if (ok) {
      _logs.info('Runtime permissions granted');
    } else {
      _logs.warning('Runtime permissions are incomplete');
      if (mounted) {
        await _showPermissionDialog(
          title: context.l10n.notificationPermissionRequired,
          message: context.l10n.notificationPermissionRequiredBody,
        );
      }
    }
    return ok;
  }

  Future<void> _startSharing() async {
    _logs.debug('Sharing button pressed busy=$_busy');
    if (_busy) {
      _logs.debug('Sharing start ignored: busy');
      return;
    }
    final l10n = context.l10n;
    if (_receivingActive) {
      _logs.debug('Sharing start blocked: receiving is active');
      _showServiceConflictMessage(l10n.receiving, l10n.sharing);
      return;
    }
    setState(() => _busy = true);
    unawaited(_syncDiscoveryLifecycle());
    try {
      _logs.debug(
        'Sharing start flow root=${widget.settings.rootRoutingEnabled} protocols=${widget.settings.enabledProtocols.map((value) => value.name).join(',')} ports=${widget.settings.protocolPorts} shareAll=${widget.settings.shareAllRoutes} selectedIps=${widget.settings.selectedLocalIps}',
      );
      if (!Platform.isWindows && widget.settings.rootRoutingEnabled) {
        if (!widget.settings.shareAllRoutes &&
            widget.settings.selectedLocalIps.isEmpty) {
          _logs.warning('No local IP was selected for root sharing');
          if (mounted) {
            showLocalistNotice(
              context,
              message: l10n.selectAtLeastOneLocalIp,
              tone: InAppNoticeTone.warning,
            );
          }
          return;
        }
        final root = await _bridge.startRootSharing(
          shareAllRoutes: widget.settings.shareAllRoutes,
          selectedLocalIps: widget.settings.selectedLocalIps,
        );
        if (root.active) {
          _logs.info(
            'Root VPN sharing started on ${root.vpnInterface} for ${root.clientSubnets.join(', ')}',
          );
        } else {
          final message = root.lastError.isEmpty
              ? l10n.rootVpnDidNotStart
              : root.lastError;
          _logs.error(message);
          _showInAppNotice(message, tone: InAppNoticeTone.error);
        }
        await _refreshState();
        return;
      }
      if (!Platform.isWindows) {
        await _requestRuntimePermissions();
      }
      if (!widget.settings.shareAllRoutes &&
          widget.settings.selectedLocalIps.isEmpty) {
        _logs.warning('No local IP was selected for proxy sharing');
        if (mounted) {
          showLocalistNotice(
            context,
            message: l10n.selectAtLeastOneLocalIp,
            tone: InAppNoticeTone.warning,
          );
        }
        return;
      }
      var internalVpnProxyUnavailable = false;
      RemoteProxyConfig? upstreamProxy;
      if (Platform.isWindows && widget.settings.windowsVpnProxyEnabled) {
        final candidate = RemoteProxyConfig(
          protocol: ProxyProtocol.socks5,
          host: InternetAddress.loopbackIPv4.address,
          port: widget.settings.windowsVpnProxyPort,
        );
        if (await _testProxyConnection(candidate)) {
          upstreamProxy = candidate;
        } else {
          internalVpnProxyUnavailable = true;
          _logs.warning(
            'Internal VPN proxy is unavailable; starting Sharing without VPN upstream.',
          );
        }
      }
      final started = await _bridge.startProxyService(
        protocols: widget.settings.enabledProtocols,
        ports: widget.settings.protocolPorts,
        shareAllRoutes: widget.settings.shareAllRoutes,
        selectedLocalIps: widget.settings.selectedLocalIps,
        upstreamProxy: upstreamProxy,
      );
      if (started) {
        _logs.info(
          widget.settings.enabledProtocols
              .map(
                (protocol) =>
                    '${protocol.label}:${widget.settings.portFor(protocol)}',
              )
              .join(', '),
        );
        if (internalVpnProxyUnavailable && mounted) {
          showLocalistNotice(
            context,
            message: l10n.internalVpnProxyUnavailable,
            tone: InAppNoticeTone.warning,
          );
        }
      }
      await _refreshState();
    } catch (error) {
      _logs.error('Failed to start sharing: ${_describeError(error)}');
      _showInAppNotice(
        _serviceErrorMessage(error, fallback: l10n.failedToStartProxyService),
        tone: InAppNoticeTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      unawaited(_syncDiscoveryLifecycle());
    }
  }

  Future<void> _stopSharing() async {
    _logs.debug('Stop sharing button pressed busy=$_busy');
    if (_busy) {
      _logs.debug('Stop sharing ignored: busy');
      return;
    }
    final l10n = context.l10n;
    setState(() => _busy = true);
    unawaited(_syncDiscoveryLifecycle());
    try {
      await _bridge.stopRootSharing();
      final stopped = await _bridge.stopProxyService();
      if (stopped) {
        _logs.info('Sharing stopped');
      }
      await _refreshState();
    } catch (error) {
      _logs.error('Failed to stop sharing: ${_describeError(error)}');
      _showInAppNotice(l10n.failedToStopSharing, tone: InAppNoticeTone.error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      unawaited(_syncDiscoveryLifecycle());
    }
  }

  Future<void> _stopReceiving() async {
    _logs.debug('Stop receiving button pressed busy=$_busy');
    if (_busy) {
      _logs.debug('Stop receiving ignored: busy');
      return;
    }
    final l10n = context.l10n;
    setState(() => _busy = true);
    unawaited(_syncDiscoveryLifecycle());
    try {
      final stopped = await _bridge.stopProxyService();
      if (stopped) {
        _logs.info('Receiving stopped');
      }
      await _refreshState();
    } catch (error) {
      _logs.error('Failed to stop receiving: ${_describeError(error)}');
      _showInAppNotice(l10n.failedToStopReceiving, tone: InAppNoticeTone.error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      unawaited(_syncDiscoveryLifecycle());
    }
  }

  Future<void> _startReceiving(RemoteProxyConfig config) async {
    _logs.debug(
      'Start receiving VPN button pressed config=${config.url} busy=$_busy',
    );
    if (_busy) {
      _logs.debug('Start receiving VPN ignored: busy');
      return;
    }
    final l10n = context.l10n;
    if (_sharingActive) {
      _logs.debug('Start receiving VPN blocked: sharing is active');
      _showServiceConflictMessage(l10n.sharing, l10n.receiving);
      return;
    }
    setState(() => _busy = true);
    unawaited(_syncDiscoveryLifecycle());
    try {
      final reachable = await _testProxyConnection(config);
      if (!reachable) {
        _logs.warning('Remote proxy is not reachable: ${config.url}');
        if (mounted) {
          showLocalistNotice(
            context,
            message: l10n.proxyNotReachable(config.host),
            tone: InAppNoticeTone.warning,
          );
        }
        return;
      }
      final vpnReady = await _bridge.ensureVpnPermission();
      _logs.debug('VPN permission result ready=$vpnReady');
      if (!vpnReady) {
        _logs.warning('VPN permission was not granted');
        if (mounted) {
          await _showPermissionDialog(
            title: l10n.vpnPermissionRequired,
            message: l10n.vpnPermissionRequiredBody,
          );
        }
        return;
      }
      final started = await _bridge.startReceivingVpn(config);
      if (started) {
        _logs.info('prstun VPN started with ${config.url}');
      }
      await _refreshState();
    } catch (error) {
      _logs.error('Failed to start receiving VPN: ${_describeError(error)}');
      _showInAppNotice(
        _serviceErrorMessage(error, fallback: l10n.failedToStartReceivingVpn),
        tone: InAppNoticeTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      unawaited(_syncDiscoveryLifecycle());
    }
  }

  Future<void> _startLocalProxy(RemoteProxyConfig config) async {
    _logs.debug(
      'Start local proxy button pressed config=${config.url} busy=$_busy',
    );
    if (_busy) {
      _logs.debug('Start local proxy ignored: busy');
      return;
    }
    final l10n = context.l10n;
    if (_sharingActive) {
      _logs.debug('Start local proxy blocked: sharing is active');
      _showServiceConflictMessage(l10n.sharing, l10n.receiving);
      return;
    }
    setState(() => _busy = true);
    unawaited(_syncDiscoveryLifecycle());
    try {
      final reachable = await _testProxyConnection(config);
      if (!reachable) {
        _logs.warning('Remote proxy is not reachable: ${config.url}');
        if (mounted) {
          showLocalistNotice(
            context,
            message: l10n.proxyNotReachable(config.host),
            tone: InAppNoticeTone.warning,
          );
        }
        return;
      }
      final started = await _bridge.startLocalProxy(config);
      if (started) {
        _logs.info('Local proxy started on 127.0.0.1:3781 via ${config.url}');
      }
      await _refreshState();
    } catch (error) {
      _logs.error('Failed to start local proxy: ${_describeError(error)}');
      _showInAppNotice(
        _serviceErrorMessage(error, fallback: l10n.failedToStartLocalProxy),
        tone: InAppNoticeTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      unawaited(_syncDiscoveryLifecycle());
    }
  }

  Future<void> _startSystemProxy(RemoteProxyConfig config) async {
    _logs.debug(
      'Start system proxy button pressed config=${config.url} busy=$_busy',
    );
    if (_busy) {
      _logs.debug('Start system proxy ignored: busy');
      return;
    }
    final l10n = context.l10n;
    if (_sharingActive) {
      _logs.debug('Start system proxy blocked: sharing is active');
      _showServiceConflictMessage(l10n.sharing, l10n.receiving);
      return;
    }
    setState(() => _busy = true);
    unawaited(_syncDiscoveryLifecycle());
    try {
      final reachable = await _testProxyConnection(config);
      if (!reachable) {
        _logs.warning('Remote proxy is not reachable: ${config.url}');
        if (mounted) {
          showLocalistNotice(
            context,
            message: l10n.proxyNotReachable(config.host),
            tone: InAppNoticeTone.warning,
          );
        }
        return;
      }
      final started = await _bridge.startSystemProxy(config);
      if (started) {
        _logs.info('Windows system proxy started via ${config.url}');
      }
      await _refreshState();
    } catch (error) {
      _logs.error('Failed to start system proxy: ${_describeError(error)}');
      _showInAppNotice(
        _serviceErrorMessage(error, fallback: l10n.failedToStartLocalProxy),
        tone: InAppNoticeTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
      unawaited(_syncDiscoveryLifecycle());
    }
  }

  Future<bool> _testProxyConnection(RemoteProxyConfig config) async {
    try {
      _logs.debug('Proxy reachability test started ${config.url}');
      final socket = await Socket.connect(
        config.host,
        config.port,
        timeout: const Duration(seconds: 4),
      );
      if (config.protocol == ProxyProtocol.socks5) {
        socket.add([0x05, 0x01, 0x00]);
        await socket.flush();
        final response = await socket
            .cast<List<int>>()
            .expand((bytes) => bytes)
            .take(2)
            .toList()
            .timeout(const Duration(seconds: 3));
        socket.destroy();
        final ok =
            response.length == 2 && response[0] == 0x05 && response[1] == 0;
        _logs.debug('SOCKS5 reachability test result ${config.url} ok=$ok');
        return ok;
      }
      socket.destroy();
      _logs.debug('TCP reachability test result ${config.url} ok=true');
      return true;
    } catch (error, stack) {
      _logs.debug(
        'Proxy reachability test failed ${config.url}',
        error: error,
        stack: stack,
      );
      return false;
    }
  }

  Future<void> _showPermissionDialog({
    required String title,
    required String message,
  }) {
    final l10n = context.l10n;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _openHotspotSettings() async {
    final l10n = context.l10n;
    _logs.debug('Open hotspot settings button pressed');
    try {
      final opened = await _bridge.openHotspotSettings();
      _logs.debug('Open hotspot settings result opened=$opened');
      if (!opened && mounted) {
        showLocalistNotice(
          context,
          message: l10n.hotspotSettingsCouldNotOpen,
          tone: InAppNoticeTone.warning,
        );
      }
    } catch (error) {
      _logs.error('Failed to open hotspot settings: $error');
      if (mounted) {
        showLocalistNotice(
          context,
          message: l10n.hotspotSettingsCouldNotOpen,
          tone: InAppNoticeTone.warning,
        );
      }
    }
  }

  Future<void> _shareApk() async {
    final l10n = context.l10n;
    _logs.debug('Share APK button pressed');
    try {
      final shared = await _bridge.shareApk();
      _logs.debug('Share APK result shared=$shared');
      if (shared) {
        _logs.info('APK share sheet opened');
      } else {
        _logs.warning('APK share is unavailable on this platform.');
        _showInAppNotice(
          l10n.apkSharingUnavailable,
          tone: InAppNoticeTone.warning,
        );
      }
    } catch (error) {
      _logs.error('Failed to share APK: ${_describeError(error)}');
      _showInAppNotice(l10n.apkSharingFailed, tone: InAppNoticeTone.error);
    }
  }

  Future<void> _showLogsSheet() {
    _logs.debug('Logs sheet button pressed');
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .32),
      builder: (sheetContext) {
        return LogsSheet(onClose: () => Navigator.of(sheetContext).pop());
      },
    );
  }

  Future<void> _showStatsSheet() async {
    _logs.debug('Stats sheet button pressed');
    await _refreshState(quiet: true);
    if (!mounted || !_statsAvailable) {
      return;
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .32),
      builder: (sheetContext) {
        return StatsSheet(
          settings: widget.settings,
          snapshot: _snapshot,
          loadSnapshot: _loadServiceSnapshot,
          onClose: () => Navigator.of(sheetContext).pop(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final themeSettings = context.watch<ThemeSettingsModel>();
    final simpleVisuals = widget.useSimpleTheme;
    final navItems = _navItems(l10n);
    final quickSendVpnActive = Platform.isWindows
        ? _snapshot.receivingRunning && _snapshot.deviceVpnActive
        : _snapshot.deviceVpnActive;
    final systemBarColor = simpleVisuals
        ? Theme.of(context).colorScheme.surface
        : Colors.transparent;
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: systemBarColor,
      systemNavigationBarColor: systemBarColor,
      statusBarIconBrightness: themeSettings.isDarkMode
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarIconBrightness: themeSettings.isDarkMode
          ? Brightness.light
          : Brightness.dark,
      systemStatusBarContrastEnforced: !simpleVisuals,
      systemNavigationBarContrastEnforced: !simpleVisuals,
    );
    final pages = [
      KeepAlivePage(
        child: QuickSendPage(
          key: _quickSendPageKey,
          deviceVpnActive: quickSendVpnActive,
          onOpenProfileSettings: () =>
              unawaited(_openSettings(SettingsSection.quickSend)),
        ),
      ),
      KeepAlivePage(
        child: SharingPage(
          settings: widget.settings,
          snapshot: _snapshot,
          connectedPeers: _connectedPeers,
          busy: _busy,
          controlsLocked: _receivingActive,
          lockMessage: l10n.receivingActiveLock,
          onStartSharing: _startSharing,
          onStopSharing: _stopSharing,
          onOpenHotspotSettings: _openHotspotSettings,
          onRefresh: _refreshState,
        ),
      ),
      KeepAlivePage(
        child: ReceivingPage(
          snapshot: _snapshot,
          discoveredDevices: _discoveredDevices,
          discoveryScanning: _discoveryScanning,
          busy: _busy,
          controlsLocked: _sharingActive,
          lockMessage: l10n.sharingActiveLock,
          onStartReceiving: _startReceiving,
          onStartSystemProxy: _startSystemProxy,
          onStartLocalProxy: _startLocalProxy,
          onStopReceiving: _stopReceiving,
          onRefreshDiscovery: _refreshDiscovery,
        ),
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: GlassBackground(
        simple: simpleVisuals,
        child: Scaffold(
          extendBody: true,
          backgroundColor: simpleVisuals
              ? Theme.of(context).colorScheme.surface
              : Colors.transparent,
          appBar: GlassAppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [const Text('Localist')],
            ),
            actions: [
              IconButton(
                tooltip: l10n.logs,
                onPressed: _showLogsSheet,
                icon: const Icon(Icons.subject_outlined),
              ),
              if (!Platform.isWindows)
                IconButton(
                  tooltip: l10n.shareApk,
                  onPressed: _shareApk,
                  icon: const Icon(Icons.ios_share),
                ),
              IconButton(
                tooltip: themeSettings.isDarkMode
                    ? l10n.lightMode
                    : l10n.darkMode,
                onPressed: () => _toggleTheme(themeSettings),
                icon: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 420),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return RotationTransition(
                      turns: Tween<double>(begin: -.12, end: 0).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        ),
                      ),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: Icon(
                    themeSettings.isDarkMode
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    key: ValueKey(themeSettings.isDarkMode),
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.settings,
                onPressed: _openSettings,
                icon: const Icon(Icons.tune_outlined),
              ),
            ],
          ),
          body: _buildMainContent(context, pages, navItems),
          bottomNavigationBar: Platform.isWindows
              ? null
              : _buildBottomNavigation(context, navItems),
        ),
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    List<Widget> pages,
    List<_NavItem> navItems,
  ) {
    final pageView = PageView(
      controller: _pageController,
      physics: const PageScrollPhysics(),
      onPageChanged: _handlePageChanged,
      children: pages,
    );
    if (!Platform.isWindows) {
      return SafeArea(bottom: false, child: pageView);
    }

    return SafeArea(
      bottom: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: LocalistWindowsNavigation.collapsedWidth,
            ),
            child: pageView,
          ),
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: LocalistWindowsNavigation(
              currentIndex: _index,
              onDestinationSelected: _goToPage,
              items: [
                for (final item in navItems)
                  LocalistBottomNavigationItem(
                    label: item.label,
                    icon: item.icon,
                    selectedIcon: item.selectedIcon,
                  ),
              ],
              showActionButton: _statsAvailable,
              actionIcon: Icons.query_stats,
              actionTooltip: context.l10n.stats,
              onActionPressed: _showStatsSheet,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation(BuildContext context, List<_NavItem> navItems) {
    return LocalistBottomNavigationBar(
      currentIndex: _index,
      onDestinationSelected: _goToPage,
      items: [
        for (final item in navItems)
          LocalistBottomNavigationItem(
            label: item.label,
            icon: item.icon,
            selectedIcon: item.selectedIcon,
          ),
      ],
      showActionButton: _statsAvailable,
      actionIcon: Icons.query_stats,
      actionTooltip: context.l10n.stats,
      onActionPressed: _showStatsSheet,
    );
  }

  bool get _sharingActive {
    return _snapshot.proxyRunning ||
        (!Platform.isWindows && _snapshot.root.active);
  }

  bool get _receivingActive {
    return _snapshot.receivingRunning || _snapshot.localProxyRunning;
  }

  bool get _statsAvailable {
    return _sharingActive || _receivingActive || _snapshot.vpnConnected;
  }

  void _goToPage(int value) {
    _logs.debug('Navigation destination selected index=$value');
    _setPage(value);
  }

  void _handlePageChanged(int value) {
    _logs.debug('Page changed index=$value');
    setState(() => _index = value);
    unawaited(_syncDiscoveryLifecycle());
  }

  void _setPage(int value, {bool force = false}) {
    if (!mounted) {
      return;
    }
    if (_index == value && !force) {
      _logs.debug('Page change skipped index=$value force=$force');
      return;
    }
    if (_index != value) {
      setState(() => _index = value);
    }
    if (!_pageController.hasClients) {
      return;
    }
    _pageController.animateToPage(
      value,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 460),
      curve: Curves.easeInOutCubicEmphasized,
    );
  }

  void _showServiceConflictMessage(String activeService, String targetService) {
    if (!mounted) {
      return;
    }
    showLocalistNotice(
      context,
      message: context.l10n.serviceConflict(activeService, targetService),
      tone: InAppNoticeTone.warning,
      icon: Icons.sync_problem_outlined,
    );
  }

  List<_NavItem> _navItems(AppLocalizations l10n) {
    return [
      const _NavItem('Quick Send', Icons.send_outlined, Icons.send),
      _NavItem(l10n.sharing, Icons.share_outlined, Icons.share),
      _NavItem(l10n.receiving, Icons.qr_code_scanner, Icons.qr_code_2),
    ];
  }

  Future<void> _openSettings([SettingsSection? section]) async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsRoutePage(
          settings: widget.settings,
          portsLocked: _sharingActive,
          simple: widget.useSimpleTheme,
          deviceVpnActive: Platform.isWindows
              ? _snapshot.receivingRunning && _snapshot.deviceVpnActive
              : _snapshot.deviceVpnActive,
          section: section,
        ),
      ),
    );
  }

  Future<void> _configureWindowsStartupPreference() async {
    if (!Platform.isWindows || !mounted) return;
    if (widget.settings.windowsLaunchAtStartupPrompted) {
      if (widget.settings.windowsLaunchAtStartup) {
        await _bridge.setWindowsLaunchAtStartup(true);
      }
      return;
    }
    final enable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.power_settings_new_rounded),
        title: const Text('Start Localist with Windows?'),
        content: const Text(
          'Localist can open automatically when you sign in to Windows. '
          'You can change this later in App behavior.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    await widget.settings.markWindowsLaunchAtStartupPrompted();
    if (enable == true && await _bridge.setWindowsLaunchAtStartup(true)) {
      await widget.settings.setWindowsLaunchAtStartup(true);
    }
  }

  void _toggleTheme(ThemeSettingsModel themeSettings) {
    _logs.debug(
      'Theme toggle button pressed current=${themeSettings.themeMode.name}',
    );
    themeSettings.setThemeMode(
      themeSettings.isDarkMode ? ThemeMode.light : ThemeMode.dark,
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _QuickSendIncomingRequestDialog extends StatelessWidget {
  const _QuickSendIncomingRequestDialog({
    required this.pending,
    required this.persian,
  });

  final QuickSendPendingRequest pending;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final itemCount = pending.files.length;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  QuickSendAvatar(
                    preset: pending.sender.avatarPreset,
                    colorValue: pending.sender.avatarColorValue,
                    imageBase64: pending.sender.avatarImageBase64,
                    size: 58,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          persian
                              ? 'درخواست جدید Quick Send'
                              : 'New Quick Send request',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          persian
                              ? '${pending.sender.alias} می‌خواهد $itemCount مورد برای شما بفرستد.'
                              : '${pending.sender.alias} wants to send $itemCount item${itemCount == 1 ? '' : 's'}.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .58),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: .7),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: itemCount,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final file = pending.files[index];
                      return ListTile(
                        leading: Icon(
                          file.isInlineMessage
                              ? Icons.message_outlined
                              : Icons.insert_drive_file_outlined,
                        ),
                        title: Text(
                          file.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: file.isInlineMessage
                            ? Text(
                                file.preview,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: Text(_formatQuickSendBytes(file.size)),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 430;
                  final decline = OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded),
                    label: Text(persian ? 'رد کردن' : 'Decline'),
                  );
                  final accept = FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.download_done_rounded),
                    label: Text(
                      persian ? 'پذیرش و دریافت' : 'Accept & receive',
                    ),
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [accept, const SizedBox(height: 10), decline],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: decline),
                      const SizedBox(width: 12),
                      Expanded(child: accept),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatQuickSendBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

class _WindowsCloseDecision {
  const _WindowsCloseDecision(this.behavior, {required this.remember});

  final WindowsCloseBehavior behavior;
  final bool remember;
}

class KeepAlivePage extends StatefulWidget {
  const KeepAlivePage({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
