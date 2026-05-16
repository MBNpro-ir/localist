import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_you_dynamic_theme/material_you_dynamic_theme.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'models/app_settings.dart';
import 'models/service_state.dart';
import 'screens/logs_page.dart';
import 'screens/receiving_page.dart';
import 'screens/settings_page.dart';
import 'screens/sharing_page.dart';
import 'screens/stats_sheet.dart';
import 'services/log_service.dart';
import 'services/native_bridge_service.dart';
import 'widgets/glass.dart';

const _onboardingSeenKey = 'localist.onboarding.v2.seen';
const _windowsSettingsSignatureKey = 'windows.settings.signature';
const _windowsAdminBootstrapArg = '--enable-admin';
const _android13Sdk = 33;

Future<void> main(List<String> args) async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.deferFirstFrame();
  try {
    await _bootstrapWindowsWindow();
    await _bootstrapWindowsSettings(args);
    final useSimpleAndroidTheme = await _shouldUseSimpleAndroidTheme();
    if (!useSimpleAndroidTheme) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    final settings = await AppSettings.load();
    await runAppDynamic(
      title: 'Localist',
      builder: _windowsCompactBuilder,
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: Duration.zero,
      themeAnimationCurve: Curves.easeInOutCubic,
      home: LocalistShell(
        settings: settings,
        useSimpleAndroidTheme: useSimpleAndroidTheme,
      ),
    );
  } finally {
    binding.allowFirstFrame();
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
  final LogService _logs = LogService.instance;
  late final PageController _pageController;
  Timer? _refreshTimer;
  final List<_NavItem> _items = const [
    _NavItem('Sharing', Icons.share_outlined, Icons.share),
    _NavItem('Receiving', Icons.qr_code_scanner, Icons.qr_code_2),
    _NavItem('Settings', Icons.tune_outlined, Icons.tune),
  ];

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
    _refreshState();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refreshState(quiet: true),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showOnboardingGuideIfNeeded();
    });
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      tray.trayManager.removeListener(this);
    }
    widget.settings.removeListener(_handleSettingsChanged);
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
    const fixedSize = Size(350, 720);
    try {
      final iconPath = _windowsBundledAssetPath('ico/logo.ico');
      await windowManager.setTitle('Localist');
      await windowManager.setSize(fixedSize);
      await windowManager.setMinimumSize(fixedSize);
      await windowManager.setMaximumSize(fixedSize);
      await windowManager.setResizable(false);
      await windowManager.setMaximizable(false);
      await windowManager.setPreventClose(true);
      await windowManager.setIcon(iconPath);

      await tray.trayManager.setIcon(iconPath);
      await tray.trayManager.setToolTip('Localist');
      final menu = tray.Menu(
        items: [
          tray.MenuItem(key: 'open', label: 'Open'),
          tray.MenuItem.separator(),
          tray.MenuItem(key: 'close', label: 'Close'),
        ],
      );
      await tray.trayManager.setContextMenu(menu);
      _trayReady = true;
    } catch (error) {
      _logs.warning('Windows tray setup failed: $error');
    }
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
    var remember = false;
    return showDialog<_WindowsCloseDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Close Localist'),
              actionsAlignment: MainAxisAlignment.center,
              actionsOverflowAlignment: OverflowBarAlignment.center,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: remember,
                    title: const Text('Remember my choice'),
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
                  child: const Text('Cancel'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).pop(
                    _WindowsCloseDecision(
                      WindowsCloseBehavior.tray,
                      remember: remember,
                    ),
                  ),
                  icon: const Icon(Icons.system_update_alt_outlined),
                  label: const Text('Taskbar tray'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(
                    _WindowsCloseDecision(
                      WindowsCloseBehavior.exit,
                      remember: remember,
                    ),
                  ),
                  icon: const Icon(Icons.close),
                  label: const Text('Exit'),
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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Taskbar tray is not ready. Localist stayed open.'),
            ),
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
    setState(() {
      _snapshot = _snapshot.copyWith(
        protocols: widget.settings.enabledProtocols,
        protocolPorts: widget.settings.protocolPorts,
        port: widget.settings.port,
      );
    });
  }

  Future<void> _refreshState({bool quiet = false}) async {
    try {
      final snapshot = await _bridge.getServiceState(
        fallbackProtocol: widget.settings.protocol,
        fallbackPort: widget.settings.port,
        fallbackPorts: widget.settings.protocolPorts,
      );
      if (!mounted) {
        return;
      }
      setState(() => _snapshot = snapshot);
    } catch (error) {
      if (!quiet) {
        _logs.warning('Unable to refresh native state: $error');
      }
    }
  }

  Future<bool> _requestRuntimePermissions() async {
    final notification = await Permission.notification.request();
    final ok = notification.isGranted;
    if (ok) {
      _logs.info('Runtime permissions granted');
    } else {
      _logs.warning('Runtime permissions are incomplete');
    }
    return ok;
  }

  Future<void> _startSharing() async {
    if (_busy) {
      return;
    }
    if (_receivingActive) {
      _showServiceConflictMessage('Receiving', 'Sharing');
      return;
    }
    setState(() => _busy = true);
    try {
      if (!Platform.isWindows && widget.settings.rootRoutingEnabled) {
        if (!widget.settings.shareAllRoutes &&
            widget.settings.selectedLocalIps.isEmpty) {
          _logs.warning('No local IP was selected for root sharing');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Select at least one local IP.')),
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
          _logs.error(
            root.lastError.isEmpty
                ? 'Root VPN sharing did not start'
                : root.lastError,
          );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select at least one local IP.')),
          );
        }
        return;
      }
      final started = await _bridge.startProxyService(
        protocols: widget.settings.enabledProtocols,
        ports: widget.settings.protocolPorts,
        shareAllRoutes: widget.settings.shareAllRoutes,
        selectedLocalIps: widget.settings.selectedLocalIps,
        upstreamProxy:
            Platform.isWindows && widget.settings.windowsVpnProxyEnabled
            ? RemoteProxyConfig(
                protocol: ProxyProtocol.socks5,
                host: InternetAddress.loopbackIPv4.address,
                port: widget.settings.windowsVpnProxyPort,
              )
            : null,
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
      }
      await _refreshState();
    } catch (error) {
      _logs.error('Failed to start sharing: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$error'.contains('port_unavailable')
                  ? 'Port is busy. Change the protocol port in Settings.'
                  : '$error'.contains('internal_vpn_proxy_unavailable')
                  ? 'Internal VPN proxy is not reachable. Check v2rayN and the port.'
                  : 'Failed to start proxy service.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stopSharing() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _bridge.stopRootSharing();
      final stopped = await _bridge.stopProxyService();
      if (stopped) {
        _logs.info('Sharing stopped');
      }
      await _refreshState();
    } catch (error) {
      _logs.error('Failed to stop sharing: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stopReceiving() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final stopped = await _bridge.stopProxyService();
      if (stopped) {
        _logs.info('Receiving stopped');
      }
      await _refreshState();
    } catch (error) {
      _logs.error('Failed to stop receiving: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _startReceiving(RemoteProxyConfig config) async {
    if (_busy) {
      return;
    }
    if (_sharingActive) {
      _showServiceConflictMessage('Sharing', 'Receiving');
      return;
    }
    setState(() => _busy = true);
    try {
      final reachable = await _testProxyConnection(config);
      if (!reachable) {
        _logs.warning('Remote proxy is not reachable: ${config.url}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Proxy is not reachable: ${config.host}')),
          );
        }
        return;
      }
      final vpnReady = await _bridge.ensureVpnPermission();
      if (!vpnReady) {
        _logs.warning('VPN permission was not granted');
        return;
      }
      final started = await _bridge.startReceivingVpn(config);
      if (started) {
        _logs.info('prstun VPN started with ${config.url}');
      }
      await _refreshState();
    } catch (error) {
      _logs.error('Failed to start receiving VPN: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _startLocalProxy(RemoteProxyConfig config) async {
    if (_busy) {
      return;
    }
    if (_sharingActive) {
      _showServiceConflictMessage('Sharing', 'Receiving');
      return;
    }
    setState(() => _busy = true);
    try {
      final reachable = await _testProxyConnection(config);
      if (!reachable) {
        _logs.warning('Remote proxy is not reachable: ${config.url}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Proxy is not reachable: ${config.host}')),
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
      _logs.error('Failed to start local proxy: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$error'.contains('local_proxy_port_unavailable')
                  ? 'Local port 3781 is busy.'
                  : 'Failed to start local proxy.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _testProxyConnection(RemoteProxyConfig config) async {
    try {
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
        return response.length == 2 && response[0] == 0x05 && response[1] == 0;
      }
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openHotspotSettings() async {
    try {
      final opened = await _bridge.openHotspotSettings();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hotspot settings could not be opened.'),
          ),
        );
      }
    } catch (error) {
      _logs.error('Failed to open hotspot settings: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hotspot settings could not be opened.'),
          ),
        );
      }
    }
  }

  Future<void> _shareApk() async {
    try {
      final shared = await _bridge.shareApk();
      if (shared) {
        _logs.info('APK share sheet opened');
      }
    } catch (error) {
      _logs.error('Failed to share APK: $error');
    }
  }

  Future<void> _showLogsSheet() {
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
          onClose: () => Navigator.of(sheetContext).pop(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeSettings = context.watch<ThemeSettingsModel>();
    final statsAvailable = _statsAvailable;
    final simpleVisuals = widget.useSimpleAndroidTheme;
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
      SharingPage(
        settings: widget.settings,
        snapshot: _snapshot,
        busy: _busy,
        controlsLocked: _receivingActive,
        lockMessage:
            'Receiving is active. Stop Receiving before using Sharing.',
        onStartSharing: _startSharing,
        onStopSharing: _stopSharing,
        onOpenHotspotSettings: _openHotspotSettings,
        onRefresh: _refreshState,
      ),
      ReceivingPage(
        snapshot: _snapshot,
        busy: _busy,
        controlsLocked: _sharingActive,
        lockMessage: 'Sharing is active. Stop Sharing before using Receiving.',
        onStartReceiving: _startReceiving,
        onStartLocalProxy: _startLocalProxy,
        onStopReceiving: _stopReceiving,
      ),
      SettingsPage(settings: widget.settings, portsLocked: _sharingActive),
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
                  tooltip: 'App guide',
                  onPressed: _showOnboardingGuide,
                  icon: const Icon(Icons.help_outline),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Logs',
                onPressed: _showLogsSheet,
                icon: const Icon(Icons.subject_outlined),
              ),
              if (!Platform.isWindows)
                IconButton(
                  tooltip: 'Share APK',
                  onPressed: _shareApk,
                  icon: const Icon(Icons.ios_share),
                ),
              IconButton(
                tooltip: themeSettings.isDarkMode ? 'Light mode' : 'Dark mode',
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
                  label: const Text('Stats'),
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
                  for (var i = 0; i < _items.length; i++)
                    NavigationDestination(
                      icon: AnimatedNavIcon(
                        icon: _items[i].icon,
                        selected: _index == i,
                      ),
                      selectedIcon: AnimatedNavIcon(
                        icon: _items[i].selectedIcon,
                        selected: true,
                      ),
                      label: _items[i].label,
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
    _setPage(value);
  }

  void _handlePageChanged(int value) {
    setState(() => _index = value);
  }

  void _setPage(int value, {bool force = false}) {
    if (!mounted) {
      return;
    }
    if (_index == value && !force) {
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$activeService is active. Stop it before starting $targetService.',
          ),
        ),
      );
  }

  void _toggleTheme(ThemeSettingsModel themeSettings) {
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

class _OnboardingGuideDialog extends StatelessWidget {
  const _OnboardingGuideDialog();

  @override
  Widget build(BuildContext context) {
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
                        'Welcome to localist',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _GuideStep(
                  emoji: '📤',
                  title: 'Sharing',
                  body: Platform.isWindows
                      ? 'On the source computer, tap Start proxy service and scan the QR from your phone.'
                      : 'On the source device, turn on Android Hotspot manually, then tap Start proxy service.',
                ),
                const _GuideStep(
                  emoji: '📷',
                  title: 'QR codes',
                  body:
                      'Open Smart QR to share every available proxy address with the destination device.',
                ),
                const _GuideStep(
                  emoji: '📥',
                  title: 'Receiving',
                  body:
                      'On the destination device, scan the QR or paste a config, then tap Load config.',
                ),
                const _GuideStep(
                  emoji: '🛡️',
                  title: 'Start VPN',
                  body:
                      'After Proxy Config is filled, tap Start as VPN for the whole device or Start as proxy for apps with manual proxy settings.',
                ),
                const _GuideStep(
                  emoji: '🧭',
                  title: 'Menus',
                  body:
                      'Use Sharing, Receiving, Logs, and Settings from the bottom menu to control, inspect, and tune the connection.',
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Got it'),
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
