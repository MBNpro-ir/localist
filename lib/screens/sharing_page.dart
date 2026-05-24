import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/service_state.dart';
import '../services/log_service.dart';
import '../services/native_bridge_service.dart';
import '../services/v2rayng_socks_uri.dart';
import '../widgets/glass.dart';

String _lastIphoneHotspotEndpointSignature = '';

class SharingPage extends StatelessWidget {
  const SharingPage({
    super.key,
    required this.settings,
    required this.snapshot,
    required this.busy,
    required this.controlsLocked,
    required this.lockMessage,
    required this.onStartSharing,
    required this.onStopSharing,
    required this.onOpenHotspotSettings,
    required this.onRefresh,
  });

  final AppSettings settings;
  final ServiceSnapshot snapshot;
  final bool busy;
  final bool controlsLocked;
  final String lockMessage;
  final VoidCallback onStartSharing;
  final VoidCallback onStopSharing;
  final VoidCallback onOpenHotspotSettings;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final rootMode = settings.rootRoutingEnabled;
    final rootSharingMode = !Platform.isWindows && rootMode;
    final running =
        snapshot.proxyRunning || (!Platform.isWindows && snapshot.root.active);
    final activeProtocols = running
        ? snapshot.protocols
        : settings.enabledProtocols;
    final hotspot = snapshot.hotspot;
    final localIps = snapshot.localProxyIps.isNotEmpty
        ? snapshot.localProxyIps
        : snapshot.root.availableLocalIps;
    final fallbackIp = hotspot.active && hotspot.ipAddress.isNotEmpty
        ? hotspot.ipAddress
        : '';
    final endpointIps = settings.shareAllRoutes
        ? (localIps.isEmpty && fallbackIp.isNotEmpty ? [fallbackIp] : localIps)
        : localIps.where(settings.isLocalIpSelected).toList(growable: false);
    final iphoneHotspotEndpoint = endpointIps.any(
      _isIphonePersonalHotspotClientIp,
    );
    _logIphoneHotspotEndpoint(endpointIps);

    return PageSurface(
      key: const PageStorageKey<String>('sharing-page'),
      children: [
        _SharingControlPanel(
          settings: settings,
          snapshot: snapshot,
          busy: busy,
          controlsLocked: controlsLocked,
          lockMessage: lockMessage,
          running: running,
          rootMode: rootSharingMode,
          isWindows: Platform.isWindows,
          activeProtocols: activeProtocols,
          localIps: localIps,
          fallbackIp: fallbackIp,
          iphoneHotspotEndpoint: iphoneHotspotEndpoint,
          onStartSharing: onStartSharing,
          onStopSharing: onStopSharing,
          onRefresh: onRefresh,
        ),
        if (running && !Platform.isWindows)
          _HotspotPanel(
            hotspot: hotspot,
            busy: busy,
            onOpenHotspotSettings: onOpenHotspotSettings,
            onRefresh: onRefresh,
          ),
        if (running && !rootSharingMode)
          _ProxyQrSection(
            protocols: activeProtocols,
            endpointIps: endpointIps,
            portFor: snapshot.portFor,
          ),
      ],
    );
  }
}

class _SharingControlPanel extends StatelessWidget {
  const _SharingControlPanel({
    required this.settings,
    required this.snapshot,
    required this.busy,
    required this.controlsLocked,
    required this.lockMessage,
    required this.running,
    required this.rootMode,
    required this.isWindows,
    required this.activeProtocols,
    required this.localIps,
    required this.fallbackIp,
    required this.iphoneHotspotEndpoint,
    required this.onStartSharing,
    required this.onStopSharing,
    required this.onRefresh,
  });

