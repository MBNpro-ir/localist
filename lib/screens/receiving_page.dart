import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_windows/webview_windows.dart';

import '../l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../models/service_state.dart';
import '../services/log_service.dart';
import '../services/native_bridge_service.dart';
import '../widgets/glass.dart';

const _receivingDraftConfigKey = 'receiving.draft.config';
const _receivingDraftProtocolKey = 'receiving.draft.protocol';
const _receivingDraftHostKey = 'receiving.draft.host';
const _receivingDraftPortKey = 'receiving.draft.port';

class ReceivingPage extends StatefulWidget {
  const ReceivingPage({
    super.key,
    required this.snapshot,
    required this.discoveredDevices,
    required this.discoveryScanning,
    required this.busy,
    required this.controlsLocked,
    required this.lockMessage,
    required this.onStartReceiving,
    required this.onStartLocalProxy,
    required this.onStopReceiving,
    required this.onRefreshDiscovery,
  });

  final ServiceSnapshot snapshot;
  final List<LocalistDiscoveredDevice> discoveredDevices;
  final bool discoveryScanning;
  final bool busy;
  final bool controlsLocked;
  final String lockMessage;
  final ValueChanged<RemoteProxyConfig> onStartReceiving;
  final ValueChanged<RemoteProxyConfig> onStartLocalProxy;
  final VoidCallback onStopReceiving;
  final Future<void> Function() onRefreshDiscovery;

  @override
  State<ReceivingPage> createState() => _ReceivingPageState();
}

