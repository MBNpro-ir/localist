import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/localist/connection_card.dart';
import 'package:flutter_hbb/localist/connection_info.dart';
import '../services/rustdesk_debug_service.dart';
import '../services/remote_device_service.dart';
import '../widgets/glass.dart';
import '../widgets/feature_page_layout.dart';

class RemoteDebugPage extends StatefulWidget {
  const RemoteDebugPage({super.key});
  @override
  State<RemoteDebugPage> createState() => _RemoteDebugPageState();
}

class _RemoteDebugPageState extends State<RemoteDebugPage>
    with WidgetsBindingObserver {
  final _service = RustDeskDebugService();
  final _devices = RemoteDeviceService();
  final _target = TextEditingController();
  final _password = TextEditingController();
  String _mode = 'connect';
  bool _relay = false;
  String _notice = '';
  bool _connecting = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_service.initialize());
    unawaited(_devices.initialize());
    _service.addListener(_refreshSavedPeers);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _target.dispose();
    _password.dispose();
    _service.removeListener(_refreshSavedPeers);
    _service.dispose();
    _devices.dispose();
    super.dispose();
  }

  bool _loadingPeers = false;
  Future<void> _refreshSavedPeers() async {
    if (_loadingPeers || !_service.ready) return;
    _loadingPeers = true;
    try {
      for (final device in _devices.devices) {
        await _devices.updatePeerInfo(
          device.id,
          await _service.savedPeer(device.id),
        );
      }
    } catch (_) {
      // Existing saved names remain available while the host reconnects.
    } finally {
      _loadingPeers = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_service.initialize());
    }
  }

  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    String t(String f, String e) => fa ? f : e;
    return GlassBackground(
      simple: true,
      child: AnimatedBuilder(
        animation: _service,
        builder: (context, _) => FeaturePageLayout(
          heading: [
            Text(
              t('کنترل از راه دور', 'Remote Control'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'اتصال کنترل از راه دور، انتقال فایل، دوربین، ترمینال و تونل شبکه از همین بخش مدیریت می‌شود.',
                'Remote sessions, file transfer, camera, terminal and network tunnelling are managed here.',
              ),
            ),
          ],
          sections: [
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('این دستگاه', 'This device'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: Icon(
                          _service.online
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_off_outlined,
                        ),
                        label: Text(
                          _service.online
                              ? t('متصل به سرور', 'Server connected')
                              : _service.ready
                              ? t('در انتظار شبکه', 'Waiting for network')
                              : t('در حال آماده‌سازی', 'Starting engine'),
                        ),
                      ),
                      Chip(
                        label: Text(
                          _service.hosting
                              ? t('میزبانی فعال', 'Hosting active')
                              : t('میزبانی متوقف', 'Hosting stopped'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_service.localId.isNotEmpty)
                    LocalistConnectionCard(
                      id: _service.localId,
                      password: _service.localPassword,
                      onCopyId: () => _copy(_service.localId),
                      onCopyPassword: _service.localPassword.isEmpty
                          ? null
                          : () => _copy(_service.localPassword),
                      onCopyConnection: () => _copy(
                        RemoteConnectionInfo(
                          id: _service.localId,
                          password: _service.localPassword,
                        ).toClipboardText(),
                      ),
                    )
                  else
                    Text(
                      t('شناسه در حال آماده‌سازی است…', 'Preparing your ID…'),
                    ),
                  if (Platform.isAndroid) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _service.ready
                          ? () => unawaited(_hosting())
                          : null,
                      icon: Icon(
                        _service.hosting
                            ? Icons.stop_screen_share_outlined
                            : Icons.screen_share_outlined,
                      ),
                      label: Text(
                        _service.hosting
                            ? t('توقف میزبانی', 'Stop hosting')
                            : t(
                                'شروع میزبانی و اشتراک صفحه',
                                'Start hosting and share screen',
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          unawaited(_service.openInputPermission()),
                      icon: const Icon(Icons.touch_app_outlined),
                      label: Text(
                        _service.inputEnabled
                            ? t(
                                'مجوز کنترل فعال است',
                                'Input permission enabled',
                              )
                            : t(
                                'فعال کردن مجوز کنترل',
                                'Enable input permission',
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _target,
                    decoration: InputDecoration(
                      labelText: t('شناسه یا IP مقصد', 'Remote ID or IP'),
                      prefixIcon: const Icon(Icons.computer),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: t(
                        'رمز جلسه (ذخیره نمی‌شود)',
                        'Session password (not saved)',
                      ),
                    ),
                  ),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _mode,
                    items: [
                      for (final mode in RustDeskDebugService.modes)
                        if (Platform.isWindows ||
                            (mode != 'port-forward' && mode != 'rdp'))
                          DropdownMenuItem(
                            value: mode,
                            child: Text(switch (mode) {
                              'connect' => t('کنترل صفحه', 'Remote desktop'),
                              'file-transfer' => t(
                                'انتقال فایل',
                                'File transfer',
                              ),
                              'view-camera' => t('دوربین', 'Camera'),
                              'terminal' => t('ترمینال', 'Terminal'),
                              'port-forward' => t(
                                'تونل شبکه',
                                'Network tunnel',
                              ),
                              _ => 'RDP',
                            }),
                          ),
                    ],
                    onChanged: (mode) => setState(() => _mode = mode!),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('استفاده از Relay', 'Use relay')),
                    value: _relay,
                    onChanged: (v) => setState(() => _relay = v),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _connecting || !_service.ready
                            ? null
                            : () => unawaited(_launch()),
                        icon: const Icon(Icons.link),
                        label: Text(t('اتصال', 'Connect')),
                      ),
                      OutlinedButton.icon(
                        onPressed: _connecting || !_service.ready
                            ? null
                            : () => unawaited(_pasteAndConnect()),
                        icon: const Icon(Icons.content_paste_go_outlined),
                        label: Text(t('چسباندن و اتصال', 'Paste & connect')),
                      ),
                    ],
                  ),
                  if (_notice.isNotEmpty || _service.error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _notice.isNotEmpty ? _notice : _service.error,
                      ),
                    ),
                ],
              ),
            ),
            if (_service.recent.isNotEmpty) ...[
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('اتصال‌های اخیر', 'Recent connections'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final id in _service.recent)
                      ListTile(
                        leading: const Icon(Icons.computer),
                        title: Text(id),
                        onTap: () => _target.text = id,
                      ),
                  ],
                ),
              ),
            ],
            AnimatedBuilder(
              animation: _devices,
              builder: (context, _) => GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t(
                              'دستگاه‌های شبکه و ذخیره‌شده',
                              'LAN and saved devices',
                            ),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: t('جستجوی شبکه', 'Scan LAN'),
                          onPressed: _devices.scanning
                              ? null
                              : () => unawaited(
                                  _devices.scan(localId: _service.localId),
                                ),
                          icon: _devices.scanning
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.radar),
                        ),
                      ],
                    ),
                    Text(
                      t(
                        'شناسه، نام، مدل و آخرین وضعیت شبکه ذخیره می‌شود؛ اتصال فقط با اقدام شما انجام می‌گیرد.',
                        'ID, name, model and the last LAN state are saved; connections are opened only by your action.',
                      ),
                    ),
                    if (_devices.error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_devices.error),
                      ),
                    if (_devices.devices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          t(
                            'هنوز دستگاهی ثبت نشده است.',
                            'No devices have been saved yet.',
                          ),
                        ),
                      ),
                    for (final device in _devices.devices)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          device.onLan ? Icons.wifi : Icons.history,
                        ),
                        title: Text(
                          device.name.isNotEmpty ? device.name : device.id,
                        ),
                        subtitle: Text(
                          [
                            'ID: ${device.id}',
                            if (device.model.isNotEmpty) device.model,
                            if (device.platform.isNotEmpty) device.platform,
                            if (device.ip.isNotEmpty) device.ip,
                            device.onLan
                                ? t('در شبکه', 'Online on LAN')
                                : t('ذخیره‌شده', 'Saved'),
                          ].join(' • '),
                        ),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: t('اتصال', 'Connect'),
                              onPressed: () {
                                _target.text = device.id;
                                unawaited(_launch());
                              },
                              icon: const Icon(Icons.link),
                            ),
                            IconButton(
                              tooltip: t('حذف', 'Forget'),
                              onPressed: () =>
                                  unawaited(_devices.forget(device.id)),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        onTap: () => setState(() => _target.text = device.id),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      await _service.launch(
        target: _target.text,
        mode: _mode,
        relay: _relay,
        password: _password.text,
      );
      if (_target.text.trim().isNotEmpty) {
        await _devices.rememberOpened(_target.text.trim());
      }
      if (mounted) {
        setState(
          () => _notice = faText(
            context,
            'درخواست اتصال ارسال شد؛ وضعیت اتصال در پنجرهٔ جلسه نمایش داده می‌شود.',
            'Connection requested. The session window shows its status.',
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _notice = '$error');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _hosting() async {
    try {
      await _service.setAndroidHosting(!_service.hosting);
    } catch (error) {
      if (mounted) setState(() => _notice = '$error');
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      setState(
        () => _notice = faText(
          context,
          'در کلیپ‌بورد کپی شد.',
          'Copied to clipboard.',
        ),
      );
    }
  }

  Future<void> _pasteAndConnect() async {
    try {
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final info = RemoteConnectionInfo.parse(clip?.text ?? '');
      _target.text = info.id;
      _password.text = info.password;
      await _launch();
    } catch (error) {
      if (mounted) setState(() => _notice = '$error');
    }
  }
}

String faText(BuildContext context, String fa, String en) =>
    Localizations.localeOf(context).languageCode == 'fa' ? fa : en;
