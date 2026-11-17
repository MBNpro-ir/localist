import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/native_bridge_service.dart';
import '../widgets/glass.dart';

class AndroidDeveloperAgentPage extends StatefulWidget {
  const AndroidDeveloperAgentPage({super.key});

  @override
  State<AndroidDeveloperAgentPage> createState() =>
      _AndroidDeveloperAgentPageState();
}

class _AndroidDeveloperAgentPageState extends State<AndroidDeveloperAgentPage>
    with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel(
    'localist/developer_agent',
  );

  Map<String, dynamic> _agent = const {};
  Map<String, dynamic>? _receivedApk;
  Map<String, dynamic>? _verifiedInstall;
  List<String> _ipv4Addresses = const [];
  String _message = '';
  bool _busy = false;

  bool get _persian => Localizations.localeOf(context).languageCode == 'fa';
  String t(String fa, String en) => _persian ? fa : en;
  bool get _running => _agent['running'] == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_onNativeEvent);
    unawaited(_refreshStatus());
    unawaited(_refreshAddresses());
  }

  Future<void> _onNativeEvent(MethodCall call) async {
    if (call.method != 'event' || call.arguments is! Map) return;
    final event = Map<String, dynamic>.from(call.arguments as Map);
    if (!mounted) return;
    setState(() {
      final type = event['type']?.toString() ?? '';
      final previousError = _message.startsWith('Agent session failed:');
      if (type == 'sessionError') {
        final detail = event['message']?.toString().trim();
        _message = detail == null || detail.isEmpty
            ? 'Agent session failed.'
            : 'Agent session failed: $detail';
      } else if (type != 'disconnected' || !previousError) {
        _message = _eventMessage(type);
      }
      if (event['type'] == 'apkReceived') _receivedApk = event;
      if (event['type'] == 'stopped') _agent = {..._agent, 'running': false};
    });
  }

  String _eventMessage(String type) => switch (type) {
    'started' => t('Agent فعال شد.', 'Agent started.'),
    'authenticated' => t(
      'نشست امن احراز هویت شد.',
      'Secure session authenticated.',
    ),
    'authenticationRejected' => t(
      'کد جفت‌سازی رد شد.',
      'Pairing code rejected.',
    ),
    'pairingLocked' => t(
      'کد قفل شد؛ Agent را دوباره شروع کنید.',
      'Pairing locked. Restart the Agent.',
    ),
    'disconnected' => t('نشست بسته شد.', 'Session closed.'),
    'stopped' => t('Agent متوقف شد.', 'Agent stopped.'),
    'apkReceived' => t(
      'APK دریافت و اعتبارسنجی شد؛ نصب هنوز تأیید نشده است.',
      'APK received and validated. Installation is not yet confirmed.',
    ),
    'error' || 'sessionError' => t(
      'خطا در ارتباط Agent.',
      'Developer Agent connection error.',
    ),
    _ => type,
  };

  Future<void> _refreshStatus() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('status');
      if (mounted && result != null) setState(() => _agent = result);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? error.code);
    }
  }

  Future<void> _refreshAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final addresses =
          interfaces
              .expand((interface) => interface.addresses)
              .where((address) => !address.isLoopback && !address.isLinkLocal)
              .map((address) => address.address)
              .toSet()
              .toList()
            ..sort();
      if (mounted) setState(() => _ipv4Addresses = addresses);
    } on SocketException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('start');
      await _refreshAddresses();
      if (mounted && result != null) {
        setState(() {
          _agent = result;
          _message = t('Agent فعال شد.', 'Agent started.');
        });
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await _channel.invokeMethod<bool>('stop');
      if (mounted) setState(() => _agent = {..._agent, 'running': false});
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? error.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _installReceivedApk() async {
    final apk = _receivedApk;
    if (apk == null) return;
    setState(() => _busy = true);
    try {
      final native = NativeBridgeService.instance;
      if (!await native.canInstallAndroidPackages()) {
        await native.openAndroidInstallPermissionSettings();
        if (mounted) {
          setState(() {
            _message = t(
              'اجازهٔ نصب برای Localist را در تنظیمات Android فعال کنید و دوباره اقدام کنید.',
              'Allow Localist to install apps in Android settings, then try again.',
            );
          });
        }
        return;
      }
      final launched = await native.installAndroidApk(apk['path'] as String);
      if (mounted) {
        setState(() {
          _message = launched
              ? t(
                  'پنجرهٔ نصب سیستم باز شد؛ نتیجه را روی گوشی تأیید کنید.',
                  'Android’s installer opened. Confirm the result on the phone.',
                )
              : t(
                  'درخواست نصب به سیستم‌عامل نرسید.',
                  'The install request did not reach Android.',
                );
          _verifiedInstall = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyInstall() async {
    final packageName = _receivedApk?['packageName']?.toString();
    if (packageName == null) return;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'verifyPackage',
        {'packageName': packageName},
      );
      if (mounted) setState(() => _verifiedInstall = result);
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? error.code);
    }
  }

  Future<void> _launchPackage() async {
    final packageName = _receivedApk?['packageName']?.toString();
    if (packageName == null) return;
    try {
      await _channel.invokeMethod<bool>('launchPackage', {
        'packageName': packageName,
      });
      if (mounted) {
        setState(
          () => _message = t(
            'درخواست اجرای برنامه ارسال شد.',
            'Launch intent was delivered.',
          ),
        );
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _message = error.message ?? error.code);
    }
  }

  Future<void> _refreshProcessStatus() async {
    final packageName = _receivedApk?['packageName']?.toString();
    if (packageName == null) return;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'processStatus',
        {'packageName': packageName},
      );
      if (mounted) {
        setState(
          () => _message = t(
            'وضعیت فرآیند: ${result?['status'] ?? 'unknown'}',
            'Process status: ${result?['status'] ?? 'unknown'}',
          ),
        );
      }
    } on PlatformException catch (error) {
      if