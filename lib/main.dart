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
import 'services/app_update_service.dart';
import 'services/crash_reporter_service.dart';
import 'services/log_service.dart';
import 'services/localist_discovery_service.dart';
import 'services/localist_peer_service.dart';
import 'services/native_bridge_service.dart';
import 'services/quick_send_service.dart';
import 'widgets/glass.dart';

const _onboardingSeenKey = 'localist.onboarding.v2.seen';
const _windowsSettingsSignatureKey = 'windows.settings.signature';
const _windowsAdminBootstrapArg = '--enable-admin';
const _android13Sdk = 33;

Future<void> main(List<String> args) async {
  await runZonedGuarded<Future<void>>(
    () async {
      final binding = WidgetsFlutterBinding.ensureInitialized();
      binding.deferFirstFrame();
      try {
        await CrashReporterService.instance.initialize();
        await _bootstrapWindowsWindow();
        await _bootstrapWindowsSettings(args);
        final useSimpleAndroidTheme = await _shouldUseSimpleAndroidTheme();
        if (!useSimpleAndroidTheme) {
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
              useSimpleAndroidTheme: useSimpleAndroidTheme,
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

class _LocalistApp extends StatelessWidget {
  const _LocalistApp({
    required this.settings,
    required this.useSimpleAndroidTheme,
  });

  final AppSettings settings;
  final bool useSimpleAndroidTheme;

  @override
  Widget build(BuildContext context) {
    final currentSettings = context.watch<AppSettings>();
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
      builder: _windowsCompactBuilder,
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: Duration.zero,
      themeAnimationCurve: Curves.easeInOutCubic,
      home: StartupGate(
        settings: settings,
        simple: useSimpleAndroidTheme,
        childBuilder: (onBackToLanguage) {
          return AndroidPermissionGate(
            simple: useSimpleAndroidTheme,
            onBackToLanguage: onBackToLanguage,
            child: LocalistShell(
              settings: settings,
              useSimpleAndroidTheme: useSimpleAndroidTheme,
            ),
          );
        },
      ),
    );
  }
}

Future<bool> _shouldUseSimpleAndroidTheme() async {
  if (!Platform.isAndroid) {
    return false;
  }
  try {
    final sdkInt = await NativeBridgeService.instance.getAndroidSdkInt();
    return sdkInt != null && sdkInt < _android13Sdk;
  } catch (_) {
    return false;
  }
}

Future<void> _bootstrapWindowsWindow() async {
  if (!Platform.isWindows) {
    return;
  }
  await windowManager.ensureInitialized();
}

Widget _windowsCompactBuilder(BuildContext context, Widget? child) {
  if (!Platform.isWindows) {
    return child ?? const Offstage();
  }
  final theme = Theme.of(context);
  return MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(.84)),
    child: Theme(
      data: theme.copyWith(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        iconTheme: theme.iconTheme.copyWith(size: 20),
        appBarTheme: theme.appBarTheme.copyWith(toolbarHeight: 46),
        navigationBarTheme: theme.navigationBarTheme.copyWith(height: 62),
      ),
      child: child ?? const Offstage(),
    ),
  );
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
    required this.useSimpleAndroidTheme,
  });

  final AppSettings settings;
  final bool useSimpleAndroidTheme;

  @override
  State<LocalistShell> createState() => _LocalistShellState();
}

