import 'package:flutter/material.dart';
import 'package:material_you_dynamic_theme/material_you_dynamic_theme.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../services/log_service.dart';
import '../services/native_bridge_service.dart';
import '../widgets/glass.dart';

const _appName = 'localist';
const _appVersion = '1.0.0';
const _appDeveloper = 'PRS';
const _appPackageName = 'com.prs.localist';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});

  final AppSettings settings;

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
    final themeSettings = context.watch<ThemeSettingsModel>();
    final dynamicColorsAvailable = context
        .watch<BrightnessGetColorScheme>()
        .isDynamicColorSupported;
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, _) {
        final httpError = _hasPortEdits
            ? _portError(_httpPortController.text)
            : null;
        final socks5Error = _hasPortEdits
            ? _portError(_socks5PortController.text)
            : null;
        final canSavePorts =
            _portsChanged &&
            httpError == null &&
            socks5Error == null &&
            !_portsSaving;
        return PageSurface(
          children: [
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Proxy', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: _rootBusy
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('Root VPN sharing'),
                    subtitle: Text(
                      widget.settings.rootRoutingEnabled
                          ? 'Proxy mode is disabled'
                          : 'Use proxy mode without root',
                    ),
                    value: widget.settings.rootRoutingEnabled,
                    onChanged: _rootBusy ? null : _setRootRoutingEnabled,
                  ),
                  if (!widget.settings.rootRoutingEnabled) ...[
                    const SizedBox(height: 12),
                    for (final protocol in ProxyProtocol.values)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.route_outlined),
                        title: Text(protocol.label),
                        subtitle: Text(
                          '${protocol.scheme}://host:${widget.settings.portFor(protocol)}',
                        ),
                        value: widget.settings.isProtocolEnabled(protocol),
                        onChanged:
                            widget.settings.enabledProtocols.length == 1 &&
                                widget.settings.isProtocolEnabled(protocol)
                            ? null
                            : (value) => widget.settings.setProtocolEnabled(
                                protocol,
                                value ?? false,
                              ),
                      ),
                    const SizedBox(height: 12),
                    _ProtocolPortField(
                      protocol: ProxyProtocol.http,
                      controller: _httpPortController,
                      errorText: httpError,
                      onSubmitted: (_) => _savePorts(),
                    ),
                    const SizedBox(height: 12),
                    _ProtocolPortField(
                      protocol: ProxyProtocol.socks5,
                      controller: _socks5PortController,
                      errorText: socks5Error,
                      onSubmitted: (_) => _savePorts(),
                    ),
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
                                  label: const Text('Save ports'),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {themeSettings.themeMode},
                    onSelectionChanged: (values) {
                      themeSettings.setThemeMode(values.single);
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use Material You colors'),
                    subtitle: Text(
                      dynamicColorsAvailable
                          ? 'Uses Android wallpaper colors'
                          : 'Unavailable on this Android version',
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
                    'App info',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'ico/logo.png',
                          width: 72,
                          height: 72,
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
                              'Developer: $_appDeveloper',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const MetricTile(
                    label: 'Version',
                    value: _appVersion,
                    icon: Icons.tag_outlined,
                  ),
                  const SizedBox(height: 10),
                  const MetricTile(
                    label: 'Package',
                    value: _appPackageName,
                    icon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: 10),
                  const MetricTile(
                    label: 'Developer',
                    value: _appDeveloper,
                    icon: Icons.badge_outlined,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  bool get _portsChanged {
    return _httpPortController.text.trim() !=
            widget.settings.portFor(ProxyProtocol.http).toString() ||
        _socks5PortController.text.trim() !=
            widget.settings.portFor(ProxyProtocol.socks5).toString();
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
      return 'Required';
    }
    final parsed = int.tryParse(trimmed);
    if (parsed == null) {
      return 'Numbers only';
    }
    if (parsed < 1024 || parsed > 65535) {
      return 'Use 1024-65535';
    }
    return null;
  }

  Future<void> _savePorts() async {
    final httpPort = int.tryParse(_httpPortController.text.trim());
    final socks5Port = int.tryParse(_socks5PortController.text.trim());
    if (_portError(_httpPortController.text) != null ||
        _portError(_socks5PortController.text) != null ||
        httpPort == null ||
        socks5Port == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter valid ports first.')));
      return;
    }

    setState(() => _portsSaving = true);
    try {
      if (widget.settings.portFor(ProxyProtocol.http) != httpPort) {
        await widget.settings.setProtocolPort(ProxyProtocol.http, httpPort);
      }
      if (widget.settings.portFor(ProxyProtocol.socks5) != socks5Port) {
        await widget.settings.setProtocolPort(ProxyProtocol.socks5, socks5Port);
      }
      _logs.info('Proxy ports saved');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ports saved')));
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
    setState(() => _rootBusy = true);
    try {
      final root = await _bridge.setRootRoutingEnabled(enabled);
      if (enabled && !root.available) {
        _logs.warning(
          root.lastError.isEmpty
              ? 'Root access was not granted'
              : root.lastError,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Root access was not granted')),
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
    } finally {
      if (mounted) {
        setState(() => _rootBusy = false);
      }
    }
  }
}

class _ProtocolPortField extends StatelessWidget {
  const _ProtocolPortField({
    required this.protocol,
    required this.controller,
    required this.errorText,
    required this.onSubmitted,
  });

  final ProxyProtocol protocol;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: '${protocol.label} port',
        prefixIcon: const Icon(Icons.numbers),
        helperText: 'Default: ${protocol.defaultPort}',
        errorText: errorText,
      ),
      onSubmitted: onSubmitted,
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
        Text('App color', style: Theme.of(context).textTheme.titleMedium),
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
