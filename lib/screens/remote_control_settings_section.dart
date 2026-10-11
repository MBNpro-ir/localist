import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/remote_control_settings.dart';
import '../services/rustdesk_debug_service.dart';

class RemoteControlSettingsSection extends StatefulWidget {
  const RemoteControlSettingsSection({super.key});
  @override
  State<RemoteControlSettingsSection> createState() =>
      _RemoteControlSettingsSectionState();
}

class _RemoteControlSettingsSectionState
    extends State<RemoteControlSettingsSection>
    with WidgetsBindingObserver {
  final _engine = RustDeskDebugService();
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
    _engine.dispose();
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

  String _t(String fa, String en) => context.l10n.isPersian ? fa : en;
  String _tabName(RemoteSettingsTab tab) => switch (tab) {
    RemoteSettingsTab.general => _t('عمومی', 'General'),
    RemoteSettingsTab.security => _t('امنیت', 'Security'),
    RemoteSettingsTab.network => _t('شبکه', 'Network'),
    RemoteSettingsTab.display => _t('نمایش', 'Display'),
    RemoteSettingsTab.printer => _t('چاپگر', 'Printer'),
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
                    width: 180,
                    child: ListView(
                      children: [
                        for (final tab in RemoteSettingsTab.values)
                          ListTile(
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
          final content = ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              if (_notice.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_notice),
                ),
              if (_tab == RemoteSettingsTab.network) _serverCard(),
              for (final card
                  in remoteSettings
                      .where((s) => s.tab == _tab)
                      .map((s) => s.card)
                      .toSet())
                _card(_cardName(card), [
                  for (final setting in remoteSettings.where(
                    (s) => s.tab == _tab && s.card == card,
                  ))
                    _setting(setting),
                  if (card == 'Password') _passwordControls(),
                ]),
            ],
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
    margin: const EdgeInsets.only(bottom: 16),
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
    final value = _engine.profile.values[setting.key] ?? setting.defaultValue;
    final scope = _scopeNotice(setting);
    final disabled = _engine.busy;
    final accessMode = _engine.profile.values['access-mode'] ?? '';
    final permissionPreset =
        setting.card == 'Permissions' &&
        setting.boolean &&
        accessMode.isNotEmpty;
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
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis),
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
          decoration: InputDecoration(labelText: entry.key),
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
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        OutlinedButton.icon(
          onPressed: () => unawaited(_changePermanentPassword()),
          icon: const Icon(Icons.password),
          label: Text(_t('تنظیم رمز دائمی', 'Set permanent password')),
        ),
        OutlinedButton.icon(
          onPressed: () async {
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
      ],
    ),
  );

  Future<void> _changePermanentPassword() async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    String? error;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
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
                  decoration: InputDecoration(
                    labelText: _t(
                      'رمز جدید (حداقل ۶ کاراکتر)',
                      'New password (at least 6 characters)',
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
                      if (password.text.length < 6 ||
                          password.text != confirmation.text) {
                        update(
                          () => error = _t(
                            'رمز باید حداقل ۶ کاراکتر و با تکرار برابر باشد',
                            'Use at least 6 characters and matching passwords',
                          ),
                        );
                        return;
                      }
                      update(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await _engine.setPermanentPassword(password.text);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
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
    );
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
      await showDialog<void>(
        context: context,
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
      code.dispose();
    } catch (e) {
      _showError(e);
    }
  }

  void _showError(Object e) {
    if (mounted) setState(() => _notice = '$e');
  }
}