class _ReceivingPageState extends State<ReceivingPage> {
  final NativeBridgeService _bridge = NativeBridgeService.instance;
  final LogService _logs = LogService.instance;
  final MobileScannerController _scannerController = MobileScannerController(
    autoStart: false,
    detectionTimeoutMs: 750,
    formats: const [BarcodeFormat.qrCode],
  );
  final TextEditingController _configController = TextEditingController();
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: ProxyProtocol.socks5.defaultPort.toString(),
  );

  ProxyProtocol _protocol = ProxyProtocol.socks5;
  String? _configTip;
  bool _scanning = false;
  bool _handledScan = false;
  bool _restoringDraft = false;

  @override
  void initState() {
    super.initState();
    _configController.addListener(_handleDraftChanged);
    _hostController.addListener(_handleDraftChanged);
    _portController.addListener(_handleDraftChanged);
    unawaited(_restoreDraft());
    final remote = widget.snapshot.remoteProxy;
    if (remote != null) {
      _applyConfig(remote);
    }
  }

  @override
  void didUpdateWidget(covariant ReceivingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final remote = widget.snapshot.remoteProxy;
    final running =
        widget.snapshot.receivingRunning || widget.snapshot.localProxyRunning;
    final wasRunning =
        oldWidget.snapshot.receivingRunning ||
        oldWidget.snapshot.localProxyRunning;
    if (remote != null && remote.url != oldWidget.snapshot.remoteProxy?.url) {
      _applyConfig(remote);
    }
    if ((widget.controlsLocked && !oldWidget.controlsLocked) ||
        (running && !wasRunning)) {
      if (_scanning) {
        unawaited(_stopScanner());
      }
    }
  }

  @override
  void dispose() {
    unawaited(_stopScanner());
    _scannerController.dispose();
    _configController.removeListener(_handleDraftChanged);
    _hostController.removeListener(_handleDraftChanged);
    _portController.removeListener(_handleDraftChanged);
    _configController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final running =
        widget.snapshot.receivingRunning || widget.snapshot.localProxyRunning;
    final oppositeServiceActive = widget.controlsLocked && !running;
    final vpnRunning = widget.snapshot.receivingRunning;
    final proxyRunning = widget.snapshot.localProxyRunning;
    final hostError = _hostError(_hostController.text);
    final portError = _portError(_portController.text);
    final config = _currentConfig();
    final configFieldEnabled =
        !running && !widget.busy && !oppositeServiceActive;
    final proxyFieldEnabled = !running && !oppositeServiceActive;

    return PageSurface(
      key: const PageStorageKey<String>('receiving-page'),
      children: [
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.receiving,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                running
                    ? _runningStatusText(
                        vpnRunning: vpnRunning,
                        proxyRunning: proxyRunning,
                      )
                    : 'Paste a Smart config or scan a localist QR, then load it into Proxy Config.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              _NearbyDevicesView(
                devices: widget.discoveredDevices,
                scanning: widget.discoveryScanning,
                enabled: configFieldEnabled,
                onRefresh: widget.onRefreshDiscovery,
                onTap: _showDiscoveredDevicePicker,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _configController,
                enabled: configFieldEnabled,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Smart/manual config',
                  hintText: 'localist://smart?... or http://host:2060',
                  prefixIcon: const Icon(Icons.data_object_outlined),
                  suffixIcon: _clearTextButton(
                    controller: _configController,
                    enabled: configFieldEnabled,
                    tooltip: 'Clear config',
                    afterClear: () => _configTip = null,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: widget.busy || running || oppositeServiceActive
                      ? null
                      : () => _handleConfigValue(_configController.text),
                  icon: const Icon(Icons.download_done_outlined),
                  label: const Text('Load config'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.busy || running || oppositeServiceActive
                      ? null
                      : _startScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan proxy QR'),
                ),
              ),
              if (oppositeServiceActive) ...[
                const SizedBox(height: 12),
                ServiceLockNotice(message: widget.lockMessage),
              ],
            ],
          ),
        ),
        if (_scanning)
          GlassPanel(
            padding: const EdgeInsets.all(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: _handleCapture,
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: IconButton.filled(
                        tooltip: 'Close scanner',
                        onPressed: _stopScanner,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Proxy Config',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              SegmentedButton<ProxyProtocol>(
                segments: [
                  for (final protocol in ProxyProtocol.values)
                    ButtonSegment(
                      value: protocol,
                      label: Text(protocol.label),
                      icon: const Icon(Icons.route_outlined),
                    ),
                ],
                selected: {_protocol},
                onSelectionChanged: running || oppositeServiceActive
                    ? null
                    : (values) => _setProtocol(values.single),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _hostController,
                enabled: proxyFieldEnabled,
                decoration: InputDecoration(
                  labelText: 'Proxy host',
                  prefixIcon: const Icon(Icons.dns_outlined),
                  suffixIcon: _clearTextButton(
                    controller: _hostController,
                    enabled: proxyFieldEnabled,
                    tooltip: 'Clear host',
                  ),
                  errorText: hostError,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                enabled: proxyFieldEnabled,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Proxy port',
                  prefixIcon: const Icon(Icons.numbers),
                  suffixIcon: _clearTextButton(
                    controller: _portController,
                    enabled: proxyFieldEnabled,
                    tooltip: 'Clear port',
                  ),
                  errorText: portError,
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _configTip == null
                    ? const SizedBox.shrink()
                    : Padding(
                        key: ValueKey(_configTip),
                        padding: const EdgeInsets.only(top: 12),
                        child: _ConfigTip(message: _configTip!),
                      ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.busy || oppositeServiceActive
                      ? null
                      : vpnRunning
                      ? widget.onStopReceiving
                      : proxyRunning || config == null
                      ? null
                      : () => widget.onStartReceiving(config),
                  icon: Icon(
                    vpnRunning
                        ? Icons.stop_circle_outlined
                        : Icons.vpn_key_outlined,
                  ),
                  label: Text(
                    vpnRunning
                        ? Platform.isWindows
                              ? 'Stop Windows VPN'
                              : 'Stop VPN'
                        : Platform.isWindows
                        ? 'Start Windows VPN + proxy'
                        : 'Start as VPN + proxy',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed:
                      widget.busy ||
                          vpnRunning ||
                          oppositeServiceActive ||
                          (!proxyRunning && config == null)
                      ? null
                      : proxyRunning
                      ? widget.onStopReceiving
                      : () => widget.onStartLocalProxy(config!),
                  icon: Icon(
                    proxyRunning
                        ? Icons.stop_circle_outlined
                        : Icons.settings_ethernet,
                  ),
                  label: Text(proxyRunning ? 'Stop proxy' : 'Start as proxy'),
                ),
              ),
              if (config != null) ...[
                const SizedBox(height: 12),
                SelectableText(config.url),
              ],
            ],
          ),
        ),
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Proxy Apps', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Apps with their own proxy setting can use 127.0.0.1:3781 after Start as VPN or Start as proxy.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: proxyRunning && !oppositeServiceActive
                      ? _openTelegramProxy
                      : null,
                  icon: const Icon(Icons.telegram),
                  label: Text(
                    Platform.isWindows
                        ? 'Open Telegram Desktop proxy'
                        : 'Open Telegram proxy',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openTelegramProxy() async {
    try {
      final opened = await _bridge.openUri(
        'tg://socks?server=127.0.0.1&port=3781',
      );
      if (!opened && mounted) {
        showLocalistNotice(
          context,
          message: 'Telegram could not be opened.',
          tone: InAppNoticeTone.warning,
        );
      }
    } catch (error) {
      _logs.error('Unable to open Telegram proxy link: $error');
      if (mounted) {
        showLocalistNotice(
          context,
          message: 'Telegram could not be opened.',
          tone: InAppNoticeTone.warning,
        );
      }
    }
  }

  Widget? _clearTextButton({
    required TextEditingController controller,
    required bool enabled,
    required String tooltip,
    VoidCallback? afterClear,
  }) {
    if (!enabled || controller.text.isEmpty) {
      return null;
    }
    return IconButton(
      tooltip: tooltip,
      onPressed: () {
        controller.clear();
        if (afterClear != null && mounted) {
          setState(afterClear);
        }
      },
      icon: const Icon(Icons.close),
    );
  }

  Future<void> _showPermissionPopup({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          FilledButton(
            onPressed: () {
              openAppSettings();
              Navigator.of(context).pop();
            },
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  String _runningStatusText({
    required bool vpnRunning,
    required bool proxyRunning,
  }) {
    if (vpnRunning && proxyRunning) {
      return Platform.isWindows
          ? 'Windows VPN mode and local proxy are active on 127.0.0.1:3781.'
          : 'prstun VPN and local proxy are active on 127.0.0.1:3781.';
    }
    if (proxyRunning) {
      return 'Local proxy is active on 127.0.0.1:3781.';
    }
    return Platform.isWindows
        ? 'Windows VPN mode is active.'
        : 'prstun VPN receiving mode is active.';
  }

  Future<void> _startScanner() async {
    if (widget.controlsLocked) {
      return;
    }
    if (Platform.isWindows) {
      await _startWindowsScanner();
      return;
    }
    final permission = await Permission.camera.request();
    if (!permission.isGranted) {
      if (mounted) {
        await _showPermissionPopup(
          title: 'Camera permission required',
          message: 'Localist needs camera access to scan proxy QR configs.',
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _handledScan = false;
      _scanning = true;
    });
    await _scannerController.start();
  }

  Future<void> _startWindowsScanner() async {
    final String? device;
    try {
      device = await _chooseWindowsCameraDevice();
    } catch (error) {
      _logs.error('Unable to start Windows QR scanner: $error');
      if (mounted) {
        showLocalistNotice(
          context,
          message: 'Scanner could not start.',
          tone: InAppNoticeTone.warning,
        );
      }
      return;
    }
    if (device == null || !mounted) {
      return;
    }
    final deviceName = device;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => _WindowsQrScannerPage(deviceName: deviceName),
      ),
    );
    final value = result?.trim();
    if (value == null || value.isEmpty || value == '-1' || !mounted) {
      return;
    }
    setState(() => _configController.text = value);
    await _handleConfigValue(value);
  }

  Future<String?> _chooseWindowsCameraDevice() async {
    final devices = await _bridge.getWindowsCameraDevices();
    if (!mounted) {
      return null;
    }
    if (devices.isEmpty) {
      return showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Scanner device'),
          content: const Text('Use the default Windows camera device?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('default'),
              child: const Text('Default camera'),
            ),
          ],
        ),
      );
    }
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Scanner device'),
        children: [
          for (final device in devices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(device),
              child: Text(device),
            ),
        ],
      ),
    );
  }

  Future<void> _stopScanner() async {
    await _scannerController.stop();
    if (!mounted) {
      return;
    }
    setState(() => _scanning = false);
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_handledScan) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) {
        continue;
      }
      if (SmartProxyPayload.tryParse(value) == null &&
          RemoteProxyConfig.tryParse(value) == null) {
        continue;
      }
      _handledScan = true;
      _scannerController.stop();
      if (!mounted) {
        return;
      }
      setState(() {
        _scanning = false;
        _configController.text = value;
      });
      _handleConfigValue(value);
      return;
    }
  }

  Future<void> _handleConfigValue(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final smart = SmartProxyPayload.tryParse(trimmed);
    if (smart != null) {
      await _showSmartProxyPicker(smart);
      return;
    }
    final config = RemoteProxyConfig.tryParse(trimmed);
    if (config != null) {
      _loadConfig(config);
      return;
    }
    if (!mounted) {
      return;
    }
    showLocalistNotice(
      context,
      message: 'Config is not valid.',
      tone: InAppNoticeTone.error,
    );
  }

  RemoteProxyConfig? _currentConfig() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (_hostError(host) != null || _portError(_portController.text) != null) {
      return null;
    }
    return RemoteProxyConfig(protocol: _protocol, host: host, port: port!);
  }

  void _applyConfig(RemoteProxyConfig config) {
    _protocol = config.protocol;
    _hostController.text = config.host;
    _portController.text = config.port.toString();
  }

  void _loadConfig(RemoteProxyConfig config, {String? configText}) {
    setState(() {
      _applyConfig(config);
      _configController.text = configText ?? config.url;
      _configTip =
          'Proxy Config is ready. Use Start as VPN + proxy or Start as proxy when you are ready.';
    });
    unawaited(_persistDraft());
    showLocalistNotice(
      context,
      message: 'Config loaded. Choose Start as VPN + proxy or Start as proxy.',
      tone: InAppNoticeTone.success,
    );
  }

  Future<void> _showSmartProxyPicker(SmartProxyPayload payload) async {
    final selected = await showModalBottomSheet<SmartProxyEndpoint>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose proxy endpoint',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final endpoint in _sortedEndpoints(
                        payload.endpoints,
                      ))
                        ListTile(
                          leading: const Icon(Icons.route_outlined),
                          title: Text(endpoint.label),
                          subtitle: Text(
                            endpoint.protocol == ProxyProtocol.http
                                ? '${endpoint.config.url} - VPN compatible'
                                : '${endpoint.config.url} - manual proxy endpoint',
                          ),
                          onTap: () => Navigator.of(context).pop(endpoint),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) {
      return;
    }
    _loadConfig(selected.config, configText: _configController.text.trim());
  }

  Future<void> _showDiscoveredDevicePicker(
    LocalistDiscoveredDevice device,
  ) async {
    if (widget.controlsLocked ||
        widget.busy ||
        widget.snapshot.receivingRunning ||
        widget.snapshot.localProxyRunning) {
      return;
    }
    final selected = await showModalBottomSheet<SmartProxyEndpoint>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${device.platform} - ${device.sourceAddress}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final endpoint in _sortedEndpoints(device.endpoints))
                        ListTile(
                          leading: const Icon(Icons.route_outlined),
                          title: Text(endpoint.label),
                          subtitle: Text(
                            endpoint.protocol == ProxyProtocol.http
                                ? '${endpoint.config.url} - VPN compatible'
                                : '${endpoint.config.url} - manual proxy endpoint',
                          ),
                          onTap: () => Navigator.of(context).pop(endpoint),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected == null || !mounted) {
      return;
    }
    _loadConfig(selected.config, configText: device.payload.encode());
  }

  Future<void> _restoreDraft() async {
    _restoringDraft = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final configText = prefs.getString(_receivingDraftConfigKey) ?? '';
      final host = prefs.getString(_receivingDraftHostKey) ?? '';
      final port =
          prefs.getInt(_receivingDraftPortKey) ??
          ProxyProtocol.socks5.defaultPort;
      final protocol = ProxyProtocol.fromName(
        prefs.getString(_receivingDraftProtocolKey),
      );
      if (!mounted || widget.snapshot.remoteProxy != null) {
        return;
      }
      setState(() {
        _protocol = protocol;
        _configController.text = configText;
        _hostController.text = host;
        _portController.text = port.toString();
      });
    } finally {
      _restoringDraft = false;
    }
  }

  void _setProtocol(ProxyProtocol value) {
    setState(() {
      _protocol = value;
      _portController.text = value.defaultPort.toString();
    });
    unawaited(_persistDraft());
  }

  void _handleDraftChanged() {
    if (_restoringDraft || !mounted) {
      return;
    }
    setState(() {});
    unawaited(_persistDraft());
  }

  Future<void> _persistDraft() async {
    if (_restoringDraft) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_receivingDraftConfigKey, _configController.text);
    await prefs.setString(_receivingDraftProtocolKey, _protocol.name);
    await prefs.setString(_receivingDraftHostKey, _hostController.text.trim());
    final port = int.tryParse(_portController.text.trim());
    if (port != null) {
      await prefs.setInt(_receivingDraftPortKey, port);
    }
  }

  String? _hostError(String value) {
    final host = value.trim();
    if (host.isEmpty) {
      return 'Required';
    }
    if (host.contains(RegExp(r'\s'))) {
      return 'No spaces';
    }
    if (host.contains('://')) {
      return 'Host only';
    }
    final uri = Uri.tryParse('http://$host');
    if (uri == null || uri.host.isEmpty || uri.host != host) {
      return 'Invalid host';
    }
    return null;
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
    if (parsed < 1 || parsed > 65535) {
      return 'Use 1-65535';
    }
    return null;
  }

  List<SmartProxyEndpoint> _sortedEndpoints(
    List<SmartProxyEndpoint> endpoints,
  ) {
    return [...endpoints]..sort((first, second) {
      final protocolOrder = first.protocol.index.compareTo(
        second.protocol.index,
      );
      if (protocolOrder != 0) {
        return protocolOrder;
      }
      return first.host.compareTo(second.host);
    });
  }
}

