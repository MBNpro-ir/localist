import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../services/feature_permission_service.dart';
import '../services/rustdesk_debug_service.dart';
import '../widgets/glass.dart';

/// Mirrors upstream mobile PermissionChecker: capture, input, transfer,
/// audio and clipboard. System permissions remain separate from engine grants.
class PermissionsSettingsPage extends StatefulWidget {
  const PermissionsSettingsPage({super.key});
  @override
  State<PermissionsSettingsPage> createState() =>
      _PermissionsSettingsPageState();
}

class _PermissionsSettingsPageState extends State<PermissionsSettingsPage>
    with WidgetsBindingObserver {
  final _access = FeaturePermissionService.instance;
  final _remote = RustDeskDebugService();
  final _granted = <FeatureAccess, bool>{};
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remote.addListener(_remoteChanged);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remote.removeListener(_remoteChanged);
    _remote.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  void _remoteChanged() {
    if (!mounted) return;
    setState(() {
      _granted[FeatureAccess.screenCapture] = _remote.hosting;
      _granted[FeatureAccess.remoteInput] = _remote.inputEnabled;
    });
  }

  Future<void> _refresh() async {
    await _remote.initialize();
    final values = <FeatureAccess, bool>{};
    for (final item in FeatureAccess.values) {
      values[item] = await _access.granted(item);
    }
    if (mounted) {
      setState(() {
        _granted.addAll(values);
      });
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
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

  Future<void> _engineOption(
    String key,
    bool value, [
    FeatureAccess? permission,
  ]) async {
    if (value && permission != null && !await _access.ensure([permission])) {
      return;
    }
    await _remote.saveProfileValue(key, value ? 'Y' : 'N');
  }

  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    String t(String f, String e) => fa ? f : e;
    Widget row(
      String name,
      String hint,
      bool value,
      Future<void> Function(bool) change,
      IconData icon,
    ) => SwitchListTile(
      secondary: Icon(icon),
      title: Text(name),
      subtitle: Text(hint),
      value: value,
      onChanged: _busy ? null : (value) => unawaited(_run(() => change(value))),
    );
    return PageSurface(
      useColumns: false,
      maxContentWidth: 980,
      children: [
        GlassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('دسترسی‌های کنترل از راه دور', 'Remote control permissions'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  'هر قابلیت را جدا روشن یا خاموش کنید. تغییرها بلافاصله اعمال می‌شوند.',
                  'Enable or disable each capability individually. Changes apply immediately.',
                ),
              ),
              const SizedBox(height: 12),
              row(
                t('اشتراک صفحه', 'Screen capture'),
                t(
                  'اندروید برای هر جلسه تأیید می‌خواهد.',
                  'Android asks for consent for each session.',
                ),
                _granted[FeatureAccess.screenCapture] == true,
                _remote.setAndroidHosting,
                Icons.screen_share_outlined,
              ),
              row(
                t('کنترل لمس و صفحه‌کلید', 'Input control'),
                t(
                  'سرویس Accessibility خود Localist.',
                  'Localist Accessibility service.',
                ),
                _granted[FeatureAccess.remoteInput] == true,
                (value) async {
                  if (value) {
                    await _remote.openInputPermission();
                  } else {
                    await _remote.disableInputPermission();
                  }
                  await _remote.saveProfileValue(
                    'enable-keyboard',
                    value && await _access.granted(FeatureAccess.remoteInput)
                        ? 'Y'
                        : 'N',
                  );
                },
                Icons.touch_app_outlined,
              ),
              row(
                t('انتقال فایل', 'File transfer'),
                t(
                  'اجازهٔ انتقال فایل در جلسهٔ ریموت.',
                  'Allow file transfers in remote sessions.',
                ),
                _remote.enabled('enable-file-transfer'),
                (value) => _engineOption('enable-file-transfer', value),
                Icons.folder_copy_outlined,
              ),
              row(
                t('صدا', 'Audio capture'),
                t(
                  'برای تماس صوتی، میکروفن هم لازم است.',
                  'Microphone permission is also required for voice calls.',
                ),
                _remote.enabled('enable-audio') &&
                    _granted[FeatureAccess.microphone] == true,
                (value) => _engineOption(
                  'enable-audio',
                  value,
                  FeatureAccess.microphone,
                ),
                Icons.volume_up_outlined,
              ),
              row(
                t('کلیپ‌بورد', 'Clipboard'),
                t(
                  'اجازهٔ تبادل متن کلیپ‌بورد در جلسه.',
                  'Allow exchanging clipboard text in sessions.',
                ),
                _remote.enabled('enable-clipboard'),
                (value) => _engineOption('enable-clipboard', value),
                Icons.content_paste_outlined,
              ),
              row(
                t('اشتراک دوربین', 'Camera sharing'),
                t(
                  'اجازهٔ نمایش دوربین به کاربر مقابل.',
                  'Allow the peer to view your camera.',
                ),
                _remote.enabled('enable-camera') &&
                    _granted[FeatureAccess.camera] == true,
                (value) =>
                    _engineOption('enable-camera', value, FeatureAccess.camera),
                Icons.videocam_outlined,
              ),
              const SizedBox(height: 8),
              Text(
                t(
                  'اگر اندروید Accessibility را محدود کرده است: App info ← منوی سه‌نقطه ← Allow restricted settings؛ سپس سرویس Localist را در Accessibility فعال کنید.',
                  'If Android restricts Accessibility: App info → three-dot menu → Allow restricted settings, then enable Localist in Accessibility.',
                ),
              ),
            ],
          ),
        ),
        if (Platform.isAndroid)
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('دسترسی‌های سیستم', 'System permissions'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  t(
                    'برای خاموش کردن مجوزهای سیستم، صفحهٔ تنظیمات اندروید باز می‌شود. وضعیت با برگشت به برنامه تازه می‌شود.',
                    'To revoke a system permission, Android settings opens. Status refreshes when you return.',
                  ),
                ),
                for (final item in FeatureAccess.values.where(
                  (a) =>
                      a != FeatureAccess.remoteInput &&
                      a != FeatureAccess.screenCapture,
                ))
                  row(
                    _access.label(item, fa),
                    _granted[item] == true
                        ? t('فعال', 'Enabled')
                        : t(
                            'غیرفعال؛ هنگام نیاز درخواست می‌شود',
                            'Off; requested when needed',
                          ),
                    _granted[item] == true,
                    (value) async {
                      if (value) {
                        await _access.ensure([item]);
                      } else {
                        await _access.openSettings(item);
                      }
                    },
                    Icons.verified_user_outlined,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
