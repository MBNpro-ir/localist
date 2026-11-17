import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/developer_bridge_models.dart';
import '../services/developer_bridge_adb_service.dart';
import '../services/developer_agent_transport.dart';
import '../services/virtual_adb_endpoint_service.dart';
import '../widgets/feature_page_layout.dart';
import '../widgets/glass.dart';

enum _BridgePath { hotspot, internet }

typedef NetworkTunnelLauncher =
    Future<void> Function({
      required String target,
      required String password,
      required bool relay,
      required int localPort,
      required String remoteHost,
      required int remotePort,
    });

class DeveloperBridgePage extends StatefulWidget {
  const DeveloperBridgePage({
    super.key,
    this.onOpenRemoteControl,
    this.onOpenNetworkTunnel,
  });

  final VoidCallback? onOpenRemoteControl;
  final NetworkTunnelLauncher? onOpenNetworkTunnel;

  @override
  State<DeveloperBridgePage> createState() => _DeveloperBridgePageState();
}

class _DeveloperBridgePageState extends State<DeveloperBridgePage> {
  static const int _rustDeskLocalPort = 15555;
  final _service = DeveloperBridgeAdbService();
  final _virtualAdb = VirtualAdbEndpointService();
  final _adbPath = TextEditingController();
  final _agentHost = TextEditingController();
  final _agentCode = TextEditingController();
  final _agentFingerprint = TextEditingController();
  final _remoteId = TextEditingController();
  final _remotePassword = TextEditingController();
  final _remoteHost = TextEditingController(text: '127.0.0.1');
  final _remotePort = TextEditingController(text: '48291');
  bool _enabled = false;
  bool _relay = false;
  bool _openingTunnel = false;
  // Most users need the Internet path: the RustDesk route carries the same
  // authenticated Android Agent protocol used by the local hotspot adapter.
  _BridgePath _path = _BridgePath.internet;
  String _tunnelError = '';
  String _virtualAdbError = '';
  DeveloperBridgeTransport? _agentTransport;
  bool _agentConnected = false;
  bool _agentBusy = false;
  String _agentStatus = '';

  bool get _persian => Localizations.localeOf(context).languageCode == 'fa';
  String t(String fa, String en) => _persian ? fa : en;

  @override
  void initState() {
    super.initState();
    _service.addListener(_syncPath);
    _virtualAdb.addListener(_syncPath);
  }

  void _syncPath() {
    final path = _service.executablePath;
    if (path != null && _adbPath.text.isEmpty) _adbPath.text = path;
    if (mounted) setState(() {});
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _enabled = enabled);
    if (enabled) {
      await _service.initialize();
      if (mounted && _service.executablePath != null) {
        await _service.refreshDevices();
      }
    } else {
      _service.deactivate();
      await _service.disconnectManagedEndpoints();
    }
  }

  Future<void> _openRustDeskTunnel() async {
    final target = _remoteId.text.trim();
    if (target.isEmpty) {
      setState(
        () => _tunnelError = t(
          'شناسهٔ Localist گوشی را وارد کنید.',
          'Enter the phone’s Localist ID.',
        ),
      );
      return;
    }
    final remotePort = int.tryParse(_remotePort.text.trim());
    if (remotePort == null || remotePort < 1 || remotePort > 65535) {
      setState(
        () => _tunnelError = t(
          'پورت Android Agent را از صفحهٔ Agent گوشی وارد کنید.',
          'Enter the Android Agent port shown on the phone.',
        ),
      );
      return;
    }
    final remoteHost = _remoteHost.text.trim().toLowerCase();
    if (!const {'127.0.0.1', 'localhost', '::1'}.contains(remoteHost)) {
      setState(
        () => _tunnelError = t(
          'مقصد تونل باید خود گوشی باشد: 127.0.0.1',
          'The tunnel target must be the phone itself: 127.0.0.1',
        ),
      );
      return;
    }
    setState(() {
      _openingTunnel = true;
      _tunnelError = '';
    });
    try {
      final launch = widget.onOpenNetworkTunnel;
      if (launch == null) {
        widget.onOpenRemoteControl?.call();
        setState(
          () => _tunnelError = t(
            'Remote Control باز شد؛ حالت «تونل شبکه» را انتخاب کنید.',
            'Remote Control opened. Select “Network tunnel”.',
          ),
        );
      } else {
        await launch(
          target: target,
          password: _remotePassword.text,
          relay: _relay,
          localPort: _rustDeskLocalPort,
          remoteHost: remoteHost,
          remotePort: remotePort,
        );
      }
    } catch (error) {
      setState(() => _tunnelError = error.toString());
    } finally {
      if (mounted) setState(() => _openingTunnel = false);
    }
  }

  Future<DeveloperBridgeTransport> _newAgentTransport() async {
    final code = _agentCode.text.trim();
    final fingerprint = _agentFingerprint.text.trim();
    if (_path == _BridgePath.hotspot) {
      final host = _agentHost.text.trim();
      final port = int.tryParse(_remotePort.text.trim());
      if (host.isEmpty || port == null) {
        throw const FormatException('Enter the Android Agent IP and port.');
      }
      return LocalLanTransport(
        host: host,
        port: port,
        pairingCode: code,
        certificateSha256: fingerprint,
      );
    }
    return RustDeskRemoteTransport(
      localPort: _rustDeskLocalPort,
      pairingCode: code,
      certificateSha256: fingerprint,
    );
  }

  Future<DeveloperBridgeTransport> _ensureAgentConnected() async {
    final existing = _agentTransport;
    if (existing != null && _agentConnected) return existing;
    final transport = await _newAgentTransport();
    await transport.connect();
    _agentTransport = transport;
    _agentConnected = true;
    return transport;
  }

  Future<void> _testAgentEcho() async {
    setState(() {
      _agentBusy = true;
      _agentStatus = '';
    });
    try {
      final transport = await _ensureAgentConnected();
      final payload = 'localist-echo-${DateTime.now().microsecondsSinceEpoch}';
      final response = await transport.echo(payload);
      if (response != payload) throw StateError('Echo payload did not match.');
      if (mounted) {
        setState(() => _agentStatus = 'PASS · Echo authenticated over TLS');
      }
    } catch (error) {
      if (mounted) setState(() => _agentStatus = 'FAIL · $error');
    } finally {
      if (mounted) setState(() => _agentBusy = false);
    }
  }

  Future<void> _sendAgentApk() async {
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['apk'],
    );
    if (selected.isEmpty) return;
    final path = selected.single.path;
    if (path == null) return;
    setState(() {
      _agentBusy = true;
      _agentStatus = '';
    });
    try {
      final transport = await _ensureAgentConnected();
      final response = await transport.sendApk(File(path));
      if (mounted) {
        setState(() {
          _agentStatus =
              'PASS · APK SHA-256 validated · ${response['packageName']} '
              'v${response['versionName']} (${response['size']} bytes)';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _agentStatus = 'FAIL · $error');
    } finally {
      if (mounted) setState(() => _agentBusy = false);
    }
  }

  Future<void> _disconnectAgent() async {
    final transport = _agentTransport;
    _agentTransport = null;
    _agentConnected = false;
    await transport?.close();
    if (mounted) setState(() => _agentStatus = 'Agent session closed.');
  }

  Future<void> _startVirtualAdb() async {
    try {
      final endpoint = await _virtualAdb.start();
      if (!_enabled) {
        setState(() {
          _virtualAdbError = t(
            'Listener آماده است؛ برای معرفی به ADB، ابتدا ADB ویندوز را فعال کنید.',
            'The listener is ready. Enable Windows ADB to register it.',
          );
        });
 