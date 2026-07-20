import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_you_dynamic_theme/material_you_dynamic_theme.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../services/app_update_service.dart';
import '../services/log_service.dart';
import '../services/native_bridge_service.dart';
import '../widgets/glass.dart';

const _appName = 'Localist';
const _appDeveloper = 'PRS';
const _appPackageName = 'com.prs.localist';
const _windowsAppId = 'PRS.Localist';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.portsLocked,
  });

  final AppSettings settings;
  final bool portsLocked;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final NativeBridgeService _bridge = NativeBridgeService.instance;
  final LogService _logs = LogService.instance;
  late final TextEditingController _httpPortController;
  late final TextEditingController _socks5PortController;
  bool _rootBusy = false;
  bool _hasPortEdits = false;
  bool _portsSaving = false;
  bool _syncingPortControllers = false;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _httpPortController = TextEditingController(
      text: widget.settings.portFor(ProxyProtocol.http).toString(),
    );
    _socks5PortController = TextEditingController(
      text: widget.settings.portFor(ProxyProtocol.socks5).toString(),
    );
    _httpPortController.addListener(_handlePortTextChanged);
    _socks5PortController.addListener(_handlePortTextChanged);
    widget.settings.addListener(_syncPortControllersFromSettings);
    unawaited(_loadAppVersion());
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncPortControllersFromSettings);
    _httpPortController.removeListener(_handlePortTextChanged);
    _socks5PortController.removeListener(_handlePortTextChanged);
    _httpPortController.dispose();
    _socks5PortController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_syncPortControllersFromSettings);
      widget.settings.addListener(_syncPortControllersFromSettings);
      _syncPortControllersFromSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final themeSettings = context.watch<ThemeSettingsModel>();
    final dynamicColorsAvailable = context
        .watch<BrightnessGetColorScheme>()
        .isDynamicColorSupported;
    final isWindows = Platform.isWindows;
    final logoSize = isWindows ? 56.0 : 72.0;
    final settingsPath = isWindows ? _windowsSettingsPath() : null;
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, _) {
        final portErrors = {
          for (final protocol in ProxyProtocol.values)
            protocol: _enabledPortError(protocol),
        };
        final proxySettingsLocked = widget.portsLocked;
        final canSavePorts =
            _portsChanged &&
            portErrors.values.every((error) => error == null) &&
            !proxySettingsLocked &&
            !_portsSaving;
        return PageSurface(
          children: [
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.proxy,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (!isWindows) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: _rootBusy
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.admin_panel_settings_outlined),
                      title: Text(l10n.rootVpnSharing),
                      subtitle: Text(
                        widget.settings.rootRoutingEnabled
                            ? l10n.proxyModeDisabled
                            : l10n.useProxyModeWithoutRoot,
                      ),
                      value: widget.settings.rootRoutingEnabled,
                      onChanged: _rootBusy ? null : _setRootRoutingEnabled,
                    ),
                  ],
                  if (isWindows || !widget.settings.rootRoutingEnabled) ...[
                    const SizedBox(height: 12),
                    for (final protocol in ProxyProtocol.values)
                      _ProtocolToggle(
                        settings: widget.settings,
                        protocol: protocol,
                        enabled: !proxySettingsLocked,
                      ),
                    for (final protocol in ProxyProtocol.values)
                      if (widget.settings.isProtocolEnabled(protocol)) ...[
                        const SizedBox(height: 12),
                        _ProtocolPortField(
                          protocol: protocol,
                          controller: _portControllerFor(protocol),
                          errorText: portErrors[protocol],
                          enabled: !proxySettingsLocked,
                          onSubmitted: (_) => _savePorts(),
                        ),
                      ],
                    if (proxySettingsLocked) ...[
                      const SizedBox(height: 10),
                      const _LockedPortsNotice(),
                    ],
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: _portsChanged || _portsSaving
                          ? Padding(
                              key: const ValueKey('save-ports'),
                              padding: const EdgeInsets.only(top: 12),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.icon(
                                  onPressed: canSavePorts ? _savePorts : null,
                                  icon: _portsSaving
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.save_outlined),
                                  label: Text(l10n.savePorts),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
            if (isWindows)
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.windowClose,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _WindowsCloseBehaviorSelector(settings: widget.settings),
                  ],
                ),
              ),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.languageSettingsTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.languageSettingsSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<AppLanguage>(
                      expandedInsets: EdgeInsets.zero,
                      segments: [
                        ButtonSegment(
                          value: AppLanguage.system,
                          icon: const Icon(Icons.language),
                          label: Text(l10n.languageSystem),
                        ),
                        ButtonSegment(
                          value: AppLanguage.english,
                          icon: const Icon(Icons.flag_outlined),
                          label: Text(l10n.languageEnglish),
                        ),
                        ButtonSegment(
                          value: AppLanguage.persian,
                          icon: const Icon(Icons.flag_outlined),
                          label: Text(l10n.languagePersian),
                        ),
                      ],
                      selected: {widget.settings.language},
                      onSelectionChanged: (values) {
                        widget.settings.setLanguage(values.single);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const _UpdatePanel(),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.debugging,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.bug_report_outlined),
                    title: Text(l10n.activeDebugMode),
                    subtitle: Text(l10n.activeDebugModeSubtitle),
                    value: widget.settings.activeDebugMode,
                    onChanged: widget.settings.setActiveDebugMode,
                  ),
                ],
              ),
            ),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.theme,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      expandedInsets: EdgeInsets.zero,
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: const Icon(Icons.brightness_auto),
                          label: Text(l10n.themeSystem),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: const Icon(Icons.light_mode_outlined),
                          label: Text(l10n.themeLight),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: const Icon(Icons.dark_mode_outlined),
                          label: Text(l10n.themeDark),
                        ),
                      ],
                      selected: {themeSettings.themeMode},
                      onSelectionChanged: (values) {
                        themeSettings.setThemeMode(values.single);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.useMaterialYouColors),
                    subtitle: Text(
                      dynamicColorsAvailable
                          ? isWindows
                                ? l10n.usesWindowsAccentColors
                                : l10n.usesAndroidWallpaperColors
                          : isWindows
                          ? l10n.unavailableWindows
                          : l10n.unavailableAndroid,
                    ),
                    value:
                        dynamicColorsAvailable &&
                        themeSettings.colorSchemeType == ColorSchemeType.system,
                    onChanged: dynamicColorsAvailable
                        ? (value) => themeSettings.setColorSchemeType(
                            value
                                ? ColorSchemeType.system
                                : ColorSchemeType.custom,
                          )
                        : null,
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child:
                        !dynamicColorsAvailable ||
                            themeSettings.colorSchemeType ==
                                ColorSchemeType.custom
                        ? _SeedColorPicker(themeSettings: themeSettings)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.appInfo,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'ico/logo.png',
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _appName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.developedBy(_appDeveloper),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  MetricTile(
                    label: l10n.version,
                    value: _appVersion ?? l10n.loading,
                    icon: Icons.tag_outlined,
                  ),
                  const SizedBox(height: 10),
                  MetricTile(
                    label: isWindows ? l10n.platform : l10n.package,
                    value: isWindows ? l10n.windowsDesktop : _appPackageName,
                    icon: isWindows
                        ? Icons.desktop_windows_outlined
                        : Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: 10),
                  MetricTile(
                    label: isWindows ? l10n.appId : l10n.developer,
                    value: isWindows ? _windowsAppId : _appDeveloper,
                    icon: isWindows
                        ? Icons.verified_outlined
                        : Icons.badge_outlined,
                  ),
                  if (settingsPath != null) ...[
                    const SizedBox(height: 10),
                    MetricTile(
                      label: l10n.settingsPath,
                      value: settingsPath,
                      icon: Icons.folder_outlined,
                      wrapValue: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _windowsSettingsPath() {
    final appData = Platform.environment['APPDATA'];
    final root = appData == null || appData.isEmpty ? r'%APPDATA%' : appData;
    return '$root\\PRS\\Localist\\shared_preferences.json';
  }

  bool get _portsChanged {
    return ProxyProtocol.values.any((protocol) {
      if (!widget.settings.isProtocolEnabled(protocol)) {
        return false;
      }
      return _portControllerFor(protocol).text.trim() !=
          widget.settings.portFor(protocol).toString();
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final pubspec = await rootBundle.loadString('pubspec.yaml');
      final version = _parsePubspecVersion(pubspec);
      if (mounted) {
        setState(() => _appVersion = version);
      }
    } catch (error) {
      _logs.warning('Unable to load app version: $error');
    }
  }

  String _parsePubspecVersion(String pubspec) {
    for (final line in pubspec.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('version:')) {
        return _versionNameOnly(trimmed.substring('version:'.length).trim());
      }
    }
    return context.l10n.development;
  }

  String _versionNameOnly(String value) {
    return value.split('+').first.trim();
  }

  void _handlePortTextChanged() {
    if (_syncingPortControllers || !mounted) {
      return;
    }
    setState(() => _hasPortEdits = _portsChanged);
  }

  void _syncPortControllersFromSettings() {
    if (_hasPortEdits) {
      return;
    }
    _syncingPortControllers = true;
    _setControllerText(
      _httpPortController,
      widget.settings.portFor(ProxyProtocol.http).toString(),
    );
    _setControllerText(
      _socks5PortController,
      widget.settings.portFor(ProxyProtocol.socks5).toString(),
    );
    _syncingPortControllers = false;
    if (mounted) {
      setState(() {});
    }
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  String? _portError(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return context.l10n.required;
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null) {
      return context.l10n.numbersOnly;
    }
    if (parsed < 1024 || parsed > 65535) {
      return context.l10n.portRange1024To65535;
    }
    return null;
  }

  String? _enabledPortError(ProxyProtocol protocol) {
    if (!_hasPortEdits || !widget.settings.isProtocolEnabled(protocol)) {
      return null;
    }
    return _portError(_portControllerFor(protocol).text);
  }

  TextEditingController _portControllerFor(ProxyProtocol protocol) {
    return switch (protocol) {
      ProxyProtocol.http => _httpPortController,
      ProxyProtocol.socks5 => _socks5PortController,
    };
  }

  Future<void> _savePorts() async {
    if (widget.portsLocked) {
      showLocalistNotice(
        context,
        message: context.l10n.stopSharingBeforeChangingPorts,
        tone: InAppNoticeTone.warning,
      );
      return;
    }
    final httpPort = int.tryParse(_httpPortController.text.trim());
    final socks5Port = int.tryParse(_socks5PortController.text.trim());
    if (_enabledPortError(ProxyProtocol.http) != null ||
        _enabledPortError(ProxyProtocol.socks5) != null ||
        (widget.settings.isProtocolEnabled(ProxyProtocol.http) &&
            httpPort == null) ||
        (widget.settings.isProtocolEnabled(ProxyProtocol.socks5) &&
            socks5Port == null)) {
      showLocalistNotice(
        context,
        message: context.l10n.enterValidPortsFirst,
        tone: InAppNoticeTone.warning,
      );
      return;
    }

    setState(() => _portsSaving = true);
    try {
      if (widget.settings.isProtocolEnabled(ProxyProtocol.http) &&
          widget.settings.portFor(ProxyProtocol.http) != httpPort) {
        await widget.settings.setProtocolPort(ProxyProtocol.http, httpPort!);
      }
      if (widget.settings.isProtocolEnabled(ProxyProtocol.socks5) &&
          widget.settings.portFor(ProxyProtocol.socks5) != socks5Port) {
        await widget.settings.setProtocolPort(
          ProxyProtocol.socks5,
          socks5Port!,
        );
      }
      _logs.info('Proxy ports saved');
      if (mounted) {
        showLocalistNotice(
          context,
          message: context.l10n.portsSaved,
          tone: InAppNoticeTone.success,
        );
      }
    } finally {
      if (mounted) {
        _hasPortEdits = false;
        _syncPortControllersFromSettings();
        setState(() => _portsSaving = false);
      }
    }
  }

  Future<void> _setRootRoutingEnabled(bool enabled) async {
    if (Platform.isWindows && !enabled) {
      return;
    }
    setState(() => _rootBusy = true);
    try {
      final root = await _bridge.setRootRoutingEnabled(enabled);
      if (Platform.isWindows) {
        if (root.enabled || root.available) {
          await widget.settings.setRootRoutingEnabled(true);
          _logs.info('Windows administrator access enabled');
        } else {
          _logs.warning(
            root.lastError.isEmpty
                ? 'Windows administrator approval was not completed'
                : root.lastError,
          );
          if (mounted) {
            showLocalistNotice(
              context,
              message: root.lastError.isEmpty
                  ? context.l10n.approveWindowsAdminPrompt
                  : root.lastError,
              tone: InAppNoticeTone.warning,
            );
          }
        }
        return;
      }
      if (enabled && !root.available) {
        _logs.warning(
          root.lastError.isEmpty
              ? 'Root access was not granted'
              : root.lastError,
        );
        if (mounted) {
          showLocalistNotice(
            context,
            message: context.l10n.rootAccessWasNotGranted,
            tone: InAppNoticeTone.warning,
          );
        }
        await widget.settings.setRootRoutingEnabled(false);
        return;
      }
      await widget.settings.setRootRoutingEnabled(enabled);
      _logs.info(enabled ? 'Root routing enabled' : 'Root routing disabled');
    } catch (error) {
      _logs.error('Unable to change root routing: $error');
      await widget.settings.setRootRoutingEnabled(false);
      if (mounted) {
        showLocalistNotice(
          context,
          message: context.l10n.unableToChangeRootRouting,
          tone: InAppNoticeTone.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _rootBusy = false);
      }
    }
  }
}

class _WindowsCloseBehaviorSelector extends StatelessWidget {
  const _WindowsCloseBehaviorSelector({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DropdownButtonFormField<WindowsCloseBehavior>(
      initialValue: settings.windowsCloseBehavior,
      decoration: InputDecoration(
        labelText: l10n.closeButton,
        prefixIcon: const Icon(Icons.close_fullscreen_outlined),
      ),
      items: [
        DropdownMenuItem(
          value: WindowsCloseBehavior.ask,
          child: Text(l10n.askEveryTime),
        ),
        DropdownMenuItem(
          value: WindowsCloseBehavior.tray,
          child: Text(l10n.taskbarTray),
        ),
        DropdownMenuItem(
          value: WindowsCloseBehavior.exit,
          child: Text(l10n.exitLocalist),
        ),
      ],
      onChanged: (value) {
        if (value != null) {
          settings.setWindowsCloseBehavior(value);
        }
      },
    );
  }
}

class _UpdatePanel extends StatefulWidget {
  const _UpdatePanel();

  @override
  State<_UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<_UpdatePanel> {
  final AppUpdateService _updates = AppUpdateService();
  final NativeBridgeService _bridge = NativeBridgeService.instance;
  final LogService _logs = LogService.instance;
  AppUpdateCheck? _check;
  File? _downloadedApk;
  bool _checking = false;
  bool _downloading = false;
  bool _installing = false;
  bool _needsInstallPermission = false;
  double? _progress;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isWindows) {
      unawaited(_checkForUpdates(quiet: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final check = _check;
    final latestVersion = check?.release.version.toString() ?? '-';
    final currentVersion = check?.current.toString() ?? '-';
    final hasInstallableUpdate =
        check?.updateAvailable == true && check?.canInstallOnThisDevice == true;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.updates, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            l10n.updateSubtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: l10n.currentVersion,
                  value: currentVersion,
                  icon: Platform.isWindows
                      ? Icons.desktop_windows_outlined
                      : Icons.phone_android_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MetricTile(
                  label: l10n.latestVersion,
                  value: latestVersion,
                  icon: Icons.cloud_download_outlined,
                ),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            ServiceLockNotice(
              message: _message!,
              icon: _message == l10n.updaterUpToDate
                  ? Icons.check_circle_outline
                  : Icons.info_outline,
            ),
          ],
          if (_progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _checking ? null : () => _checkForUpdates(),
                icon: _checking
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  _checking ? l10n.checkingForUpdates : l10n.checkForUpdates,
                ),
              ),
              if (Platform.isAndroid && hasInstallableUpdate)
                FilledButton.icon(
                  onPressed: _downloading || _installing
                      ? null
                      : _downloadAndInstallAndroid,
                  icon: _downloading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update_alt_outlined),
                  label: Text(
                    _downloading
                        ? l10n.downloadingUpdate
                        : l10n.downloadAndInstall,
                  ),
                ),
              if (Platform.isAndroid && _needsInstallPermission)
                FilledButton.tonalIcon(
                  onPressed: _bridge.openAndroidInstallPermissionSettings,
                  icon: const Icon(Icons.security_outlined),
                  label: Text(l10n.allowInstallPermission),
                ),
              if (Platform.isAndroid && _downloadedApk != null)
                FilledButton.tonalIcon(
                  onPressed: _installing ? null : _installDownloadedApk,
                  icon: _installing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.install_mobile_outlined),
                  label: Text(l10n.installUpdate),
                ),
              if (Platform.isWindows && hasInstallableUpdate)
                FilledButton.icon(
                  onPressed: _downloading || _installing
                      ? null
                      : _downloadAndInstallWindows,
                  icon: _downloading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.system_update_alt_outlined),
                  label: Text(
                    _downloading
                        ? l10n.downloadingUpdate
                        : l10n.downloadAndInstall,
                  ),
                ),
              if (!Platform.isAndroid && !Platform.isWindows)
                FilledButton.tonalIcon(
                  onPressed: () => _bridge.openUri(localistLatestReleaseUrl),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l10n.openGithubRelease),
                ),
            ],
          ),
          if (!Platform.isAndroid && !Platform.isWindows) ...[
            const SizedBox(height: 12),
            ServiceLockNotice(
              message: l10n.updaterAndroidOnly,
              icon: Icons.phone_android_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _checkForUpdates({bool quiet = false}) async {
    _logs.debug('Update check button pressed quiet=$quiet');
    setState(() {
      _checking = true;
      _needsInstallPermission = false;
      _message = quiet ? _message : null;
    });
    try {
      final result = await _updates.checkForUpdate();
      _logs.debug(
        'Update check UI result updateAvailable=${result.updateAvailable} canInstall=${result.canInstallOnThisDevice}',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _check = result;
        _downloadedApk = null;
        _progress = null;
        _message = _messageForCheck(result);
      });
    } catch (error) {
      _logs.debug('Update check UI failed quiet=$quiet', error: error);
      if (!mounted) {
        return;
      }
      if (!quiet) {
        setState(() => _message = context.l10n.updaterFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  String _messageForCheck(AppUpdateCheck result) {
    final l10n = context.l10n;
    if (!result.updateAvailable) {
      return l10n.updaterUpToDate;
    }
    if (!result.canInstallOnThisDevice) {
      return l10n.updaterNoCompatibleApk;
    }
    return l10n.updaterAvailable(result.release.version.toString());
  }

  Future<void> _downloadAndInstallAndroid() async {
    _logs.debug('Download and install update button pressed');
    var check = _check;
    if (check == null) {
      await _checkForUpdates();
      check = _check;
    }
    final asset = check?.androidAsset;
    if (asset == null) {
      _logs.debug('Download update blocked: no compatible asset');
      setState(() => _message = context.l10n.updaterNoCompatibleApk);
      return;
    }
    final canInstall = await _bridge.canInstallAndroidPackages();
    _logs.debug('Android install permission canInstall=$canInstall');
    if (!canInstall) {
      await _bridge.openAndroidInstallPermissionSettings();
      if (mounted) {
        setState(() {
          _needsInstallPermission = true;
          _message = context.l10n.updaterInstallPermissionNeeded;
        });
      }
      return;
    }
    setState(() {
      _downloading = true;
      _needsInstallPermission = false;
      _progress = 0;
      _message = null;
    });
    try {
      final file = await _updates.downloadAndroidUpdate(
        asset,
        onProgress: (received, total) {
          if (!mounted || total <= 0) {
            return;
          }
          setState(() => _progress = received / total);
        },
      );
      if (!mounted) {
        return;
      }
      _logs.debug('Android update downloaded path=${file.path}');
      setState(() {
        _downloadedApk = file;
        _progress = 1;
        _message = context.l10n.updaterDownloaded;
      });
      await _installDownloadedApk();
    } catch (error) {
      _logs.debug('Download and install update failed', error: error);
      if (mounted) {
        setState(() => _message = context.l10n.updaterFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  Future<void> _installDownloadedApk() async {
    final apk = _downloadedApk;
    if (apk == null) {
      _logs.debug('Install downloaded APK skipped: no file');
      return;
    }
    _logs.debug('Install downloaded APK button pressed path=${apk.path}');
    final canInstall = await _bridge.canInstallAndroidPackages();
    _logs.debug('Install downloaded APK permission canInstall=$canInstall');
    if (!canInstall) {
      await _bridge.openAndroidInstallPermissionSettings();
      if (mounted) {
        setState(() {
          _needsInstallPermission = true;
          _message = context.l10n.updaterInstallPermissionNeeded;
        });
      }
      return;
    }
    setState(() {
      _installing = true;
      _needsInstallPermission = false;
    });
    try {
      final opened = await _bridge.installAndroidApk(apk.path);
      _logs.debug('Install downloaded APK result opened=$opened');
      if (mounted) {
        setState(() {
          _needsInstallPermission = !opened;
          _message = opened
              ? context.l10n.updaterInstallStarted
              : context.l10n.updaterInstallPermissionNeeded;
        });
      }
    } catch (error) {
      _logs.debug('Install downloaded APK failed', error: error);
      _logs.error('Unable to open Android update installer: $error');
      if (mounted) {
        setState(() => _message = context.l10n.updaterFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _installing = false);
      }
    }
  }

  Future<void> _downloadAndInstallWindows() async {
    _logs.debug('Windows download and install update button pressed');
    var check = _check;
    if (check == null) {
      await _checkForUpdates();
      check = _check;
    }
    final asset = check?.windowsAsset;
    if (asset == null) {
      _logs.debug('Windows update blocked: no compatible asset');
      if (mounted) {
        setState(() => _message = context.l10n.updaterNoCompatibleApk);
      }
      return;
    }
    setState(() {
      _downloading = true;
      _progress = 0;
      _message = null;
    });
    try {
      final archive = await _updates.downloadWindowsUpdate(
        asset,
        onProgress: (received, total) {
          if (!mounted || total <= 0) {
            return;
          }
          setState(() => _progress = received / total);
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _downloading = false;
        _installing = true;
        _progress = 1;
        _message = 'Preparing the Localist update…';
      });
      await _bridge.stopRootSharing();
      await _bridge.stopProxyService();
      final started = await _bridge.startWindowsUpdate(
        archivePath: archive.path,
        version: check!.release.version.toString(),
      );
      _logs.debug(
        'Windows update helper started=$started path=${archive.path}',
      );
      if (!started && mounted) {
        setState(() {
          _installing = false;
          _message = context.l10n.updaterFailed;
        });
      }
    } catch (error) {
      _logs.debug('Windows download and install update failed', error: error);
      if (mounted) {
        setState(() {
          _installing = false;
          _message = context.l10n.updaterFailed;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }
}

class _ProtocolToggle extends StatelessWidget {
  const _ProtocolToggle({
    required this.settings,
    required this.protocol,
    required this.enabled,
  });

  final AppSettings settings;
  final ProxyProtocol protocol;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final protocolEnabled = settings.isProtocolEnabled(protocol);
    final isOnlyEnabledProtocol =
        settings.enabledProtocols.length == 1 && protocolEnabled;
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.route_outlined),
      title: Text(protocol.label),
      subtitle: Text('${protocol.scheme}://host:${settings.portFor(protocol)}'),
      value: protocolEnabled,
      onChanged: enabled && !isOnlyEnabledProtocol
          ? (value) {
              LogService.instance.debug(
                'Protocol toggle changed protocol=${protocol.name} enabled=${value ?? false}',
              );
              settings.setProtocolEnabled(protocol, value ?? false);
            }
          : null,
    );
  }
}

class _ProtocolPortField extends StatelessWidget {
  const _ProtocolPortField({
    required this.protocol,
    required this.controller,
    required this.errorText,
    required this.enabled,
    required this.onSubmitted,
  });

  final ProxyProtocol protocol;
  final TextEditingController controller;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: l10n.protocolPort(protocol.label),
        prefixIcon: const Icon(Icons.numbers),
        helperText: enabled
            ? l10n.defaultPort(protocol.defaultPort)
            : l10n.lockedWhileSharingActive,
        errorText: errorText,
      ),
      onSubmitted: onSubmitted,
    );
  }
}

class _LockedPortsNotice extends StatelessWidget {
  const _LockedPortsNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.lockedPortsNotice,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeedColorPicker extends StatelessWidget {
  const _SeedColorPicker({required this.themeSettings});

  final ThemeSettingsModel themeSettings;

  static const _colors = [
    Color(0xFF3367D6),
    Color(0xFF00897B),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFC2185B),
    Color(0xFFD84315),
    Color(0xFFF9A825),
    Color(0xFF00ACC1),
    Color(0xFF039BE5),
    Color(0xFF3949AB),
    Color(0xFF8E24AA),
    Color(0xFF5E35B1),
    Color(0xFF00838F),
    Color(0xFF43A047),
    Color(0xFF7CB342),
    Color(0xFFE53935),
    Color(0xFF6D4C41),
    Color(0xFF546E7A),
    Color(0xFF795548),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('seed-color-picker'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          context.l10n.appColor,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in _colors)
              Tooltip(
                message:
                    '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => themeSettings.setSeedColor(color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            themeSettings.seedColor.toARGB32() ==
                                color.toARGB32()
                            ? scheme.onSurface
                            : scheme.outlineVariant,
                        width:
                            themeSettings.seedColor.toARGB32() ==
                                color.toARGB32()
                            ? 3
                            : 1,
                      ),
                    ),
                    child:
                        themeSettings.seedColor.toARGB32() == color.toARGB32()
                        ? Icon(Icons.check, color: scheme.onPrimary)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