  final AppSettings settings;
  final ServiceSnapshot snapshot;
  final bool busy;
  final bool controlsLocked;
  final String lockMessage;
  final bool running;
  final bool rootMode;
  final bool isWindows;
  final Set<ProxyProtocol> activeProtocols;
  final List<String> localIps;
  final String fallbackIp;
  final bool iphoneHotspotEndpoint;
  final VoidCallback onStartSharing;
  final VoidCallback onStopSharing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final oppositeServiceActive = controlsLocked && !running;
    final actionLabel = busy
        ? running
              ? l10n.stoppingSharing
              : rootMode
              ? l10n.startingRootVpn
              : l10n.startingProxyService
        : running
        ? l10n.stopSharing
        : rootMode
        ? l10n.startRootVpnSharing
        : l10n.startProxyService;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.sharingControl,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: l10n.refresh,
                onPressed: busy || oppositeServiceActive ? null : onRefresh,
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.shareAllRouteIps),
            subtitle: Text(
              settings.shareAllRoutes
                  ? l10n.allDetectedLocalIpsCanServeProxy
                  : l10n.chooseExactLocalIps,
            ),
            value: settings.shareAllRoutes,
            onChanged: busy || running || oppositeServiceActive
                ? null
                : (value) {
                    LogService.instance.debug(
                      'Sharing share-all-routes switch changed value=$value',
                    );
                    settings.setShareAllRoutes(value);
                  },
          ),
          if (settings.shareAllRoutes) ...[
            const SizedBox(height: 10),
            _LocalProxyIpsTile(
              value: localIps.isEmpty
                  ? (fallbackIp.isEmpty
                        ? isWindows
                              ? l10n.connectPcThenRefresh
                              : l10n.turnOnHotspotThenRefresh
                        : fallbackIp)
                  : localIps.join('\n'),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              l10n.allowedProxyIps,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _AllowedProxyIpsBox(
              child: localIps.isEmpty
                  ? MetricTile(
                      label: l10n.localIps,
                      value: l10n.noLocalIpsDetected,
                      icon: Icons.lan_outlined,
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final ip in localIps)
                          _LocalIpFilterChip(
                            ip: ip,
                            selected: settings.isLocalIpSelected(ip),
                            enabled:
                                !busy && !running && !oppositeServiceActive,
                            onSelected: (selected) {
                              LogService.instance.debug(
                                'Sharing local IP chip changed ip=$ip selected=$selected',
                              );
                              settings.setLocalIpSelected(ip, selected);
                            },
                          ),
                      ],
                    ),
            ),
          ],
          if (iphoneHotspotEndpoint) ...[
            const SizedBox(height: 12),
            ServiceLockNotice(
              message: l10n.iphoneHotspotHostCannotUseProxy,
              icon: Icons.phone_iphone_outlined,
            ),
          ],
          if (isWindows) ...[
            const SizedBox(height: 12),
            _WindowsVpnProxySettings(
              settings: settings,
              enabled: !busy && !running && !oppositeServiceActive,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (rootMode)
                Chip(
                  avatar: const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 18,
                  ),
                  label: Text(
                    snapshot.root.active
                        ? l10n.rootVia(snapshot.root.vpnInterface)
                        : l10n.rootVpnSharing,
                  ),
                )
              else
                for (final protocol in activeProtocols)
                  Chip(
                    avatar: const Icon(Icons.route_outlined, size: 18),
                    label: Text(
                      '${protocol.label} :${settings.portFor(protocol)}',
                    ),
                  ),
              if (rootMode && snapshot.root.lastError.isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.error_outline, size: 18),
                  label: Text(snapshot.root.lastError),
                ),
              if (isWindows && settings.windowsVpnProxyEnabled)
                Chip(
                  avatar: const Icon(Icons.vpn_lock_outlined, size: 18),
                  label: Text(l10n.vpnProxyPort(settings.windowsVpnProxyPort)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy || oppositeServiceActive
                  ? null
                  : (running ? onStopSharing : onStartSharing),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      running ? Icons.stop_circle_outlined : Icons.play_circle,
                    ),
              label: Text(actionLabel),
            ),
          ),
          if (oppositeServiceActive) ...[
            const SizedBox(height: 12),
            ServiceLockNotice(message: lockMessage),
          ],
        ],
      ),
    );
  }
}