class _LocalistShellState extends State<LocalistShell>
    with WindowListener, tray.TrayListener {
  final NativeBridgeService _bridge = NativeBridgeService.instance;
  final LocalistDiscoveryService _discovery = LocalistDiscoveryService.instance;
  final LocalistPeerService _peerService = LocalistPeerService.instance;
  final QuickSendService _quickSend = QuickSendService.instance;
  final AppUpdateService _updates = AppUpdateService();
  final LogService _logs = LogService.instance;
  late final PageController _pageController;
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    if (Platform.isWindows) {
      windowManager.addListener(this);
      tray.trayManager.addListener(this);
      unawaited(_configureWindowsWindow());
    }
    widget.settings.addListener(_handleSettingsChanged);
    _discovery.addListener(_handleDiscoveryChanged);
    _peerService.addListener(_handlePeersChanged);
    unawaited(_quickSend.initialize());
    _refreshState();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshState(quiet: true),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showOnboardingGuideIfNeeded();
      _checkForStartupUpdate();
    });
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      tray.trayManager.removeListener(this);
    }
    widget.settings.removeListener(_handleSettingsChanged);
    _discovery.removeListener(_handleDiscoveryChanged);
    _peerService.removeListener(_handlePeersChanged);
    unawaited(_discovery.stop());
    unawaited(_peerService.stop());
    unawaited(_quickSend.disposeService());
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
    const initialSize = Size(440, 680);
    const minimumSize = Size(440, 680);
    const maximumSize = Size(440, 8192);
    try {
      final iconPath = _windowsBundledAssetPath('ico/logo.ico');
      await windowManager.setTitle('Localist');
      await windowManager.setSize(initialSize);
      await windowManager.setMinimumSize(minimumSize);
      await windowManager.setMaximumSize(maximumSize);
      await windowManager.setResizable(true);
      await windowManager.setMaximizable(false);
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
      onTap: () => _setPage(1, force: true),
    );
  }

  Future<void> _checkForStartupUpdate() async {
    if (_startupUpdateChecked || !Platform.isAndroid) {
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
        onTap: () => _setPage(3, force: true),
      );
    } catch (error) {
      _logs.warning('Startup update check failed: $error');
    }
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
    final statsAvailable = _statsAvailable;
    final simpleVisuals = widget.useSimpleAndroidTheme;
    final navItems = _navItems(l10n);
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
      KeepAlivePage(child: const QuickSendPage()),
      KeepAlivePage(
        child: SettingsPage(
          settings: widget.settings,
          portsLocked: _sharingActive,
        ),
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: GlassBackground(
        simple: widget.useSimpleAndroidTheme,
        child: Scaffold(
          extendBody: !simpleVisuals,
          backgroundColor: simpleVisuals
              ? Theme.of(context).colorScheme.surface
              : Colors.transparent,
          appBar: GlassAppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Localist'),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: l10n.appGuide,
                  onPressed: _showOnboardingGuide,
                  icon: const Icon(Icons.help_outline),
                ),
              ],
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
                  duration: const Duration(milliseconds: 260),
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
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: PageView(
              controller: _pageController,
              physics: const PageScrollPhysics(),
              onPageChanged: _handlePageChanged,
              children: pages,
            ),
          ),
          floatingActionButton: statsAvailable
              ? FloatingActionButton.extended(
                  heroTag: 'stats-button',
                  onPressed: _showStatsSheet,
                  icon: const Icon(Icons.query_stats),
                  label: Text(l10n.stats),
                )
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: GlassPanel(
              padding: EdgeInsets.zero,
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _goToPage,
                backgroundColor: Colors.transparent,
                indicatorColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: .18),
                destinations: [
                  for (var i = 0; i < navItems.length; i++)
                    NavigationDestination(
                      icon: AnimatedNavIcon(
                        icon: navItems[i].icon,
                        selected: _index == i,
                      ),
                      selectedIcon: AnimatedNavIcon(
                        icon: navItems[i].selectedIcon,
                        selected: true,
                      ),
                      label: navItems[i].label,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
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
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
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
      _NavItem(l10n.sharing, Icons.share_outlined, Icons.share),
      _NavItem(l10n.receiving, Icons.qr_code_scanner, Icons.qr_code_2),
      const _NavItem('Quick Send', Icons.send_outlined, Icons.send),
      _NavItem(l10n.settings, Icons.tune_outlined, Icons.tune),
    ];
  }

  void _toggleTheme(ThemeSettingsModel themeSettings) {
    _logs.debug(
      'Theme toggle button pressed current=${themeSettings.themeMode.name}',
    );
    themeSettings.setThemeMode(
      themeSettings.isDarkMode ? ThemeMode.light : ThemeMode.dark,
    );
  }

  Future<void> _showOnboardingGuideIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadySeen = prefs.getBool(_onboardingSeenKey) ?? false;
    if (alreadySeen || !mounted) {
      return;
    }
    await prefs.setBool(_onboardingSeenKey, true);
    if (mounted) {
      await _showOnboardingGuide();
    }
  }

  Future<void> _showOnboardingGuide() {
    _logs.debug('Onboarding guide opened');
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: .32),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(curved),
            child: const _OnboardingGuideDialog(),
          ),
        );
      },
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
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

class _OnboardingGuideDialog extends StatelessWidget {
  const _OnboardingGuideDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.guideWelcome,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _GuideStep(
                  emoji: '📤',
                  title: l10n.guideSharingTitle,
                  body: Platform.isWindows
                      ? l10n.guideSharingWindows
                      : l10n.guideSharingAndroid,
                ),
                _GuideStep(
                  emoji: '📷',
                  title: l10n.guideQrTitle,
                  body: l10n.guideQrBody,
                ),
                _GuideStep(
                  emoji: '📥',
                  title: l10n.guideReceivingTitle,
                  body: l10n.guideReceivingBody,
                ),
                _GuideStep(
                  emoji: '🛡️',
                  title: l10n.guideStartVpnTitle,
                  body: l10n.guideStartVpnBody,
                ),
                _GuideStep(
                  emoji: '🧭',
                  title: l10n.guideMenusTitle,
                  body: l10n.guideMenusBody,
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.gotIt),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.emoji,
    required this.title,
    required this.body,
  });

  final String emoji;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(body, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
