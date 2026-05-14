import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/app_settings.dart';
import '../models/service_state.dart';
import '../services/native_bridge_service.dart';
import '../widgets/glass.dart';

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
  final VoidCallback onStartSharing;
  final VoidCallback onStopSharing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final oppositeServiceActive = controlsLocked && !running;
    final actionLabel = busy
        ? running
              ? 'Stopping sharing...'
              : rootMode
              ? 'Starting root VPN...'
              : 'Starting proxy service...'
        : running
        ? 'Stop sharing'
        : rootMode
        ? 'Start root VPN sharing'
        : 'Start proxy service';
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sharing Control',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: busy || oppositeServiceActive ? null : onRefresh,
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Share on all route IPs'),
            subtitle: Text(
              settings.shareAllRoutes
                  ? 'All detected local IPs can serve proxy'
                  : 'Choose the exact local IPs that should serve proxy',
            ),
            value: settings.shareAllRoutes,
            onChanged: busy || running || oppositeServiceActive
                ? null
                : (value) => settings.setShareAllRoutes(value),
          ),
          if (settings.shareAllRoutes) ...[
            const SizedBox(height: 10),
            _LocalProxyIpsTile(
              value: localIps.isEmpty
                  ? (fallbackIp.isEmpty
                        ? isWindows
                              ? 'Connect this PC to a network, then refresh.'
                              : 'Turn on Android Hotspot, then refresh.'
                        : fallbackIp)
                  : localIps.join('\n'),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Allowed proxy IPs',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (localIps.isEmpty)
              const MetricTile(
                label: 'Local IPs',
                value: 'No local IPs detected',
                icon: Icons.lan_outlined,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final ip in localIps)
                    FilterChip(
                      avatar: const Icon(Icons.lan_outlined, size: 18),
                      label: Text(ip),
                      selected: settings.isLocalIpSelected(ip),
                      onSelected: busy || running || oppositeServiceActive
                          ? null
                          : (selected) =>
                                settings.setLocalIpSelected(ip, selected),
                    ),
                ],
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
                        ? 'Root via ${snapshot.root.vpnInterface}'
                        : 'Root VPN sharing',
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
                  label: Text('VPN proxy :${settings.windowsVpnProxyPort}'),
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
            labelText: 'Internal VPN proxy',
            prefixIcon: const Icon(Icons.vpn_lock_outlined),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 48,
            ),
            suffixIcon: Tooltip(
              message: 'Use internal VPN proxy',
              child: Checkbox(
                value: _enabledDraft,
                onChanged: widget.enabled
                    ? (value) => setState(() {
                        _enabledDraft = value ?? false;
                      })
                    : null,
              ),
            ),
            helperText: widget.enabled
                ? _enabledDraft
                      ? 'Uses v2rayN SOCKS on 127.0.0.1'
                      : 'Off; sharing uses the Windows route'
                : 'Locked while sharing is active',
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
                      label: const Text('Save VPN proxy'),
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
      return 'Numbers only';
    }
    if (parsed < 1024 || parsed > 65535) {
      return 'Use 1024-65535';
    }
    for (final protocol in widget.settings.enabledProtocols) {
      if (widget.settings.portFor(protocol) == parsed) {
        return 'Use a different port';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final port = int.tryParse(_portController.text.trim());
    if (_portError(_portController.text) != null || port == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid VPN proxy port first.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.settings.setWindowsVpnProxy(
        enabled: _enabledDraft,
        port: port,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('VPN proxy saved')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _LocalProxyIpsTile extends StatelessWidget {
  const _LocalProxyIpsTile({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                    'Local proxy IPs',
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
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hotspot', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Turn on Android Hotspot manually, connect the receiving device to it, then refresh localist.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: busy ? null : onOpenHotspotSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open Android hotspot settings'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Refresh hotspot',
                onPressed: busy ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          MetricTile(
            label: 'Android hotspot',
            value: hotspot.active ? 'Detected' : 'Not detected',
            icon: Icons.wifi_tethering,
          ),
          const SizedBox(height: 10),
          MetricTile(
            label: 'Proxy IP',
            value: hotspot.active && hotspot.ipAddress.isNotEmpty
                ? hotspot.ipAddress
                : 'Available after hotspot is on',
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

class _ProxyQrSectionState extends State<_ProxyQrSection> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final endpoints = _buildEndpoints();
    _QrEndpoint? selected;
    for (final endpoint in endpoints) {
      if (endpoint.id == _selectedId) {
        selected = endpoint;
        break;
      }
    }

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Proxy QR codes', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (endpoints.isEmpty)
            const MetricTile(
              label: 'Proxy QR',
              value: 'No proxy endpoint is open',
              icon: Icons.qr_code_2,
            )
          else ...[
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final endpoint in endpoints)
                  _QrEndpointChip(
                    endpoint: endpoint,
                    selected: endpoint.id == _selectedId,
                    onTap: () => setState(() => _selectedId = endpoint.id),
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
                      child: _QrPreview(endpoint: selected),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  List<_QrEndpoint> _buildEndpoints() {
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
        title: 'Smart',
        subtitle: 'All proxy endpoints',
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
  const _QrPreview({required this.endpoint});

  final _QrEndpoint endpoint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              ],
            ),
            const SizedBox(height: 12),
            RepaintBoundary(
              child: Center(
                child: _CachedQrImage(
                  data: endpoint.data,
                  size: qrSize,
                  semanticLabel: '${endpoint.title} QR code',
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
                        await Clipboard.setData(
                          ClipboardData(text: endpoint.data),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Config copied')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy config'),
                    ),
                  ),
                  if (!Platform.isWindows) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Share config',
                      onPressed: () => NativeBridgeService.instance.shareText(
                        text: endpoint.data,
                        title: 'localist Smart config',
                      ),
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
