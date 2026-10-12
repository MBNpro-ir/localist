import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/localist/connection_card.dart';
import 'package:flutter_hbb/localist/connection_info.dart';
import '../services/rustdesk_debug_service.dart';
import '../services/feature_activity_service.dart';
import '../services/remote_device_service.dart';
import '../widgets/glass.dart';
import '../widgets/feature_page_layout.dart';
import '../widgets/remote_ready_indicator.dart';
import 'remote_address_book.dart';

class RemoteDebugPage extends StatefulWidget {
  const RemoteDebugPage({
    super.key,
    required this.service,
    required this.devices,
  });
  final RustDeskDebugService service;
  final RemoteDeviceService devices;
  @override
  State<RemoteDebugPage> createState() => _RemoteDebugPageState();
}

class _RemoteDebugPageState extends State<RemoteDebugPage>
    with WidgetsBindingObserver {
  RustDeskDebugService get _service => widget.service;
  RemoteDeviceService get _devices => widget.devices;
  final _target = TextEditingController();
  final _password = TextEditingController();
  String _mode = 'connect';
  bool _relay = false;
  String? _relayConfig;
  String _notice = '';
  bool _connecting = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
    _service.addListener(_refreshSavedPeers);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _target.dispose();
    _password.dispose();
    _service.removeListener(_refreshSavedPeers);

    super.dispose();
  }

  Future<void> _initialize() async {
    await _service.initialize();
    if (!mounted) return;
    await _devices.initialize();
    if (!mounted) return;
    final known = _devices.devices.map((d) => d.id).toSet();
    for (final id in _service.recent.reversed) {
      if (!known.contains(id)) await _devices.rememberOpened(id);
    }
    await _refreshSavedPeers();
  }

  bool _loadingPeers = false;
  Future<void> _refreshSavedPeers() async {
    if (!mounted) return;
    final config = _service.profile.server.encode();
    if (_relayConfig != config) {
      _relayConfig = config;
      _relay = _service.profile.server.usesRelay;
    }
    _devices.setPresenceContext(
      server: config,
      ready: _service.ready && _service.online,
    );
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
            const SizedBox(height: 4),
            Text(
              'Powered by RustDesk',
              textDirection: TextDirection.ltr,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: .4,
              ),
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
                  RemoteReadyIndicator(
                    ready: _service.ready,
                    online: _service.online,
                    hosting: _service.hosting,
                    server: _service.serverLabel,
                  ),
                  const SizedBox(height: 10),
                  if (_service.localId.isNotEmpty)
                    LocalistConnectionCard(
                      id: _service.localId,
                      password: _service.localPassword,
                      onCopyId: () => _copy(
                        _service.localId,
                        t(
                          'آیدی ${_service.localId} کپی شد.',
                          'ID ${_service.localId} copied.',
                        ),
                      ),
                      onCopyPassword: _service.localPassword.isEmpty
                          ? null
                          : () => _copy(
                              _service.localPassword,
                              t(
                                'رمز یک‌بارمصرف کپی شد.',
                                'One-time password copied.',
                              ),
                            ),
                      onCopyConnection: () => _copy(
                        RemoteConnectionInfo(
                          id: _service.localId,
                          password: _service.localPassword,
                        ).toClipboardText(),
                        t(
                          'آیدی و رمز اتصال کپی شدند.',
                          'Connection ID and password copied.',
                        ),
                      ),
                    )
                  else
                    Text(
                      t('شناسه در حال آماده‌سازی است…', 'Preparing your ID…'),
                    ),
                  if (Platform.isAndroid) ...[
                    const SizedBox(height: 16),
                    Text(
                      t(
                        'درخواست اتصال روی همین گوشی نمایش داده می‌شود. می‌توانید آن را قبول کنید یا رمز یک‌بارمصرف را بفرستید. رمز ثابت اختیاری است و در تنظیمات امنیت قرار دارد.',
                        'Incoming requests appear on this phone. Accept the request or share your one-time password. A permanent password is optional in Security settings.',
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    subtitle: _service.profile.server.usesRelay
                        ? Text(
                            t(
                              'برای سرور شخصی به‌صورت خودکار فعال است.',
                              'Enabled automatically for your private server.',
                            ),
                          )
                        : null,
                    onChanged: _service.profile.server.usesRelay
                        ? null
                        : (v) => setState(() => _relay = v),
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
          ],
          fullWidthSections: [
            RemoteAddressBook(
              service: _devices,
              localId: _service.localId,
              canConnect: _service.ready && !_connecting,
              onConnect: (id) {
                _target.text = id;
                _password.clear();
                unawaited(_launch());
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launch() async {
    if (_connecting) return;
    if (!FeatureActivityService.instance.reserve(
      this,
      LocalistFeature.remoteControl,
    )) {
      setState(
        () => _notice = faText(
          context,
          'ابتدا سرویس فعال را متوقف کنید.',
          'Stop the active service first.',
        ),
      );
      return;
    }
    setState(() => _connecting = true);
    try {
      await _service.launch(
        target: _target.text,
        mode: _mode,
        relay: _relay,
        password: _password.text,
      );
      if (_target.text.trim().isNotEmpty) {
        await _devices.rememberOpened(normalizeRemoteTarget(_target.text));
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
      await _service.refresh();
      FeatureActivityService.instance.setActive(
        this,
        LocalistFeature.remoteControl,
        false,
      );
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

  Future<void> _copy(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      showLocalistNotice(
        context,
        message: message,
        tone: InAppNoticeTone.success,
        icon: Icons.check_circle_outline,
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
