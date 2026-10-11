import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/native_bridge_service.dart';
import '../services/feature_permission_service.dart';
import '../services/rustdesk_debug_service.dart';
import '../widgets/onboarding_flow.dart';

const _permissionsCompleteKey = 'localist.permissions.v2.complete';

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
  bool _complete = !Platform.isAndroid && !Platform.isWindows;
  bool _notificationGranted = false;
  bool _batteryGranted = false;
  bool _localNetworkRequired = false;
  bool _localNetworkGranted = true;
  bool _busy = false;
  int _sdk = 0;
  bool _storageGranted = false;
  bool _installerGranted = false;
  bool _rootGranted = false;
  final Map<Permission, bool> _runtime = {};
  Map<String, bool> _features = {};
  Permission get _storage =>
      _sdk >= 30 ? Permission.manageExternalStorage : Permission.storage;
  Permission get _wifi =>
      _sdk >= 33 ? Permission.nearbyWifiDevices : Permission.locationWhenInUse;
  String _t(String fa, String en) => context.l10n.isPersian ? fa : en;

  bool get _allGranted {
    if (Platform.isWindows) return true;
    return _notificationGranted &&
        _storageGranted &&
        _batteryGranted &&
        (!_localNetworkRequired || _localNetworkGranted);
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
    if (state == AppLifecycleState.resumed &&
        (Platform.isAndroid || Platform.isWindows)) {
      _refreshStatuses();
    }
  }

  Future<void> _load() async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      setState(() => _loading = false);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final previouslyCompleted = prefs.getBool(_permissionsCompleteKey) ?? false;
    await _refreshStatuses();
    if (mounted) {
      setState(() {
        _complete = previouslyCompleted;
        _loading = false;
      });
    }
  }

  Future<void> _refreshStatuses() async {
    if (Platform.isWindows) {
      final features = await _bridge.getFeatureAccessStatus();
      if (mounted) setState(() => _features = features);
      return;
    }
    final notification = await Permission.notification.status;
    final battery = await _bridge.isIgnoringBatteryOptimizations();
    final sdk = await _bridge.getAndroidSdkInt() ?? 0;
    _sdk = sdk;
    final storage = await _storage.status;
    final runtime = <Permission, bool>{};
    for (final permission in [
      Permission.camera,
      Permission.microphone,
      _wifi,
      Permission.systemAlertWindow,
    ]) {
      runtime[permission] = (await permission.status).isGranted;
    }
    final installer = await _bridge.canInstallAndroidPackages();
    final features = await _bridge.getFeatureAccessStatus();
    final localNetworkRequired = sdk >= 37;
    final localNetwork =
        !localNetworkRequired || await _bridge.hasLocalNetworkPermission();
    if (!mounted) {
      return;
    }
    setState(() {
      _notificationGranted = notification.isGranted;
      _batteryGranted = battery;
      _localNetworkRequired = localNetworkRequired;
      _localNetworkGranted = localNetwork;
      _storageGranted = storage.isGranted;
      _runtime.addAll(runtime);
      _installerGranted = installer;
      _features = features;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_complete || (!Platform.isAndroid && !Platform.isWindows)) {
      return widget.child;
    }
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final frame = OnboardingFrame(
      simple: widget.simple,
      steps: [
        l10n.languageStep,
        l10n.permissionsStep,
        l10n.isPersian ? 'پروفایل' : 'Profile',
        l10n.mainStep,
      ],
      currentStep: 1,
      icon: Icons.verified_user_outlined,
      title: _t('به Localist خوش آمدید', 'Welcome to Localist'),
      subtitle: _t(
        'دسترسی‌های برنامه را همین‌جا آماده کنید. مجوزهای قابلیت‌های اختیاری را می‌توانید بعداً نیز فعال کنید.',
        'Prepare app access here. Permissions for optional features can also be enabled later.',
      ),
      onBack: widget.onBackToLanguage,
      children: [
        if (Platform.isWindows) ...[
          Text(
            _t(
              'Localist بدون دسترسی مدیر اجرا می‌شود. فقط هنگام استفاده از قابلیتی که به مدیر نیاز دارد، ویندوز تأیید UAC می‌خواهد و کار در همان بخش ادامه پیدا می‌کند.',
              'Localist runs without administrator access. Windows requests UAC only for an operation that needs it, and the operation continues in the same page.',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _t(
              'برای دریافت اتصال شبکه، پیام Firewall ویندوز را هنگام اولین میزبانی بررسی کنید. نصب سرویس، نمایشگر مجازی و چاپگر از راه دور در تنظیمات قابلیت مربوط انجام می‌شود.',
              'Review the Windows Firewall prompt on first hosting. Service, virtual display and printer installation are available in their feature settings.',
            ),
          ),
        ] else ...[
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _requestRuntimePermissions,
            icon: const Icon(Icons.checklist),
            label: Text(
              _t(
                'فعال کردن سه دسترسی اصلی',
                'Enable the three main permissions',
              ),
            ),
          ),
          const SizedBox(height: 12),
          _PermissionTile(
            granted: _notificationGranted,
            icon: Icons.notifications_active_outlined,
            title: l10n.notifications,
            subtitle: l10n.notificationsSubtitle,
            onPressed: _busy ? null : _requestNotification,
          ),
          if (_localNetworkRequired) ...[
            const SizedBox(height: 10),
            _PermissionTile(
              granted: _localNetworkGranted,
              icon: Icons.lan_outlined,
              title: context.l10n.isPersian
                  ? 'دسترسی شبکه محلی'
                  : 'Local network access',
              subtitle: context.l10n.isPersian
                  ? 'برای پیدا کردن دستگاه‌ها و دریافت مستقیم فایل در Android 17 لازم است.'
                  : 'Required on Android 17 to discover devices and receive files directly.',
              onPressed: _busy ? null : _requestLocalNetwork,
            ),
          ],
          const SizedBox(height: 10),
          _PermissionTile(
            granted: _batteryGranted,
            icon: Icons.battery_saver_outlined,
            title: l10n.backgroundTransfer,
            subtitle: l10n.backgroundTransferSubtitle,
            onPressed: _busy ? null : _requestBattery,
          ),
          const SizedBox(height: 10),
          _PermissionTile(
            granted: _storageGranted,
            icon: Icons.folder_open,
            title: _t(
              'فایل‌ها و پوشهٔ Downloads',
              'Files and Downloads folder',
            ),
            subtitle: _t(
              'برای ارسال فایل و ذخیرهٔ فایل‌های دریافتی در Download/Localist.',
              'For sending files and saving received files in Download/Localist.',
            ),
            onPressed: _busy ? null : () => _requestPermission(_storage),
          ),
          const SizedBox(height: 20),
          Text(
            _t('دسترسی قابلیت‌های اختیاری', 'Optional feature access'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          for (final item in [
            (
              Permission.camera,
              Icons.camera_alt_outlined,
              _t('دوربین', 'Camera'),
              _t(
                'اسکن QR و اشتراک دوربین در ریموت.',
                'QR scanning and remote camera sharing.',
              ),
            ),
            (
              Permission.microphone,
              Icons.mic_none,
              _t('میکروفن', 'Microphone'),
              _t(
                'تماس صوتی و صدای جلسهٔ ریموت.',
                'Voice calls and remote session audio.',
              ),
            ),
            (
              _wifi,
              Icons.wifi_tethering,
              _t('هات‌اسپات و دستگاه‌های نزدیک', 'Hotspot and nearby devices'),
              _t(
                'ساخت هات‌اسپات برای دستگاه‌های وب؛ در اندروید قدیمی دسترسی مکان لازم است.',
                'Create a hotspot for web devices; older Android versions require location access.',
              ),
            ),
            (
              Permission.systemAlertWindow,
              Icons.picture_in_picture_alt,
              _t('نمایش روی برنامه‌ها', 'Display over other apps'),
              _t(
                'کنترل شناور میزبانی و نمایش درخواست اتصال.',
                'Floating hosting controls and incoming connection requests.',
              ),
            ),
          ]) ...[
            _PermissionTile(
              granted: _runtime[item.$1] == true,
              icon: item.$2,
              title: item.$3,
              subtitle: item.$4,
              onPressed: _busy ? null : () => _requestPermission(item.$1),
            ),
            const SizedBox(height: 10),
          ],
          _PermissionTile(
            granted: _installerGranted,
            icon: Icons.system_update_alt,
            title: _t('نصب آپدیت', 'Install app updates'),
            subtitle: _t(
              'اجازهٔ نصب نسخه‌های جدید دانلودشده توسط Localist.',
              'Allow installation of new versions downloaded by Localist.',
            ),
            onPressed: _busy
                ? null
                : () => _featureRequest(
                    _bridge.openAndroidInstallPermissionSettings,
                  ),
          ),
          const SizedBox(height: 10),
          _PermissionTile(
            granted: _features['vpn'] == true,
            icon: Icons.vpn_key_outlined,
            title: _t('اتصال VPN', 'VPN connection'),
            subtitle: _t(
              'برای دریافت اینترنت یا اتصال از پروکسی؛ اندروید ممکن است هنگام تغییر VPN دوباره تأیید بخواهد.',
              'For internet receiving and proxy routing; Android may ask again after changing VPN apps.',
            ),
            onPressed: _busy
                ? null
                : () => _featureRequest(_bridge.ensureVpnPermission),
          ),
          const SizedBox(height: 10),
          _PermissionTile(
            granted: _features['input'] == true,
            icon: Icons.touch_app_outlined,
            title: _t(
              'کنترل از راه دور و Accessibility',
              'Remote input and Accessibility',
            ),
            subtitle: _t(
              'سرویس Localist را در Accessibility فعال کنید. اگر دسترسی محدود است: App info ← منوی سه‌نقطه ← Allow restricted settings.',
              'Enable Localist in Accessibility. If restricted: App info → three-dot menu → Allow restricted settings.',
            ),
            onPressed: _busy
                ? null
                : () => _featureRequest(() async {
                    final service = RustDeskDebugService();
                    try {
                      await service.openInputPermission();
                    } finally {
                      service.dispose();
                    }
                    return true;
                  }),
          ),
          const SizedBox(height: 10),
          _PermissionTile(
            granted: _features['capture'] == true,
            icon: Icons.screen_share_outlined,
            title: _t('اشتراک و ضبط صفحه', 'Screen sharing and capture'),
            subtitle: _t(
              'با تأیید سیستم میزبانی شروع می‌شود. اندروید این مجوز را برای هر جلسه می‌گیرد و قابل ذخیرهٔ دائمی نیست.',
              'System confirmation starts hosting. Android grants capture per session; this permission cannot be saved permanently.',
            ),
            onPressed: _busy
                ? null
                : () => _featureRequest(() async {
                    final service = RustDeskDebugService();
                    try {
                      await service.initialize();
                      await service.setAndroidHosting(true);
                    } finally {
                      service.dispose();
                    }
                    return true;
                  }),
          ),
          const SizedBox(height: 10),
          _PermissionTile(
            granted: _rootGranted,
            icon: Icons.admin_panel_settings_outlined,
            title: _t('Root روی دستگاه روت‌شده', 'Root on rooted devices'),
            subtitle: _t(
              'اختیاری؛ فقط برای اشتراک کامل مسیرهای شبکه روی دستگاه‌های روت‌شده. مدیر Root دستگاه تأیید می‌خواهد.',
              'Optional, for full network routing on rooted devices. Your root manager asks for confirmation.',
            ),
            onPressed: _busy
                ? null
                : () => _featureRequest(() async {
                    final granted = await _bridge.checkRootAccess();
                    if (mounted) setState(() => _rootGranted = granted);
                    return granted;
                  }),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: !_busy ? _enterApp : null,
            icon: const Icon(Icons.arrow_forward),
            label: Text(l10n.enterLocalist),
          ),
        ),
        if (!_allGranted) ...[
          const SizedBox(height: 12),
          Text(
            _t(
              'می‌توانید ادامه دهید؛ هر دسترسیِ داده‌نشده هنگام نیاز دوباره درخواست می‌شود. وضعیت همهٔ دسترسی‌ها در تنظیمات ← دسترسی‌ها قابل تغییر است.',
              'You can continue. Missing permissions will be requested when needed. Manage them in Settings → Permissions.',
            ),
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

  Future<void> _featureRequest(Future<bool> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await _refreshStatuses();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestPermission(Permission permission) =>
      _featureRequest(() async {
        final access = permission == _storage
            ? FeatureAccess.storage
            : permission == _wifi
            ? FeatureAccess.nearbyDevices
            : permission == Permission.camera
            ? FeatureAccess.camera
            : permission == Permission.microphone
            ? FeatureAccess.microphone
            : FeatureAccess.overlay;
        return FeaturePermissionService.instance.ensure([access]);
      });

  Future<void> _requestRuntimePermissions() => _featureRequest(() async {
    return FeaturePermissionService.instance.requestWelcome();
  });

  Future<void> _requestBattery() async {
    final l10n = context.l10n;
    await _runRequest(
      title: l10n.backgroundTransferRequired,
      body: l10n.backgroundTransferRequiredBody,
      request: () => _bridge.requestIgnoreBatteryOptimizations(),
      refresh: _refreshStatuses,
    );
  }

  Future<void> _requestLocalNetwork() async {
    await _runRequest(
      title: context.l10n.isPersian
          ? 'دسترسی شبکه محلی لازم است'
          : 'Local network access is required',
      body: context.l10n.isPersian
          ? 'بدون این دسترسی Android 17 اتصال‌های Quick Send در شبکه را مسدود می‌کند.'
          : 'Without this permission, Android 17 blocks Quick Send connections on the local network.',
      request: _bridge.requestLocalNetworkPermission,
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
        borderRadius: BorderRadius.circular(20),
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
