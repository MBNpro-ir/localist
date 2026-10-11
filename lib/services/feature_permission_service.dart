import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'native_bridge_service.dart';

enum FeatureAccess {
  notifications,
  battery,
  storage,
  camera,
  microphone,
  nearbyDevices,
  localNetwork,
  overlay,
  remoteInput,
  screenCapture,
  vpn,
  installUpdates,
}

/// Permissions are requested for the pending operation, independently of
/// whether the user completed or skipped Welcome.
class FeaturePermissionService with WidgetsBindingObserver {
  FeaturePermissionService._()
    : _check = null,
      _requestAccess = null,
      _ask = null;
  @visibleForTesting
  FeaturePermissionService.forTesting(
    this._check,
    this._requestAccess,
    this._ask,
  );
  final Future<bool> Function(FeatureAccess)? _check;
  final Future<void> Function(FeatureAccess)? _requestAccess;
  final Future<bool> Function(List<FeatureAccess>, bool)? _ask;
  bool get _android => _check != null || Platform.isAndroid;
  static final instance = FeaturePermissionService._();
  final _navigatorKey = GlobalKey<NavigatorState>();
  GlobalKey<NavigatorState>? _sessionNavigatorKey;
  GlobalKey<NavigatorState> get navigatorKey =>
      _sessionNavigatorKey ?? _navigatorKey;
  void useSessionNavigator(GlobalKey<NavigatorState> key) =>
      _sessionNavigatorKey = key;
  final _bridge = NativeBridgeService.instance;
  Future<bool>? _pending;
  Completer<void>? _resumed;
  bool _observing = false;

  static const welcomeAccess = [
    FeatureAccess.notifications,
    FeatureAccess.battery,
    FeatureAccess.storage,
  ];

  Future<bool> requestWelcome() => _serial(_requestWelcome);
  Future<bool> _requestWelcome() async {
    if (!_android) return true;
    for (final access in welcomeAccess) {
      if (!await granted(access)) await _request(access);
    }
    for (final access in welcomeAccess) {
      if (!await granted(access)) return false;
    }
    return true;
  }

