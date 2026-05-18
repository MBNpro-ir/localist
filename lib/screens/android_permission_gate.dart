import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/native_bridge_service.dart';
import '../widgets/onboarding_flow.dart';

const _permissionsCompleteKey = 'localist.android.permissions.v1.complete';

class AndroidPermissionGate extends StatefulWidget {
  const AndroidPermissionGate({
    super.key,
    required this.child,
    required this.simple,
    this.onBackToLanguage,
  });

  final Widget child;
  final bool simple;
  final VoidCallback? onBackToLanguage;

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

    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final frame = OnboardingFrame(
      simple: widget.simple,
      steps: [l10n.languageStep, l10n.permissionsStep, l10n.mainStep],
      currentStep: 1,
      icon: Icons.verified_user_outlined,
      title: l10n.requiredAndroidAccess,
      subtitle: l10n.permissionsIntro,
      onBack: widget.onBackToLanguage,
      children: [
        _PermissionTile(
          granted: _notificationGranted,
          icon: Icons.notifications_active_outlined,
          title: l10n.notifications,
          subtitle: l10n.notificationsSubtitle,
          onPressed: _busy ? null : _requestNotification,
        ),
        const SizedBox(height: 10),
        _PermissionTile(
          granted: _cameraGranted,
          icon: Icons.qr_code_scanner,
          title: l10n.camera,
          subtitle: l10n.cameraSubtitle,
          onPressed: _busy ? null : _requestCamera,
        ),
        const SizedBox(height: 10),
        _PermissionTile(
          granted: _batteryGranted,
          icon: Icons.battery_saver_outlined,
          title: l10n.backgroundTransfer,
          subtitle: l10n.backgroundTransferSubtitle,
          onPressed: _busy ? null : _requestBattery,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _allGranted && !_busy ? _enterApp : null,
            icon: Icon(_allGranted ? Icons.check_circle : Icons.lock_outline),
            label: Text(l10n.enterLocalist),
          ),
        ),
        if (!_allGranted) ...[
          const SizedBox(height: 12),
          Text(
            l10n.grantEveryItem,
            style: TextStyle(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
    return PopScope(
      canPop: widget.onBackToLanguage == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          widget.onBackToLanguage?.call();
        }
      },
      child: frame,
    );
  }

  Future<void> _requestNotification() async {
    final l10n = context.l10n;
    await _runRequest(
      title: l10n.notificationsRequired,
      body: l10n.notificationsRequiredBody,
      request: () async => (await Permission.notification.request()).isGranted,
      refresh: _refreshStatuses,
    );
  }

  Future<void> _requestCamera() async {
    final l10n = context.l10n;
    await _runRequest(
      title: l10n.cameraRequired,
      body: l10n.cameraRequiredBody,
      request: () async => (await Permission.camera.request()).isGranted,
      refresh: _refreshStatuses,
    );
  }

  Future<void> _requestBattery() async {
    final l10n = context.l10n;
    await _runRequest(
      title: l10n.backgroundTransferRequired,
      body: l10n.backgroundTransferRequiredBody,
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
    final l10n = context.l10n;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              openAppSettings();
              Navigator.of(context).pop();
            },
            child: Text(l10n.openSettings),
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
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: .42),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .38)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: Icon(
            granted ? Icons.check_circle : icon,
            color: granted ? scheme.primary : scheme.onSurfaceVariant,
          ),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: FilledButton.tonal(
            onPressed: granted ? null : onPressed,
            child: Text(granted ? l10n.granted : l10n.grant),
          ),
        ),
      ),
    );
  }
}