class _WindowsVpnProxySettings extends StatefulWidget {
  const _WindowsVpnProxySettings({
    required this.settings,
    required this.enabled,
  });

  final AppSettings settings;
  final bool enabled;

  @override
  State<_WindowsVpnProxySettings> createState() =>
      _WindowsVpnProxySettingsState();
}

class _WindowsVpnProxySettingsState extends State<_WindowsVpnProxySettings> {
  late final TextEditingController _portController;
  late bool _enabledDraft;
  bool _saving = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _enabledDraft = widget.settings.windowsVpnProxyEnabled;
    _portController = TextEditingController(
      text: widget.settings.windowsVpnProxyPort.toString(),
    );
    _portController.addListener(_handleChanged);
    widget.settings.addListener(_syncFromSettings);
  }

  @override
  void didUpdateWidget(covariant _WindowsVpnProxySettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      oldWidget.settings.removeListener(_syncFromSettings);
      widget.settings.addListener(_syncFromSettings);
      _syncFromSettings();
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncFromSettings);
    _portController.removeListener(_handleChanged);
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorText = _hasEdits ? _portError(_portController.text) : null;
    final canSave =
        widget.enabled && _hasEdits && errorText == null && !_saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _portController,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l10n.internalVpnProxy,
            prefixIcon: const Icon(Icons.vpn_lock_outlined),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 48,
            ),
            suffixIcon: Tooltip(
              message: l10n.useInternalVpnProxy,
              child: Checkbox(
                value: _enabledDraft,
                onChanged: widget.enabled
                    ? (value) {
                        LogService.instance.debug(
                          'Windows VPN proxy checkbox changed value=${value ?? false}',
                        );
                        setState(() {
                          _enabledDraft = value ?? false;
                        });
                      }
                    : null,
              ),
            ),
            helperText: widget.enabled
                ? _enabledDraft
                      ? l10n.usesV2raynSocks
                      : l10n.sharingUsesWindowsRoute
                : l10n.lockedWhileSharingActive,
            errorText: errorText,
          ),
          onSubmitted: (_) {
            if (canSave) {
              _save();
            }
          },
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _hasEdits || _saving
              ? Padding(
                  key: const ValueKey('save-windows-vpn-proxy'),
                  padding: const EdgeInsets.only(top: 10),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: canSave ? _save : null,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(l10n.saveVpnProxy),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  bool get _hasEdits {
    return _enabledDraft != widget.settings.windowsVpnProxyEnabled ||
        _portController.text.trim() !=
            widget.settings.windowsVpnProxyPort.toString();
  }

  void _handleChanged() {
    if (_syncing || !mounted) {
      return;
    }
    setState(() {});
  }

  void _syncFromSettings() {
    if (_hasEdits) {
      return;
    }
    _syncing = true;
    _enabledDraft = widget.settings.windowsVpnProxyEnabled;
    final value = widget.settings.windowsVpnProxyPort.toString();
    if (_portController.text != value) {
      _portController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    _syncing = false;
    if (mounted) {
      setState(() {});
    }
  }

  String? _portError(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      return context.l10n.numbersOnly;
    }
    if (parsed < 1024 || parsed > 65535) {
      return context.l10n.portRange1024To65535;
    }
    for (final protocol in widget.settings.enabledProtocols) {
      if (widget.settings.portFor(protocol) == parsed) {
        return context.l10n.useDifferentPort;
      }
    }
    return null;
  }

  Future<void> _save() async {
    final port = int.tryParse(_portController.text.trim());
    if (_portError(_portController.text) != null || port == null) {
      showLocalistNotice(
        context,
        message: context.l10n.enterValidVpnProxyPortFirst,
        tone: InAppNoticeTone.warning,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      LogService.instance.debug(
        'Windows VPN proxy settings save requested enabled=$_enabledDraft port=$port',
      );
      await widget.settings.setWindowsVpnProxy(
        enabled: _enabledDraft,
        port: port,
      );
      if (mounted) {
        showLocalistNotice(
          context,
          message: context.l10n.vpnProxySaved,
          tone: InAppNoticeTone.success,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _AllowedProxyIpsBox extends StatelessWidget {
  const _AllowedProxyIpsBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 1.4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 6, color: Colors.black),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalProxyIpsTile extends StatelessWidget {
  const _LocalProxyIpsTile({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .26)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lan_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.localProxyIps,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    value,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalIpFilterChip extends StatelessWidget {
  const _LocalIpFilterChip({
    required this.ip,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final String ip;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      avatar: Icon(selected ? Icons.check : Icons.lan_outlined, size: 18),
      label: Text(ip),
      selected: selected,
      showCheckmark: false,
      onSelected: enabled ? onSelected : null,
    );
  }
}

class _HotspotPanel extends StatelessWidget {
  const _HotspotPanel({
    required this.hotspot,
    required this.busy,
    required this.onOpenHotspotSettings,
    required this.onRefresh,
  });

  final HotspotInfo hotspot;
  final bool busy;
  final VoidCallback onOpenHotspotSettings;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.hotspot, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            l10n.hotspotInstructions,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: busy ? null : onOpenHotspotSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(l10n.openAndroidHotspotSettings),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: l10n.refreshHotspot,
                onPressed: busy ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          MetricTile(
            label: l10n.androidHotspot,
            value: hotspot.active ? l10n.detected : l10n.inactive,
            icon: Icons.wifi_tethering,
          ),
          const SizedBox(height: 10),
          MetricTile(
            label: l10n.proxyIp,
            value: hotspot.active && hotspot.ipAddress.isNotEmpty
                ? hotspot.ipAddress
                : l10n.availableAfterHotspotOn,
            icon: Icons.lan_outlined,
          ),
        ],
      ),
    );
  }
}

class _ProxyQrSection extends StatefulWidget {
  const _ProxyQrSection({
    required this.protocols,
    required this.endpointIps,
    required this.portFor,
  });

  final Set<ProxyProtocol> protocols;
  final List<String> endpointIps;
  final int Function(ProxyProtocol protocol) portFor;

  @override
  State<_ProxyQrSection> createState() => _ProxyQrSectionState();
}

enum _ProxyQrMode { proxy, ios }

class _ProxyQrSectionState extends State<_ProxyQrSection> {
  String? _selectedId;
  String? _selectedIosId;
  _ProxyQrMode _mode = _ProxyQrMode.proxy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final endpoints = _buildProxyEndpoints(l10n);
    final iosConfigs = _buildIosConfigs(l10n);
    final mode = iosConfigs.isEmpty ? _ProxyQrMode.proxy : _mode;
    _QrEndpoint? selected;
    for (final endpoint in endpoints) {
      if (endpoint.id == _selectedId) {
        selected = endpoint;
        break;
      }
    }
    _QrConfig? selectedIosConfig;
    for (final config in iosConfigs) {
      if (config.id == _selectedIosId) {
        selectedIosConfig = config;
        break;
      }
    }

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.proxyQrCodes,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (endpoints.isEmpty)
            MetricTile(
              label: l10n.proxyQr,
              value: l10n.noProxyEndpointOpen,
              icon: Icons.qr_code_2,
            )
          else ...[
            if (iosConfigs.isNotEmpty) ...[
              SegmentedButton<_ProxyQrMode>(
                segments: [
                  ButtonSegment(
                    value: _ProxyQrMode.proxy,
                    label: Text(l10n.proxyQr),
                    icon: const Icon(Icons.qr_code_2),
                  ),
                  ButtonSegment(
                    value: _ProxyQrMode.ios,
                    label: Text(l10n.ios),
                    icon: const Icon(Icons.phone_iphone_outlined),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (values) {
                  LogService.instance.debug(
                    'Proxy QR mode selected mode=${values.single.name}',
                  );
                  setState(() => _mode = values.single);
                },
              ),
              const SizedBox(height: 12),
            ],
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: mode == _ProxyQrMode.ios
                  ? _IosQrPanel(
                      key: const ValueKey('ios'),
                      configs: iosConfigs,
                      selected: selectedIosConfig,
                      selectedId: _selectedIosId,
                      onSelect: (config) => setState(() {
                        LogService.instance.debug(
                          'iOS QR config selected id=${config.id}',
                        );
                        _selectedIosId = config.id;
                      }),
                      onClose: () => setState(() {
                        LogService.instance.debug('iOS QR preview closed');
                        _selectedIosId = null;
                      }),
                    )
                  : Column(
                      key: const ValueKey('proxy'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final endpoint in endpoints)
                              _QrEndpointChip(
                                endpoint: endpoint,
                                selected: endpoint.id == _selectedId,
                                onTap: () => setState(() {
                                  LogService.instance.debug(
                                    'Proxy QR endpoint selected id=${endpoint.id}',
                                  );
                                  _selectedId = endpoint.id;
                                }),
                              ),
                          ],
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: selected == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  key: ValueKey(selected.id),
                                  padding: const EdgeInsets.only(top: 14),
                                  child: _QrPreview(
                                    endpoint: selected,
                                    onClose: () => setState(() {
                                      LogService.instance.debug(
                                        'Proxy QR preview closed',
                                      );
                                      _selectedId = null;
                                    }),
                                  ),
                                ),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }

  List<_QrEndpoint> _buildProxyEndpoints(AppLocalizations l10n) {
    final proxyEndpoints = [
      for (final protocol in widget.protocols)
        for (final ip in widget.endpointIps)
          SmartProxyEndpoint(
            protocol: protocol,
            host: ip,
            port: widget.portFor(protocol),
          ),
    ];
    if (proxyEndpoints.isEmpty) {
      return const [];
    }
    final smart = SmartProxyPayload(
      hotspotSsid: '',
      hotspotPassword: '',
      endpoints: proxyEndpoints,
    );
    return [
      _QrEndpoint(
        id: 'smart',
        title: l10n.smart,
        subtitle: l10n.allProxyEndpoints,
        data: smart.encode(),
        icon: Icons.auto_awesome_outlined,
        isSmart: true,
      ),
      for (final endpoint in proxyEndpoints)
        _QrEndpoint(
          id: '${endpoint.protocol.name}-${endpoint.host}-${endpoint.port}',
          title: endpoint.protocol.label,
          subtitle: '${endpoint.host}:${endpoint.port}',
          data: endpoint.config.url,
          icon: Icons.route_outlined,
          isSmart: false,
        ),
    ];
  }

  List<_QrConfig> _buildIosConfigs(AppLocalizations l10n) {
    return [
      for (final ip in widget.endpointIps)
        ..._buildIosConfigsForEndpoint(
          l10n,
          SmartProxyEndpoint(
            protocol: ProxyProtocol.socks5,
            host: ip,
            port: widget.portFor(ProxyProtocol.socks5),
          ),
        ),
    ];
  }

  List<_QrConfig> _buildIosConfigsForEndpoint(
    AppLocalizations l10n,
    SmartProxyEndpoint endpoint,
  ) {
    if (!widget.protocols.contains(ProxyProtocol.socks5)) {
      return const [];
    }
    final subtitle = '${endpoint.host}:${endpoint.port}';
    return [
      _QrConfig(
        id: 'ios-xray-${endpoint.host}-${endpoint.port}',
        title: l10n.xrayCore,
        subtitle: subtitle,
        data: _xraySocksConfig(endpoint),
        icon: Icons.hub_outlined,
      ),
      _QrConfig(
        id: 'ios-sing-box-${endpoint.host}-${endpoint.port}',
        title: l10n.singBoxCore,
        subtitle: subtitle,
        data: _singBoxSocksConfig(endpoint),
        icon: Icons.all_inclusive,
      ),
    ];
  }

  String _xraySocksConfig(SmartProxyEndpoint endpoint) {
    return buildV2rayNgSocksUri(
      host: endpoint.host,
      port: endpoint.port,
      name: 'Localist Xray ${endpoint.host}:${endpoint.port}',
    );
  }

  String _singBoxSocksConfig(SmartProxyEndpoint endpoint) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'log': {'level': 'warn'},
      'inbounds': [
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': 2080,
          'set_system_proxy': false,
        },
      ],
      'outbounds': [
        {
          'type': 'socks',
          'tag': 'localist-socks',
          'server': endpoint.host,
          'server_port': endpoint.port,
          'version': '5',
        },
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {'final': 'localist-socks'},
    });
  }
}

class _QrEndpointChip extends StatelessWidget {
  const _QrEndpointChip({
    required this.endpoint,
    required this.selected,
    required this.onTap,
  });

  final _QrEndpoint endpoint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: .72)
          : scheme.surfaceContainerHighest.withValues(alpha: .44),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(endpoint.icon, size: 18),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    endpoint.title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    endpoint.subtitle,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrPreview extends StatelessWidget {
  const _QrPreview({required this.endpoint, required this.onClose});

  final _QrEndpoint endpoint;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final qrSize = endpoint.isSmart ? 252.0 : 232.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .54),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_2, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${endpoint.title} - ${endpoint.subtitle}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: l10n.closeQrCode,
                  onPressed: () {
                    LogService.instance.debug(
                      'Proxy QR close button pressed id=${endpoint.id}',
                    );
                    onClose();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RepaintBoundary(
              child: Center(
                child: _CachedQrImage(
                  data: endpoint.data,
                  size: qrSize,
                  semanticLabel: l10n.qrCodeSemantic(endpoint.title),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (endpoint.isSmart)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        LogService.instance.debug(
                          'Proxy QR copy button pressed id=${endpoint.id}',
                        );
                        await Clipboard.setData(
                          ClipboardData(text: endpoint.data),
                        );
                        if (context.mounted) {
                          showLocalistNotice(
                            context,
                            message: l10n.configCopied,
                            tone: InAppNoticeTone.success,
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: Text(l10n.copyConfig),
                    ),
                  ),
                  if (!Platform.isWindows) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: l10n.shareConfig,
                      onPressed: () {
                        LogService.instance.debug(
                          'Proxy QR share button pressed id=${endpoint.id}',
                        );
                        NativeBridgeService.instance.shareText(
                          text: endpoint.data,
                          title: 'Localist ${l10n.smart}',
                        );
                      },
                      icon: const Icon(Icons.ios_share),
                    ),
                  ],
                ],
              )
            else
              SelectableText(
                endpoint.data,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _IosQrPanel extends StatelessWidget {
  const _IosQrPanel({
    super.key,
    required this.configs,
    required this.selected,
    required this.selectedId,
    required this.onSelect,
    required this.onClose,
  });

  final List<_QrConfig> configs;
  final _QrConfig? selected;
  final String? selectedId;
  final ValueChanged<_QrConfig> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final config in configs)
              _QrConfigChip(
                config: config,
                selected: config.id == selectedId,
                onTap: () => onSelect(config),
              ),
          ],
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: selected == null
              ? const SizedBox.shrink()
              : Padding(
                  key: ValueKey(selected!.id),
                  padding: const EdgeInsets.only(top: 14),
                  child: _QrConfigPreview(config: selected!, onClose: onClose),
                ),
        ),
      ],
    );
  }
}

