import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/native_bridge_service.dart';

const _permissionsCompleteKey = 'localist.android.permissions.v1.complete';

class AndroidPermissionGate extends StatefulWidget {
  const AndroidPermissionGate({super.key, required this.child});

  final Widget child;

  @override
  State<AndroidPermissionGate> createState() => _AndroidPermissionGateState();
}

class _AndroidPermissionGateState extends State<AndroidPermissionGate>
    with WidgetsBindingObserver {
  final _bridge = NativeBridgeService.instance;

  bool _loading = true;
  bool _complete = !Platform.isAndroid;
  bool _notificationGranted = false;
  bool _cameraGranted = false;
  bool _batteryGranted = false;
  bool _busy = false;

  bool get _allGranted {
    return _notificationGranted && _cameraGranted && _batteryGranted;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      _refreshStatuses();
    }
  }

  Future<void> _load() async {
    if (!Platform.isAndroid) {
      setState(() => _loading = false);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _complete = prefs.getBool(_permissionsCompleteKey) ?? false;
    await _refreshStatuses();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshStatuses() async {
    final notification = await Permission.notification.status;
    final camera = await Permission.camera.status;
    final battery = await _bridge.isIgnoringBatteryOptimizations();
    if (!mounted) {
      return;
    }
    setState(() {
      _notificationGranted = notification.isGranted;
      _cameraGranted = camera.isGranted;
      _batteryGranted = battery;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_complete || !Platform.isAndroid) {
      return widget.child;
    }
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Localist permissions')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(
              'Required Android access',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Localist needs these permissions before opening the app.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            _PermissionTile(
              granted: _notificationGranted,
              icon: Icons.notifications_active_outlined,
              title: 'Notifications',
              subtitle: 'Shows the foreground VPN/proxy service status.',
              onPressed: _busy ? null : _requestNotification,
            ),
            _PermissionTile(
              granted: _cameraGranted,
              icon: Icons.qr_code_scanner,
              title: 'Camera',
              subtitle: 'Scans Localist QR configs.',
              onPressed: _busy ? null : _requestCamera,
            ),
            _PermissionTile(
              granted: _batteryGranted,
              icon: Icons.battery_saver_outlined,
              title: 'Background transfer',
              subtitle: 'Keeps proxy/VPN traffic alive when the screen is off.',
              onPressed: _busy ? null : _requestBattery,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _allGranted && !_busy ? _enterApp : null,
              icon: Icon(_allGranted ? Icons.check_circle : Icons.lock_outline),
              label: const Text('Enter Localist'),
            ),
            if (!_allGranted) ...[
              const SizedBox(height: 12),
              Text(
                'Grant every item above to continue.',
                style: TextStyle(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _requestNotification() async {
    await _runRequest(
      title: 'Notifications required',
      body:
          'Localist needs notifications to run VPN and proxy services as foreground services.',
      request: () async => (await Permission.notification.request()).isGranted,
      refresh: _refreshStatuses,
    );
  }

  Future<void> _requestCamera() async {
    await _runRequest(
      title: 'Camera required',
      body: 'Camera access is needed to scan Localist QR configs.',
      request: () async => (await Permission.camera.request()).isGranted,
      refresh: _refreshStatuses,
    );
  }

  Future<void> _requestBattery() async {
    await _runRequest(
      title: 'Background transfer required',
      body:
          'Battery optimization can stop proxy/VPN traffic after the screen turns off.',
      request: () => _bridge.requestIgnoreBatteryOptimizations(),
      refresh: _refreshStatuses,
    );
  }

  Future<void> _runRequest({
    required String title,
    required String body,
    required Future<bool> Function() request,
    required Future<void> Function() refresh,
  }) async {
    setState(() => _busy = true);
    try {
      final granted = await request();
      await refresh();
      if (!granted && mounted) {
        await _showPermissionPopup(title: title, body: body);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showPermissionPopup({
    required String title,
    required String body,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
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

  Future<void> _enterApp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permissionsCompleteKey, true);
    if (mounted) {
      setState(() => _complete = true);
    }
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.granted,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final bool granted;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(granted ? Icons.check_circle : icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: FilledButton.tonal(
          onPressed: granted ? null : onPressed,
          child: Text(granted ? 'Granted' : 'Grant'),
        ),
      ),
    );
  }
}
