import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/remote_control_settings.dart';
import '../services/rustdesk_debug_service.dart';

class RemoteControlSettingsSection extends StatefulWidget {
  const RemoteControlSettingsSection({super.key, this.service});
  final RustDeskDebugService? service;
  @override
  State<RemoteControlSettingsSection> createState() =>
      _RemoteControlSettingsSectionState();
}

class _RemoteControlSettingsSectionState
    extends State<RemoteControlSettingsSection>
    with WidgetsBindingObserver {
  late final _engine = widget.service ?? RustDeskDebugService();
  RemoteSettingsTab _tab = RemoteSettingsTab.general;
  final _code = TextEditingController();
  final _idServer = TextEditingController();
  final _relayServer = TextEditingController();
  final _apiServer = TextEditingController();
  final _key = TextEditingController();
  final Map<String, TextEditingController> _fields = {};
  final Map<String, Timer> _saveTimers = {};
  final Map<String, String> _pendingValues = {};
  Timer? _serverSaveTimer;
  bool _ready = false;
  bool _serverEdited = false;
  String _notice = '';
  List<String> _printers = [];
  bool _loadingPrinters = false;
  String? _printerError;
  List<String> _audioInputs = [];
  String? _audioError;
  bool _loadingAudio = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _ready && !_serverEdited) {
      unawaited(_reloadEngineProfile());
    }
  }

  Future<void> _reloadEngineProfile() async {
    await _engine.initialize();
    if (!mounted || _serverEdited) return;
    _fillServer(_engine.profile.server);
    for (final entry in _fields.entries) {
      entry.value.text = _engine.profile.values[entry.key] ?? '';
    }
    setState(() {});
  }

  Future<void> _load() async {
    await _engine.initialize();
    if (!mounted) return;
    _fillServer(_engine.profile.server);
    for (final setting in remoteSettings.where(
      (s) => !s.boolean && s.choices == null,
    )) {
      _fields[setting.key] = TextEditingController(
        text: _engine.profile.values[setting.key],
      );
    }
    setState(() => _ready = true);
    unawaited(_loadPrinters());
    unawaited(_loadAudioInputs());
  }

  Future<void> _loadAudioInputs() async {
    if (_loadingAudio) return;
    setState(() {
      _loadingAudio = true;
      _audioError = null;
    });
    try {
      final names = await _engine.audioInputNames();
      if (mounted) setState(() => _audioInputs = names);
    } catch (e) {
      if (mounted) setState(() => _audioError = '$e');
    } finally {
      if (mounted) setState(() => _loadingAudio = false);
    }
  }

  Future<void> _loadPrinters() async {
    if (_loadingPrinters || !Platform.isWindows) return;
    setState(() {
      _loadingPrinters = true;
      _printerError = null;
    });
    try {
      final names = await _engine.printerNames();
      if (!mounted) return;
      setState(() => _printers = names);
    } catch (e) {
      if (mounted) setState(() => _printerError = '$e');
    } finally {
      if (mounted) setState(() => _loadingPrinters = false);
    }
  }

  void _fillServer(RemoteServerConfig config) {
    _idServer.text = config.idServer;
    _relayServer.text = config.relayServer;
    _apiServer.text = config.apiServer;
    _key.text = config.key;
    _serverEdited = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in _saveTimers.values) {
      timer.cancel();
    }
    for (final entry in _pendingValues.entries) {
      unawaited(_save(entry.key, entry.value));
    }
    _serverSaveTimer?.cancel();
    if (_serverEdited) unawaited(_autoSaveServer());
    if (widget.service == null) _engine.dispose();
    for (final controller in [
      _code,
      _idServer,
      _relayServer,
      _apiServer,
      _key,
      ..._fields.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _choiceName(String name) => context.l10n.isPersian
      ? const {
              'Default': 'پیش‌فرض',
              'English': 'انگلیسی',
              'System sound': 'صدای سیستم',
              'Custom': 'سفارشی',
              'Full access': 'دسترسی کامل',
              'Screen share': 'اشتراک صفحه',
              'One-time password': 'رمز یک‌بارمصرف',
              'Permanent password': 'رمز ثابت',
              'Both passwords': 'هر دو رمز',
              'Password only': 'فقط رمز',
              'Click to approve': 'تأیید دستی',
              'Password or click to approve': 'رمز یا تأیید دستی',
              'Scale original': 'اندازه اصلی',
              'Scale adaptive': 'اندازه متناسب',
              'ScrollAuto': 'پیمایش خودکار',
              'Scrollbar': 'نوار پیمایش',
              'ScrollEdge': 'پیمایش در لبه',
              'Good image quality': 'کیفیت تصویر بالا',
              'Balanced': 'متعادل',
              'Optimize reaction time': 'پاسخ سریع‌تر',
              'Auto': 'خودکار',
              'Mode 1': 'حالت ۱',
              'Mode 2': 'حالت ۲',
              'Dismiss': 'رد کردن',
              'Use the default printer': 'چاپگر پیش‌فرض',
              'Use the selected printer': 'چاپگر انتخاب‌شده',
              'ID server': 'سرور شناسه',
              'Relay server': 'سرور واسط',
              'API server': 'سرور API',
              'Key': 'کلید عمومی',
            }[name] ??
            name
      : name;
  String _t(String fa, String en) => context.l10n.isPersian ? fa : en;
  String _tabName(RemoteSettingsTab tab) => switch (tab) {
    RemoteSettingsTab.general => _t('عمومی', 'General'),
    RemoteSettingsTab.security => _t('امنیت', 'Security'),
    RemoteSettingsTab.network => _t('شبکه', 'Network'),
    RemoteSettingsTab.display => _t('نمایش', 'Display'),
    RemoteSettingsTab.printer => _t('چاپگر', 'Printer'),
  };
  IconData _tabIcon(RemoteSettingsTab tab) => switch (tab) {
    RemoteSettingsTab.general => Icons.tune,
    RemoteSettingsTab.security => Icons.shield_outlined,
    RemoteSettingsTab.network => Icons.dns_outlined,
    RemoteSettingsTab.display => Icons.desktop_windows_outlined,
    RemoteSettingsTab.printer => Icons.print_outlined,
  };
  String _cardName(String name) => context.l10n.isPersian
      ? switch (name) {
          'Service' => 'سرویس',
          'Theme' => 'پوسته',
          'Language' => 'زبان',
          'Hardware codec' => 'کدک سخت‌افزاری',
          'Audio input device' => 'دستگاه ورودی صدا',
          'Other' => 'سایر',
          'Permissions' => 'مجوزها',
          'Security' => 'امنیت',
          'Password' => 'رمز و تأیید اتصال',
          'Network' => 'شبکه',
          'Default view style' => 'اندازه پیش‌فرض تصویر',
          'Default scroll style' => 'پیمایش پیش‌فرض',
          'Default image quality' => 'کیفیت پیش‌فرض تصویر',
          'Default codec' => 'کدک پیش‌فرض',
          'Privacy mode' => 'حالت حریم خصوصی',
          'Other default options' => 'سایر پیش‌فرض‌ها',
          'Incoming print jobs' => 'کارهای چاپ ورودی',
          _ => name,
        }
      : name;

  bool _settingAvailable(RemoteSetting setting) {
    if (setting.key == 'enable-check-update' ||
        setting.key == 'allow-auto-update') {
      return false; // Localist's updater owns the bundled engine.
    }
    if (setting.key == 'enable-hwcodec') return _engine.hardwareCodecSupported;
    if (setting.key == 'allow-only-conn-window-open') {
      return _engine.installedService;
    }
    if (!Platform.isWindows &&
        const {
          'allow-d3d-render',
          'enable-directx-capture',
          'share-rdp',
          'enable-block-input',
          'enable-remote-printer',
          'enable-privacy-mode',
          'privacy-mode-impl-key',
          'allow-remove-wallpaper',
          'displays_as_individual_windows',
          'use_all_my_displays_for_the_remote_session',
        }.contains(setting.key)) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return AnimatedBuilder(
      animation: _engine,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 760;
          final tabs = Material(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: wide
                ? SizedBox(
                    width: 220,
                    child: ListView(
                      children: [
                        for (final tab in RemoteSettingsTab.values)
                          ListTile(
                            leading: Icon(_tabIcon(tab)),
                            selected: _tab == tab,
                            title: Text(_tabName(tab)),
                            onTap: () => setState(() => _tab = tab),
                          ),
                      ],
                    ),
                  )
                : SizedBox(
                    height: 64,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          for (final tab in RemoteSettingsTab.values)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 8),
                              child: ChoiceChip(
                                avatar: Icon(_tabIcon(tab), size: 18),
                                label: Text(_tabName(tab)),
                                selected: _tab == tab,
                                onSelected: (_) => setState(() => _tab = tab),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          );
          final cards = <Widget>[
            if (_tab == RemoteSettingsTab.network) _serverCard(),
            for (final card
                in remoteSettings
                    .where((s) => s.tab == _tab && _settingAvailable(s))
                    .map((s) => s.card)
                    .toSet())
              _card(_cardName(card), [
                for (final setting in remoteSettings.where(
                  (s) =>
                      s.tab == _tab &&
                      s.card == card &&
                      _settingAvailable(s) &&
                      (s.key != 'verification-method' ||
                          _engine.hasPermanentPassword),
                ))
                  _setting(setting),
                if (card == 'Password') _passwordControls(),
              ]),
          ];
          final content = LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_notice.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_notice),
                    ),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    children: [
                      for (final card in cards)
                        SizedBox(
                          width: box.maxWidth >= 850
                              ? (box.maxWidth - 56) / 2
                              : box.maxWidth - 40,
                          child: card,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
          return wide
              ? Row(
                  children: [
                    tabs,
                    Expanded(child: content),
                  ],
                )
              : Column(
                  children: [
                    tabs,
                    Expanded(child: content),
                  ],
                );
        },
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Card(
    margin: EdgeInsets.zero,
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  String? _scopeNotice(RemoteSetting setting) => switch (setting.scope) {
    RemoteOptionScope.server =>
      Platform.isWindows || Platform.isAndroid
          ? null
          : _t(
              'ذخیره در پروفایل؛ موتور داخلی اندروید هنوز متصل نیست',
              'Saved in profile; Android embedded engine is pending',
            ),
    RemoteOptionScope.local =>
      Platform.isAndroid || Platform.isWindows
          ? null
          : _t(
              'ذخیره در پروفایل؛ اعمال در رابط موتور داخلی هنوز آماده نیست',
              'Saved in profile; embedded UI support is pending',
            ),
    RemoteOptionScope.display =>
      Platform.isAndroid || Platform.isWindows
          ? null
          : _t(
              'پیش‌فرض جلسه؛ اعمال در موتور داخلی هنوز آماده نیست',
              'Session default; embedded engine support is pending',
            ),
    RemoteOptionScope.native => null,
  };

  Widget _setting(RemoteSetting setting) {
    final label = context.l10n.isPersian ? setting.fa : setting.en;
    final value = setting.key == 'share-rdp'
        ? (_engine.rdpShared ? 'Y' : 'N')
        : setting.key == 'force-always-relay'
        ? (_engine.profile.server.usesRelay ? 'Y' : 'N')
        : _engine.profile.values[setting.key] ?? setting.defaultValue;
    final scope = _scopeNotice(setting);
    final passwordDisabled = _engine.profile.values['approve-mode'] == 'click';
    final temporaryDisabled =
        passwordDisabled ||
        _engine.profile.values['verification-method'] ==
            'use-permanent-password';
    final disabled =
        _engine.busy ||
        setting.key == 'force-always-relay' ||
        (setting.key == 'verification-method' && passwordDisabled) ||
        (const {
              'temporary-password-length',
              'allow-numeric-one-time-password',
            }.contains(setting.key) &&
            temporaryDisabled);
    final accessMode = _engine.profile.values['access-mode'] ?? '';
    final permissionPreset =
        setting.card == 'Permissions' &&
        setting.boolean &&
        accessMode.isNotEmpty;
    if (setting.key == 'printer-selected-name') return _printerPicker();
    if (setting.key == 'audio-input') return _audioInputPicker();
    if (setting.tab == RemoteSettingsTab.printer && !Platform.isWindows) {
      return setting.key == 'printer-incomming-job-action'
          ? Text(
              _t(
                'دریافت کار چاپ روی ویندوز پشتیبانی می‌شود.',
                'Receiving print jobs is supported on Windows.',
              ),
            )
          : const SizedBox.shrink();
    }
    if (setting.key == '2fa') {
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(label),
        value: _engine.twoFactorEnabled,
        onChanged: disabled
            ? null
            : (enabled) => unawaited(_changeTwoFactor(enabled!)),
      );
    }
    if (setting.key == 'share-rdp' && !Platform.isWindows) {
      return const SizedBox.shrink();
    }
    if (setting.boolean) {
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        visualDensity: VisualDensity.compact,
        title: Text(label),
        subtitle: scope == null ? null : Text(scope),
        value: permissionPreset ? accessMode == 'full' : value == 'Y',
        onChanged: disabled || permissionPreset
            ? null
            : (v) => unawaited(_save(setting.key, v! ? 'Y' : 'N')),
      );
    }
    if (setting.choices != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              key: ValueKey('${setting.key}:$value'),
              initialValue: setting.choices!.containsKey(value)
                  ? value
                  : setting.defaultValue,
              isExpanded: true,
              items: [
                for (final entry in setting.choices!.entries)
                  if (setting.key != 'printer-incomming-job-action' ||
                      entry.key != 'selected' ||
                      value == 'selected' ||
                      _printers.isNotEmpty)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(
                        _choiceName(entry.value),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: disabled
                  ? null
                  : (v) => unawaited(_save(setting.key, v!)),
            ),
            if (scope != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  scope,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: _fields[setting.key],
        enabled: !disabled,
        decoration: InputDecoration(
          labelText: label,
          helperText: scope,
          helperMaxLines: 3,
        ),
        onChanged: (v) => _queueSave(setting.key, v.trim()),
        onSubmitted: (_) => _flushSave(setting.key),
      ),
    );
  }

  Widget _printerPicker() {
    if (!Platform.isWindows) return const SizedBox.shrink();
    final selected = _engine.profile.values['printer-selected-name'];
    final unavailable =
        selected != null &&
        selected.isNotEmpty &&
        !_printers.contains(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(_t('چاپگر این دستگاه', 'Printer on this device')),
            ),
            IconButton(
              onPressed: _loadingPrinters ? null : _loadPrinters,
              tooltip: _t('تازه‌سازی چاپگرها', 'Refresh printers'),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_loadingPrinters) const LinearProgressIndicator(),
        if (_printerError != null) Text(_printerError!),
        if (_printers.isEmpty && !_loadingPrinters)
          Text(
            _t(
              'چاپگری در ویندوز یافت نشد. پس از افزودن چاپگر، تازه‌سازی کنید.',
              'No Windows printers found. Add a printer, then refresh.',
            ),
          ),
        if (unavailable)
          Text(
            _t(
              'چاپگر ذخیره‌شده در دسترس نیست: $selected. انتخاب شما حفظ شده است.',
              'Saved printer unavailable: $selected. Your selection is preserved.',
            ),
          ),
        if (_printers.isNotEmpty || unavailable)
          DropdownButtonFormField<String>(
            key: ValueKey('printer:$selected:${_printers.join('|')}'),
            initialValue: selected != null && selected.isNotEmpty
                ? selected
                : null,
            isExpanded: true,
            hint: Text(_t('انتخاب چاپگر', 'Select printer')),
            items: [
              if (unavailable)
                DropdownMenuItem(
                  value: selected,
                  enabled: false,
                  child: Text(selected, overflow: TextOverflow.ellipsis),
                ),
              for (final name in _printers)
                DropdownMenuItem(
                  value: name,
                  child: Text(name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (name) async {
              if (name == null) return;
              await _save('printer-selected-name', name);
              await _save('printer-incomming-job-action', 'selected');
            },
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _audioInputPicker() {
    final selected = _engine.profile.values['audio-input'] ?? '';
    final names = {'', ..._audioInputs, if (selected.isNotEmpty) selected};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(_t('ورودی صدا', 'Audio input device'))),
            IconButton(
              onPressed: _loadingAudio ? null : _loadAudioInputs,
              tooltip: _t('تازه‌سازی ورودی‌های صدا', 'Refresh audio inputs'),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_loadingAudio) const LinearProgressIndicator(),
        if (_audioError != null) Text(_audioError!),
        DropdownButtonFormField<String>(
          key: ValueKey('audio:$selected:${names.join('|')}'),
          initialValue: selected,
          isExpanded: true,
          items: [
            for (final name in names)
              DropdownMenuItem(
                value: name,
                child: Text(
                  name.isEmpty
                      ? _t('صدای پیش‌فرض دستگاه', 'Default device audio')
                      : name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _engine.busy
              ? null
              : (name) {
                  if (name != null) unawaited(_save('audio-input', name));
                },
        ),
      ],
    );
  }

  Widget _serverCard() => _card('ID/Relay server', [
    Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          key: const ValueKey('remote-import'),
          style: FilledButton.styleFrom(minimumSize: const Size(155, 52)),
          onPressed: () => unawaited(_import()),
          icon: const Icon(Icons.content_paste),
          label: Text(_t('وارد کردن · Import', 'Import configuration')),
        ),
        OutlinedButton.icon(
          key: const ValueKey('remote-export'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(155, 52)),
          onPressed: () => unawaited(_export()),
          icon: const Icon(Icons.copy),
          label: Text(_t('کپی کردن · Export', 'Export configuration')),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            const config = RemoteServerConfig();
            _serverSaveTimer?.cancel();
            await _engine.saveServerConfig(config);
            if (mounted) {
              setState(() {
                _fillServer(config);
                _serverEdited = false;
              });
            }
          },
          icon: const Icon(Icons.public),
          label: Text(_t('استفاده از سرورهای عمومی', 'Use public servers')),
        ),
      ],
    ),
    const SizedBox(height: 14),
    TextField(
      key: const ValueKey('remote-server-code'),
      controller: _code,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: _t(
          'کد تنظیمات (یا Import از کلیپ‌بورد)',
          'Configuration code (or import from clipboard)',
        ),
      ),
    ),
    const SizedBox(height: 16),
    for (final entry in {
      'ID server': _idServer,
      'Relay server': _relayServer,
      'API server': _apiServer,
      'Key': _key,
    }.entries)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: entry.value,
          onChanged: (_) {
            setState(() => _serverEdited = true);
            _serverSaveTimer?.cancel();
            _serverSaveTimer = Timer(
              const Duration(milliseconds: 650),
              () => unawaited(_autoSaveServer()),
            );
          },
          decoration: InputDecoration(labelText: _choiceName(entry.key)),
        ),
      ),
    if (_serverEdited)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _t(
            'تغییرات معتبر به‌صورت خودکار اعمال می‌شوند',
            'Valid changes are applied automatically',
          ),
        ),
      ),
  ]);

  RemoteServerConfig _formConfig() => RemoteServerConfig(
    idServer: _idServer.text.trim(),
    relayServer: _relayServer.text.trim(),
    apiServer: _apiServer.text.trim(),
    key: _key.text.trim(),
  );
  Future<void> _autoSaveServer() async {
    try {
      final config = _formConfig();
      config.validate();
      await _engine.saveServerConfig(config);
      if (mounted) setState(() => _serverEdited = false);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _import() async {
    try {
      var value = _code.text.trim();
      if (value.isEmpty) {
        value =
            (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
      }
      final config = RemoteServerConfig.decode(value);
      await _engine.saveServerConfig(config);
      if (mounted) {
        setState(() {
          _fillServer(config);
          _notice = _t(
            'Import موفق؛ چهار فیلد خودکار پر و ذخیره شدند',
            'Imported: all four fields filled and saved',
          );
        });
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _export() async {
    try {
      final config = _formConfig();
      config.validate();
      await Clipboard.setData(ClipboardData(text: config.encode()));
      if (mounted) {
        setState(
          () => _notice = _t('کد تنظیمات کپی شد', 'Configuration copied'),
        );
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _save(String key, String value) async {
    try {
      await _engine.saveProfileValue(key, value);
      if (mounted) {
        setState(
          () => _notice = _t(
            'ذخیره شد و خودکار اعمال می‌شود',
            'Saved and applied automatically',
          ),
        );
      }
    } catch (e) {
      _showError(e);
    }
  }

  void _queueSave(String key, String value) {
    _pendingValues[key] = value;
    _saveTimers.remove(key)?.cancel();
    _saveTimers[key] = Timer(
      const Duration(milliseconds: 650),
      () => _flushSave(key),
    );
  }

  void _flushSave(String key) {
    _saveTimers.remove(key)?.cancel();
    final value = _pendingValues.remove(key);
    if (value != null) unawaited(_save(key, value));
  }

  Widget _passwordControls() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_engine.profile.values['approve-mode'] == 'click') ...[
          Text(
            _t(
              'در حالت تأیید دستی، ورود با رمز غیرفعال است. تنظیم رمز دائمی، ورود با رمز یا تأیید دستی را فعال می‌کند.',
              'Manual approval disables password login. Setting a permanent password enables password or manual approval.',
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (!_engine.hasPermanentPassword &&
            _engine.profile.values['approve-mode'] != 'click') ...[
          Text(
            _t(
              'رمز دائمی تنظیم نشده؛ اتصال با رمز یک‌بارمصرف انجین انجام می‌شود.',
              'No permanent password is set. Connections use the engine’s one-time password.',
            ),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: () => unawaited(_changePermanentPassword()),
              icon: const Icon(Icons.password),
              label: Text(_t('تنظیم رمز دائمی', 'Set permanent password')),
            ),
            OutlinedButton.icon(
              onPressed:
                  _engine.profile.values['approve-mode'] == 'click' ||
                      _engine.profile.values['verification-method'] ==
                          'use-permanent-password'
                  ? null
                  : () async {
                      try {
                        await _engine.regeneratePassword();
                        if (mounted) {
                          setState(
                            () => _notice = _t(
                              'رمز موقت جدید ساخته شد',
                              'Temporary password regenerated',
                            ),
                          );
                        }
                      } catch (e) {
                        _showError(e);
                      }
                    },
              icon: const Icon(Icons.refresh),
              label: Text(_t('رمز موقت جدید', 'Regenerate temporary password')),
            ),
            if (_engine.hasPermanentPassword)
              TextButton.icon(
                onPressed: () async {
                  try {
                    await _engine.setPermanentPassword('');
                    if (mounted) {
                      setState(
                        () => _notice = _t(
                          'رمز دائمی حذف شد؛ نوع رمز به یک‌بارمصرف برگشت',
                          'Permanent password removed; password type reset to one-time',
                        ),
                      );
                    }
                  } catch (e) {
                    _showError(e);
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: Text(_t('حذف رمز دائمی', 'Remove permanent password')),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> _changePermanentPassword() async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    String? error;
    bool saving = false;
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            scrollable: true,
            title: Text(
              _t('رمز دائمی ریموت کنترل', 'Remote control permanent password'),
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: password,
                    obscureText: true,
                    autocorrect: false,
                    maxLength: 128,
                    decoration: InputDecoration(
                      labelText: _t('رمز جدید', 'New password'),
                      helperMaxLines: 3,
                      helperText: _t(
                        '۸ تا ۱۲۸ کاراکتر؛ شامل رقم، حرف بزرگ و کوچک انگلیسی',
                        '8–128 characters with a digit, upper and lower case letter',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmation,
                    obscureText: true,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: _t('تکرار رمز', 'Confirm password'),
                      errorText: error,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: Text(_t('لغو', 'Cancel')),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final newPassword = password.text.trim();
                        final validation = permanentPasswordValidationError(
                          newPassword,
                        );
                        if (newPassword.isEmpty ||
                            validation != null ||
                            newPassword != confirmation.text.trim()) {
                          update(
                            () => error = _t(
                              newPassword.isEmpty
                                  ? 'رمز جدید را وارد کنید؛ برای حذف از دکمه حذف رمز استفاده کنید'
                                  : validation == null
                                  ? 'تکرار رمز با رمز جدید یکسان نیست'
                                  : 'رمز باید حداقل ۸ کاراکتر، شامل رقم، حرف بزرگ و حرف کوچک باشد',
                              newPassword.isEmpty
                                  ? 'Enter a new password; use Remove password to clear it'
                                  : validation == null
                                  ? 'The confirmation does not match'
                                  : 'Use at least 8 characters with a digit, upper and lower case letter',
                            ),
                          );
                          return;
                        }
                        update(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await _engine.setPermanentPassword(newPassword);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (mounted) {
                            setState(
                              () => _notice = _t(
                                'رمز دائمی ذخیره و برای اتصال فعال شد',
                                'Permanent password saved and enabled for connections',
                              ),
                            );
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            update(() {
                              saving = false;
                              error = '$e';
                            });
                          }
                        }
                      },
                child: Text(_t('تنظیم رمز', 'Set password')),
              ),
            ],
          ),
        ),
      ),
    );
    await Navigator.of(context).push(route);
    // A popped dialog remains mounted during its exit animation.
    await route.completed;
    password.dispose();
    confirmation.dispose();
  }

  Future<void> _changeTwoFactor(bool enabled) async {
    try {
      if (!enabled) {
        await _engine.disableTwoFactor();
        return;
      }
      final generated = Uri.parse(await _engine.generateTwoFactor());
      final parameters = {...generated.queryParameters, 'issuer': 'Localist'};
      final uri = generated
          .replace(path: '/Localist', queryParameters: parameters)
          .toString();
      final code = TextEditingController();
      String? error;
      bool verifying = false;
      if (!mounted) {
        code.dispose();
        return;
      }
      final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              _t(
                'فعال‌سازی احراز هویت دومرحله‌ای',
                'Enable two-factor authentication',
              ),
            ),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _t(
                        'کد را با برنامه Authenticator اسکن کنید و کد شش‌رقمی را وارد کنید.',
                        'Scan with your authenticator and enter the six-digit code.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    QrImageView(
                      data: uri,
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                    SelectableText(parameters['secret'] ?? ''),
                    const SizedBox(height: 12),
                    TextField(
                      controller: code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: _t('کد تأیید', 'Verification code'),
                        errorText: error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: verifying
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: Text(_t('لغو', 'Cancel')),
              ),
              FilledButton(
                onPressed: verifying
                    ? null
                    : () async {
                        update(() {
                          verifying = true;
                          error = null;
                        });
                        try {
                          if (await _engine.verifyTwoFactor(code.text.trim())) {
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } else if (dialogContext.mounted) {
                            update(() {
                              verifying = false;
                              error = _t(
                                'کد نادرست است',
                                'Invalid verification code',
                              );
                            });
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            update(() {
                              verifying = false;
                              error = '$e';
                            });
                          }
                        }
                      },
                child: Text(_t('تأیید و فعال‌سازی', 'Verify and enable')),
              ),
            ],
          ),
        ),
      );
      if (!mounted) {
        code.dispose();
        return;
      }
      await Navigator.of(context).push(route);
      await route.completed;
      code.dispose();
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (mounted) setState(() => _notice = '$e');
  }
}