class _NearbyDevicesView extends StatelessWidget {
  const _NearbyDevicesView({
    required this.devices,
    required this.scanning,
    required this.enabled,
    required this.onRefresh,
    required this.onTap,
  });

  final List<LocalistDiscoveredDevice> devices;
  final bool scanning;
  final bool enabled;
  final Future<void> Function() onRefresh;
  final ValueChanged<LocalistDiscoveredDevice> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .34),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.radar_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.nearbyDevices,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (scanning)
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: l10n.searchAgain,
                    onPressed: enabled ? () => unawaited(onRefresh()) : null,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (devices.isEmpty)
              _NearbyEmptyState(enabled: enabled, scanning: scanning)
            else
              Column(
                children: [
                  for (var index = 0; index < devices.length; index++) ...[
                    if (index > 0) const SizedBox(height: 8),
                    _NearbyDeviceTile(
                      device: devices[index],
                      enabled: enabled,
                      onTap: () => onTap(devices[index]),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _NearbyEmptyState extends StatelessWidget {
  const _NearbyEmptyState({required this.enabled, required this.scanning});

  final bool enabled;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Row(
      children: [
        Icon(Icons.devices_other_outlined, color: scheme.outline),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            !enabled
                ? l10n.nearbySearchDisabled
                : scanning
                ? l10n.searchingLocalNetwork
                : l10n.noSharingDeviceFound,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _NearbyDeviceTile extends StatelessWidget {
  const _NearbyDeviceTile({
    required this.device,
    required this.enabled,
    required this.onTap,
  });

  final LocalistDiscoveredDevice device;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : .56,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: .44),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(Icons.devices_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${device.platform} - ${device.endpointSummary}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${device.endpoints.length}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      _lastSeenLabel(device.lastSeen),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _lastSeenLabel(DateTime value) {
    final seconds = DateTime.now().difference(value).inSeconds;
    if (seconds < 5) {
      return 'now';
    }
    if (seconds < 60) {
      return '${seconds}s';
    }
    return '${DateTime.now().difference(value).inMinutes}m';
  }
}

class _WindowsQrScannerPage extends StatefulWidget {
  const _WindowsQrScannerPage({required this.deviceName});

  final String deviceName;

  @override
  State<_WindowsQrScannerPage> createState() => _WindowsQrScannerPageState();
}

class _WindowsQrScannerPageState extends State<_WindowsQrScannerPage> {
  late final WebviewController _controller;
  late final Future<void> _initialized;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebviewController();
    _initialized = _initWebview();
  }

  @override
  void dispose() {
    _postClose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initWebview() async {
    await _controller.initialize();
    _controller.webMessage.listen(_handleWebMessage);
    await _controller.loadUrl(_scannerAssetUrl());
  }

  void _handleWebMessage(dynamic event) {
    if (_completed || !mounted || event is! Map) {
      return;
    }
    if (event['methodName'] != 'successCallback') {
      return;
    }
    final data = event['data'];
    if (data is! String || data.trim().isEmpty) {
      return;
    }
    _completed = true;
    Navigator.of(context).pop(data.trim());
  }

  String _scannerAssetUrl() {
    final assetsDirectory =
        '${File(Platform.resolvedExecutable).parent.path}\\data\\flutter_assets\\packages\\simple_barcode_scanner\\assets\\barcode.html';
    return Uri.file(assetsDirectory).toString();
  }

  Future<WebviewPermissionDecision> _handlePermissionRequest(
    String url,
    WebviewPermissionKind kind,
    bool isUserInitiated,
  ) async {
    if (kind == WebviewPermissionKind.camera) {
      return WebviewPermissionDecision.allow;
    }
    return WebviewPermissionDecision.none;
  }

  void _closeScanner() {
    _completed = true;
    _postClose();
    Navigator.of(context).pop();
  }

  void _postClose() {
    try {
      _controller.postWebMessage(json.encode({'event': 'close'}));
    } catch (_) {
      // The webview may not have finished initializing yet.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Localist QR'),
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Close scanner',
          onPressed: _closeScanner,
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: .55),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 318,
                    width: double.infinity,
                    child: FutureBuilder<void>(
                      future: _initialized,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Scanner could not start.',
                                style: TextStyle(color: scheme.error),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return Webview(
                          _controller,
                          permissionRequested: _handlePermissionRequest,
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Scanner device'),
                subtitle: Text(widget.deviceName),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _closeScanner,
                  icon: const Icon(Icons.close),
                  label: const Text('Close scanner'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigTip extends StatelessWidget {
  const _ConfigTip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary.withValues(alpha: .24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.tips_and_updates_outlined, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
