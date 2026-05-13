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

  @override
  void initState() {
    super.initState();
    _httpPortController = TextEditingController(
      text: widget.settings.portFor(ProxyProtocol.http).toString(),
    );
    _socks5PortController = TextEditingController(
      text: widget.settings.portFor(ProxyProtocol.socks5).toString(),
    );
  }

  @override
  void dispose() {
    _httpPortController.dispose();
    _socks5PortController.dispose();
    super.dispose();
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
        final httpPort = widget.settings.portFor(ProxyProtocol.http).toString();
        final socks5Port = widget.settings
            .portFor(ProxyProtocol.socks5)
            .toString();
        if (_httpPortController.text != httpPort) {
          _httpPortController.text = httpPort;
        }
        if (_socks5PortController.text != socks5Port) {
          _socks5PortController.text = socks5Port;
        }
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
                      onSave: _saveProtocolPort,
                    ),
                    const SizedBox(height: 12),
                    _ProtocolPortField(
                      protocol: ProxyProtocol.socks5,
                      controller: _socks5PortController,
                      onSave: _saveProtocolPort,
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

  void _saveProtocolPort(ProxyProtocol protocol, String value) {
    final parsed = int.tryParse(value);
    if (parsed != null) {
      widget.settings.setProtocolPort(protocol, parsed);
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
    required this.onSave,
  });

  final ProxyProtocol protocol;
  final TextEditingController controller;
  final void Function(ProxyProtocol protocol, String value) onSave;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: '${protocol.label} port',
        prefixIcon: const Icon(Icons.numbers),
        helperText: 'Default: ${protocol.defaultPort}',
      ),
      onSubmitted: (value) => onSave(protocol, value),
      onEditingComplete: () => onSave(protocol, controller.text),
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