  bool _fa(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'fa';
  String label(FeatureAccess access, bool fa) => switch (access) {
    FeatureAccess.notifications => fa ? 'اعلان‌ها' : 'Notifications',
    FeatureAccess.battery => fa ? 'فعالیت در پس‌زمینه' : 'Background activity',
    FeatureAccess.storage =>
      fa ? 'فایل‌ها و Download/Localist' : 'Files and Download/Localist',
    FeatureAccess.camera => fa ? 'دوربین' : 'Camera',
    FeatureAccess.microphone => fa ? 'میکروفن' : 'Microphone',
    FeatureAccess.nearbyDevices =>
      fa ? 'دستگاه‌های نزدیک و Wi-Fi' : 'Nearby devices and Wi-Fi',
    FeatureAccess.localNetwork => fa ? 'شبکهٔ محلی' : 'Local network',
    FeatureAccess.overlay =>
      fa ? 'نمایش روی برنامه‌ها' : 'Display over other apps',
    FeatureAccess.remoteInput =>
      fa ? 'کنترل لمس و Accessibility' : 'Touch control and Accessibility',
    FeatureAccess.screenCapture =>
      fa ? 'اشتراک صفحه (برای همین جلسه)' : 'Screen sharing (this session)',
    FeatureAccess.vpn => 'VPN',
    FeatureAccess.installUpdates => fa ? 'نصب آپدیت' : 'Install updates',
  };

  Future<Permission?> _permission(FeatureAccess access) async {
    final sdk =
        await const MethodChannel('localist/remote').invokeMethod<int>('sdk') ??
        0;
    return switch (access) {
      FeatureAccess.notifications => Permission.notification,
      FeatureAccess.storage =>
        sdk >= 30 ? Permission.manageExternalStorage : Permission.storage,
      FeatureAccess.camera => Permission.camera,
      FeatureAccess.microphone => Permission.microphone,
      FeatureAccess.nearbyDevices =>
        sdk >= 33 ? Permission.nearbyWifiDevices : Permission.locationWhenInUse,
      FeatureAccess.overlay => Permission.systemAlertWindow,
      _ => null,
    };
  }

  Future<bool> granted(FeatureAccess access) async {
    if (_check != null) return _check(access);
    if (!_android) return true;
    final permission = await _permission(access);
    if (permission != null) return (await permission.status).isGranted;
    if ([
      FeatureAccess.remoteInput,
      FeatureAccess.screenCapture,
      FeatureAccess.vpn,
    ].contains(access)) {
      final features =
          await const MethodChannel(
            'localist/remote',
          ).invokeMapMethod<String, dynamic>('features') ??
          {};
      final name = access == FeatureAccess.remoteInput
          ? 'input'
          : access == FeatureAccess.screenCapture
          ? 'capture'
          : 'vpn';
      return features[name] == true;
    }
    return switch (access) {
      FeatureAccess.battery => _bridge.isIgnoringBatteryOptimizations(),
      FeatureAccess.localNetwork => _bridge.hasLocalNetworkPermission(),
      FeatureAccess.installUpdates => _bridge.canInstallAndroidPackages(),
      _ => false,
    };
  }

  Future<bool> ensure(
    List<FeatureAccess> access, {
    String? reason,
    bool explain = true,
  }) => _serial(() => _ensure(access.toSet().toList(), reason, explain));

  Future<void> openSettings(FeatureAccess access) async {
    if (!Platform.isAndroid) return;
    await _serial(() async {
      await _withResume(() async {
        final opened = await const MethodChannel(
          'localist/remote',
        ).invokeMethod<bool>('permissionSettings', access.name);
        if (opened != true) await openAppSettings();
      });
      return true;
    });
  }

  Future<bool> _serial(Future<bool> Function() run) async {
    if (!_android) return true;
    final task = (_pending ?? Future<bool>.value(false))
        .catchError((Object _) => false)
        .then((_) => run());
    _pending = task;
    try {
      return await task;
    } finally {
      if (identical(_pending, task)) _pending = null;
    }
  }

  Future<bool> _ensure(
    List<FeatureAccess> access,
    String? reason,
    bool explain,
  ) async {
    final missing = <FeatureAccess>[];
    for (final item in access) {
      if (!await granted(item)) missing.add(item);
    }
    if (missing.isEmpty) return true;
    final context = navigatorKey.currentContext;
    if (_ask == null && (context == null || !context.mounted)) return false;
    final fa = context != null && _fa(context);
    if (explain && !await _confirm(context, missing, fa, reason: reason)) {
      return false;
    }
    for (final item in missing) {
      if (await granted(item)) continue;
      await _request(item);
      if (await granted(item)) continue;
      final current = navigatorKey.currentContext;
      if (_ask == null && (current == null || !current.mounted)) return false;
      final settings = await _confirm(current, [item], fa, settings: true);
      if (!settings) return false;
      await _withResume(() async {
        if (item == FeatureAccess.remoteInput) {
          await openAppSettings();
        } else if (item == FeatureAccess.screenCapture) {
          await const MethodChannel('mChannel').invokeMethod('init_service');
        } else {
          await openAppSettings();
        }
      });
      if (item == FeatureAccess.remoteInput && !await granted(item)) {
        await _request(item);
      }
      if (!await granted(item)) return false;
    }
    return true;
  }

  Future<void> _request(FeatureAccess access) async {
    if (_requestAccess != null) {
      await _requestAccess(access);
      return;
    }
    final permission = await _permission(access);
    if (permission != null) {
      if (!(await permission.status).isPermanentlyDenied) {
        await _withResume(() async {
          await permission.request();
        });
      }
      return;
    }
    await _withResume(() async {
      switch (access) {
        case FeatureAccess.battery:
          await _bridge.requestIgnoreBatteryOptimizations();
        case FeatureAccess.localNetwork:
          await _bridge.requestLocalNetworkPermission();
        case FeatureAccess.installUpdates:
          await _bridge.openAndroidInstallPermissionSettings();
        case FeatureAccess.remoteInput:
          await const MethodChannel(
            'localist/remote',
          ).invokeMethod('inputSettings');
        case FeatureAccess.screenCapture:
          await const MethodChannel('mChannel').invokeMethod('init_service');
        case FeatureAccess.vpn:
          await _bridge.ensureVpnPermission();
        default:
          break;
      }
    });
    // MediaProjection/service state arrives shortly after the activity result.
    if (access == FeatureAccess.screenCapture) {
      for (var n = 0; n < 20 && !await granted(access); n++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Future<void> _withResume(Future<void> Function() action) async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    final resumed = Completer<void>();
    _resumed = resumed;
    await action();
    // External settings calls return before the user comes back. Runtime
    // dialogs often already awaited their activity result.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed &&
        WidgetsBinding.instance.lifecycleState != null) {
      await resumed.future;
    }
    if (identical(_resumed, resumed)) _resumed = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _resumed?.isCompleted == false) {
      _resumed!.complete();
    }
  }

  Future<bool> _confirm(
    BuildContext? context,
    List<FeatureAccess> access,
    bool fa, {
    String? reason,
    bool settings = false,
  }) {
    if (_ask != null) return _ask(access, settings);
    return _dialog(context!, access, fa, reason: reason, settings: settings);
  }

  Future<bool> _dialog(
    BuildContext context,
    List<FeatureAccess> access,
    bool fa, {
    String? reason,
    bool settings = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          icon: const Icon(Icons.verified_user_outlined),
          title: Text(fa ? 'دسترسی مورد نیاز' : 'Permission needed'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reason ??
                    (fa
                        ? 'برای ادامهٔ همین کار، این دسترسی‌ها لازم هستند:'
                        : 'These permissions are needed to continue this operation:'),
              ),
              const SizedBox(height: 12),
              for (final item in access) Text('• ${label(item, fa)}'),
              if (access.contains(FeatureAccess.remoteInput)) ...[
                const SizedBox(height: 12),
                Text(
                  fa
                      ? 'سرویس Localist را در Accessibility فعال کنید. اگر APK را از GitHub نصب کرده‌اید و این گزینه قفل است: App info ← منوی سه‌نقطه ← Allow restricted settings؛ سپس به Accessibility برگردید. این مجوز به طرف مقابل امکان کنترل لمس و صفحه‌کلید می‌دهد.'
                      : 'Enable Localist in Accessibility. For a GitHub APK, if Android blocks it: App info → three-dot menu → Allow restricted settings, then return to Accessibility. This allows the remote user to control touch and keyboard.',
                ),
              ],
              if (access.contains(FeatureAccess.screenCapture)) ...[
                const SizedBox(height: 12),
                Text(
                  fa
                      ? 'اندروید برای هر جلسه اجازهٔ اشتراک صفحه می‌خواهد. فقط به شخص مورد اعتماد اجازه بدهید.'
                      : 'Android asks for screen sharing for each session. Approve only a trusted person.',
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(fa ? 'فعلاً نه' : 'Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                settings
                    ? (fa ? 'باز کردن تنظیمات' : 'Open settings')
                    : (fa ? 'دادن دسترسی و ادامه' : 'Grant and continue'),
              ),
            ),
          ],
        ),
      ) ??
      false;
}