class _QrConfigChip extends StatelessWidget {
  const _QrConfigChip({
    required this.config,
    required this.selected,
    required this.onTap,
  });

  final _QrConfig config;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: .72)
          : scheme.surfaceContainerHighest.withValues(alpha: .44),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(config.icon, size: 18),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    config.title,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    config.subtitle,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrConfigPreview extends StatelessWidget {
  const _QrConfigPreview({required this.config, required this.onClose});

  final _QrConfig config;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .54),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(config.icon, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${config.title} - ${config.subtitle}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: l10n.copyConfig,
                  onPressed: () async {
                    LogService.instance.debug(
                      'iOS QR copy button pressed id=${config.id}',
                    );
                    await Clipboard.setData(ClipboardData(text: config.data));
                    if (context.mounted) {
                      showLocalistNotice(
                        context,
                        message: l10n.configCopied,
                        tone: InAppNoticeTone.success,
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: l10n.closeQrCode,
                  onPressed: () {
                    LogService.instance.debug(
                      'iOS QR close button pressed id=${config.id}',
                    );
                    onClose();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            RepaintBoundary(
              child: Center(
                child: _CachedQrImage(
                  data: config.data,
                  size: 232,
                  semanticLabel: l10n.qrCodeSemantic(config.title),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrEndpoint {
  const _QrEndpoint({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.data,
    required this.icon,
    required this.isSmart,
  });

  final String id;
  final String title;
  final String subtitle;
  final String data;
  final IconData icon;
  final bool isSmart;
}

class _QrConfig {
  const _QrConfig({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.data,
    required this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final String data;
  final IconData icon;
}

bool _isIphonePersonalHotspotClientIp(String value) {
  final octets = value.split('.').map(int.tryParse).toList();
  if (octets.length != 4 || octets.any((octet) => octet == null)) {
    return false;
  }
  final typed = octets.cast<int>();
  return typed[0] == 172 &&
      typed[1] == 20 &&
      typed[2] == 10 &&
      typed[3] >= 2 &&
      typed[3] <= 14;
}

void _logIphoneHotspotEndpoint(List<String> endpointIps) {
  final matches = endpointIps
      .where(_isIphonePersonalHotspotClientIp)
      .toList(growable: false);
  final signature = matches.join(',');
  if (signature == _lastIphoneHotspotEndpointSignature) {
    return;
  }
  _lastIphoneHotspotEndpointSignature = signature;
  if (matches.isEmpty) {
    return;
  }
  LogService.instance.debug(
    'iPhone Personal Hotspot client IP detected: $signature. The hotspot owner may not be able to connect back to this proxy.',
  );
}

class _CachedQrImage extends StatelessWidget {
  const _CachedQrImage({
    required this.data,
    required this.size,
    required this.semanticLabel,
  });

  final String data;
  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
        ),
        child: FutureBuilder<Uint8List>(
          future: _QrRasterCache.imageFor(data: data, size: size),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Image.memory(
                snapshot.data!,
                width: size,
                height: size,
                gaplessPlayback: true,
                filterQuality: FilterQuality.none,
                semanticLabel: semanticLabel,
              );
            }
            if (snapshot.hasError) {
              return const Center(
                child: Icon(Icons.qr_code_2, color: Colors.black54),
              );
            }
            return const Center(
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QrRasterCache {
  static final Map<String, Future<Uint8List>> _cache = {};

  static Future<Uint8List> imageFor({
    required String data,
    required double size,
  }) {
    final key = '${size.toStringAsFixed(0)}::$data';
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }
    if (_cache.length >= 12) {
      _cache.remove(_cache.keys.first);
    }
    return _cache[key] = _render(data: data, size: size);
  }

  static Future<Uint8List> _render({
    required String data,
    required double size,
  }) async {
    final imageSize = size.round();
    final quietZone = (imageSize * .075).round().clamp(16, 22);
    final qrSize = imageSize - quietZone * 2;
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, imageSize.toDouble(), imageSize.toDouble()),
      Paint()..color = Colors.white,
    );
    canvas.translate(quietZone.toDouble(), quietZone.toDouble());
    painter.paint(canvas, Size.square(qrSize.toDouble()));
    final picture = recorder.endRecording();
    final image = await picture.toImage(imageSize, imageSize);
    final imageData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (imageData == null) {
      throw StateError('Unable to render QR image.');
    }
    return imageData.buffer.asUint8List();
  }
}
