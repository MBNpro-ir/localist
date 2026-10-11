import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Server export format used by the upstream client: reversed base64url JSON.
class RemoteServerConfig {
  const RemoteServerConfig({
    this.idServer = '',
    this.relayServer = '',
    this.apiServer = '',
    this.key = '',
  });

  final String idServer;
  final String relayServer;
  final String apiServer;
  final String key;

  static const suppliedCode =
      '=0nI9kVNrd0U1EWM380U1NVQiN3QvBzb4NzTxpVNY5URXFnZtBnTyJUN1EnW04mI6ISeltmIsIiI6ISawFmIsICO0IjL4ATMuAzMuEDOiojI5FGblJnIsICO0IjL4ATMuAzMuEDOiojI0N3boJye';

  factory RemoteServerConfig.decode(String value) {
    if (value.length > 16384) {
      throw const FormatException('Server code is too long.');
    }
    dynamic json;
    try {
      json = jsonDecode(value.trim());
    } on FormatException {
      try {
        json = jsonDecode(
          utf8.decode(
            base64Url.decode(
              base64.normalize(value.trim().split('').reversed.join()),
            ),
          ),
        );
      } catch (_) {
        throw const FormatException('Invalid server configuration code.');
      }
    }
    if (json is! Map ||
        [
          'host',
          'relay',
          'api',
          'key',
        ].any((k) => json[k] != null && json[k] is! String)) {
      throw const FormatException('Invalid server configuration fields.');
    }
    final config = RemoteServerConfig(
      idServer: (json['host'] as String? ?? '').trim(),
      relayServer: (json['relay'] as String? ?? '').trim(),
      apiServer: (json['api'] as String? ?? '').trim(),
      key: (json['key'] as String? ?? '').trim(),
    );
    config.validate();
    return config;
  }

  void validate() {
    for (final value in [idServer, relayServer, apiServer, key]) {
      if (value.length > 2048 || value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        throw const FormatException('Invalid server configuration value.');
      }
    }
    for (final host in [idServer, relayServer]) {
      if (host.isNotEmpty &&
          (host.contains(RegExp(r'\s')) ||
              host.startsWith('-') ||
              host.contains('/'))) {
        throw const FormatException(
          'Enter a server hostname or IP, with an optional port.',
        );
      }
    }
    if (apiServer.isNotEmpty) {
      final uri = Uri.tryParse(apiServer);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw const FormatException('API server must be an HTTP or HTTPS URL.');
      }
    }
    if (key.isNotEmpty) {
      try {
        if (base64.decode(base64.normalize(key)).length != 32) {
          throw const FormatException();
        }
      } catch (_) {
        throw const FormatException('The public key must encode 32 bytes.');
      }
    }
  }

  String encode() => base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'host': idServer.trim(),
            'relay': relayServer.trim(),
            'api': apiServer.trim(),
            'key': key.trim(),
          }),
        ),
      )
      .split('')
      .reversed
      .join();

  Map<String, String> get engineOptions => {
    'custom-rendezvous-server': idServer,
    'relay-server': relayServer,
    'api-server': apiServer,
    'key': key,
  };
  bool get usesRelay =>
      [idServer, relayServer, apiServer, key].any((s) => s.isNotEmpty);
}

enum RemoteSettingsTab { general, security, network, display, printer }

enum RemoteOptionScope { server, local, display, native }

class RemoteSetting {
  const RemoteSetting(
    this.key,
    this.fa,
    this.en,
    this.tab,
    this.card,
    this.scope,
    this.defaultValue, {
    this.choices,
    this.boolean = true,
  });
  final String key, fa, en, card, defaultValue;
  final RemoteSettingsTab tab;
  final RemoteOptionScope scope;
  final bool boolean;

  /// Values are engine values; labels are kept human-readable in the UI.
  final Map<String, String>? choices;
}

const _g = RemoteSettingsTab.general;
const _s = RemoteSettingsTab.security;
const _n = RemoteSettingsTab.network;
const _d = RemoteSettingsTab.display;
const _p = RemoteSettingsTab.printer;
const _server = RemoteOptionScope.server;
const _local = RemoteOptionScope.local;
const _display = RemoteOptionScope.display;
const _native = RemoteOptionScope.native;

/// Keys/scopes are mapped from upstream desktop_setting_page.dart, consts.dart
/// and UserDefaultConfig. Defaults below are the user's supplied screenshots.
const remoteSettings = <RemoteSetting>[
  RemoteSetting(
    'stop-service',
    'سرویس میزبانی متوقف باشد',
    'Stop hosting service',
    _g,
    'Service',
    _server,
    'N',
  ),
  RemoteSetting(
    'lang',
    'زبان',
    'Language',
    _g,
    'Language',
    _local,
    '',
    boolean: false,
    choices: {'': 'Default', 'fa': 'فارسی', 'en': 'English'},
  ),
  RemoteSetting(
    'enable-hwcodec',
    'کدک سخت‌افزاری',
    'Enable hardware codec',
    _g,
    'Hardware codec',
    _server,
    'Y',
  ),
  RemoteSetting(
    'audio-input',
    'ورودی صدا',
    'Audio input device',
    _g,
    'Audio input device',
    _server,
    '',
    boolean: false,
    choices: {'': 'System sound'},
  ),
  RemoteSetting(
    'enable-confirm-closing-tabs',
    'تأیید پیش از بستن چند تب',
    'Confirm before closing multiple tabs',
    _g,
    'Other',
    _local,
    'Y',
  ),
  RemoteSetting(
    'allow-multi-edge-toolbar-dock',
    'چسبیدن نوار ابزار به لبه‌های پنجره',
    'Allow docking remote toolbar to any window edge',
    _g,
    'Other',
    _local,
    'N',
  ),
  RemoteSetting(
    'enable-abr',
    'نرخ بیت تطبیقی',
    'Adaptive bitrate',
    _g,
    'Other',
    _server,
    'Y',
  ),
  RemoteSetting(
    'allow-remove-wallpaper',
    'حذف کاغذدیواری هنگام اتصال ورودی',
    'Remove wallpaper during incoming sessions',
    _g,
    'Other',
    _server,
    'N',
  ),
  RemoteSetting(
    'enable-open-new-connections-in-tabs',
    'باز شدن اتصال در تب جدید',
    'Open connection in new tab',
    _g,
    'Other',
    _local,
    'Y',
  ),
  RemoteSetting(
    'enable-port-forward-mux',
    'استفاده از یک اتصال برای تونل‌ها',
    'Reuse one connection for port forwarding',
    _g,
    'Other',
    _local,
    'Y',
  ),
  RemoteSetting(
    'use-texture-render',
    'رندر با Texture',
    'Use texture rendering',
    _g,
    'Other',
    _local,
    'Y',
  ),
  RemoteSetting(
    'allow-d3d-render',
    'رندر با D3D',
    'Use D3D rendering',
    _g,
    'Other',
    _local,
    'Y',
  ),
  RemoteSetting(
    'enable-check-update',
    'بررسی آپدیت موتور هنگام اجرا',
    'Check for engine updates on startup',
    _g,
    'Other',
    _local,
    'Y',
  ),
  RemoteSetting(
    'allow-auto-update',
    'آپدیت خودکار موتور',
    'Auto update engine',
    _g,
    'Other',
    _server,
    'Y',
  ),
  RemoteSetting(
    'enable-directx-capture',
    'ضبط صفحه با DirectX',
    'Capture screen using DirectX',
    _g,
    'Other',
    _server,
    'Y',
  ),
  RemoteSetting(
    'enable-tcp-punch',
    'اتصال مستقیم TCP',
    'Enable TCP hole punching',
    _g,
    'Other',
    _local,
    'Y',
  ),
  RemoteSetting(
    'enable-udp-punch',
    'اتصال مستقیم UDP',
    'Enable UDP hole punching',
    _g,
    'Other',
    _local,
    'Y',
  ),
  RemoteSetting(
    'enable-ipv6-punch',
    'اتصال مستقیم IPv6',
    'Enable IPv6 P2P connection',
    _g,
    'Other',
    _local,
    'Y',
  ),
  RemoteSetting(
    'enable-webrtc',
    'اتصال مستقیم WebRTC',
    'Enable WebRTC P2P connection',
    _g,
    'Other',
    _local,
    'Y',
  ),
  RemoteSetting(
    'relay-fallback-delay',
    'تأخیر Relay (ثانیه)',
    'Relay fallback delay in seconds',
    _g,
    'Other',
    _local,
    '2.5',
    boolean: false,
  ),
  RemoteSetting(
    'allow-sync-clipboard-between-sessions',
    'همگام‌سازی کلیپ‌بورد جلسه‌ها',
    'Sync clipboard between sessions',
    _g,
    'Other',
    _local,
    'Y',
  ),
  RemoteSetting(
    'keep-awake-during-outgoing-sessions',
    'روشن ماندن صفحه هنگام اتصال خروجی',
    'Keep screen awake during outgoing sessions',
    _g,
    'Other',
    _local,
    'Y',
  ),
  RemoteSetting(
    'allow-ask-for-note',
    'پرسیدن یادداشت در پایان اتصال',
    'Ask for note at end of connection',
    _g,
    'Other',
    _local,
    'N',
  ),
  RemoteSetting(
    'allow-monitor-switch-main-toolbar',
    'دکمه تغییر مانیتور در نوار اصلی',
    'Show monitor switch button on the main toolbar',
    _g,
    'Other',
    _local,
    'N',
  ),
  RemoteSetting(
    'access-mode',
    'نوع دسترسی',
    'Access mode',
    _s,
    'Permissions',
    _server,
    '',
    boolean: false,
    choices: {'': 'Custom', 'full': 'Full access', 'view': 'Screen share'},
  ),
  RemoteSetting(
    'enable-keyboard',
    'صفحه‌کلید و ماوس',
    'Enable keyboard/mouse',
    _s,
    'Permissions',
    _server,
    'Y',
  ),
  RemoteSetting(
    'enable-remote-printer',
    'چاپگر از راه دور',
    'Enable remote printer',
    _s,
    'Permissions',
    _server,
    'Y',
  ),
  RemoteSetting(
    'enable-clipboard',
    'کلیپ‌بورد',
    'Enable clipboard',
    _s,
    'Permissions',
    _server,
    'Y',
  ),
  RemoteSetting(
    'enable-file-transfer',
    'انتقال فایل',
    'Enable file transfer',
    _s,
    'Permissions',
    _server,
    'Y',
  ),
  RemoteSetting(
    'enable-audio',
    'صدای دستگاه',
    'Enable audio',
    _s,
    'Permissions',
    _server,
    'N',
  ),
  RemoteSetting(
    'enable-camera',
    'دوربین',
    'Enable camera',
    _s,
    'Permissions',
    _server,
    'N',
  ),
  RemoteSetting(
    'enable-terminal',
    'ترمینال',
    'Enable terminal',
    _s,
    'Permissions',
    _server,
    'N',
  ),
  RemoteSetting(
    'enable-tunnel',
    'تونل TCP',
    'Enable TCP tunneling',
    _s,
    'Permissions',
    _server,
    'N',
  ),
  RemoteSetting(
    'enable-remote-restart',
    'راه‌اندازی مجدد از راه دور',
    'Enable remote restart',
    _s,
    'Permissions',
    _server,
    'N',
  ),
  RemoteSetting(
    'enable-record-session',
    'ضبط جلسه',
    'Enable recording session',
    _s,
    'Permissions',
    _server,
    'N',
  ),
  RemoteSetting(
    'enable-block-input',
    'مسدود کردن ورودی محلی',
    'Enable blocking user input',
    _s,
    'Permissions',
    _server,
    'N',
  ),
  RemoteSetting(
    'enable-privacy-mode',
    'حالت حریم خصوصی',
    'Enable privacy mode',
    _s,
    'Permissions',
    _server,
    'N',
  ),
  RemoteSetting(
    'allow-remote-config-modification',
    'تغییر تنظیمات از راه دور',
    'Enable remote configuration modification',
    _s,
    'Permissions',
    _server,
    'N',
  ),
  RemoteSetting(
    '2fa',
    'احراز هویت دو مرحله‌ای',
    'Enable two-factor authentication',
    _s,
    '2FA',
    _native,
    'N',
  ),
  RemoteSetting(
    'share-rdp',
    'اشتراک‌گذاری جلسه RDP',
    'Enable RDP session sharing',
    _s,
    'Security',
    _native,
    'Y',
  ),
  RemoteSetting(
    'enable-lan-discovery',
    'نمایش دستگاه در شبکه محلی',
    'Allow LAN discovery',
    _s,
    'Security',
    _server,
    'Y',
  ),
  RemoteSetting(
    'direct-server',
    'دسترسی مستقیم با IP',
    'Enable direct IP access',
    _s,
    'Security',
    _server,
    'N',
  ),
  RemoteSetting(
    'direct-access-port',
    'پورت دسترسی مستقیم',
    'Direct access port',
    _s,
    'Security',
    _server,
    '21118',
    boolean: false,
  ),
  RemoteSetting(
    'whitelist',
    'IPهای مجاز (با ویرگول)',
    'IP whitelist (comma separated)',
    _s,
    'Security',
    _server,
    '',
    boolean: false,
  ),
  RemoteSetting(
    'id-whitelist',
    'شناسه‌های مجاز (با ویرگول)',
    'ID whitelist (comma separated)',
    _s,
    'Security',
    _server,
    '',
    boolean: false,
  ),
  RemoteSetting(
    'allow-auto-disconnect',
    'قطع اتصال ورودی پس از بی‌کاری',
    'Automatically close incoming sessions on inactivity',
    _s,
    'Security',
    _server,
    'N',
  ),
  RemoteSetting(
    'auto-disconnect-timeout',
    'مهلت بی‌کاری (دقیقه)',
    'Inactivity timeout in minutes',
    _s,
    'Security',
    _server,
    '10',
    boolean: false,
  ),
  RemoteSetting(
    'keep-awake-during-incoming-sessions',
    'روشن ماندن صفحه هنگام اتصال ورودی',
    'Keep screen awake during incoming sessions',
    _s,
    'Security',
    _server,
    'Y',
  ),
  RemoteSetting(
    'allow-only-conn-window-open',
    'اتصال فقط هنگام باز بودن پنجره',
    'Only allow connections while the window is open',
    _s,
    'Security',
    _server,
    'N',
  ),
  RemoteSetting(
    'verification-method',
    'روش تأیید رمز',
    'Password verification',
    _s,
    'Password',
    _server,
    'use-temporary-password',
    boolean: false,
    choices: {
      'use-temporary-password': 'One-time password',
      'use-permanent-password': 'Permanent password',
      'use-both-passwords': 'Both passwords',
    },
  ),
  RemoteSetting(
    'temporary-password-length',
    'طول رمز یک‌بارمصرف',
    'One-time password length',
    _s,
    'Password',
    _server,
    '6',
    boolean: false,
    choices: {'6': '6', '8': '8', '10': '10'},
  ),
  RemoteSetting(
    'allow-numeric-one-time-password',
    'رمز یک‌بارمصرف فقط عددی',
    'Numeric one-time password',
    _s,
    'Password',
    _server,
    'N',
  ),
  RemoteSetting(
    'approve-mode',
    'تأیید اتصال ورودی',
    'Incoming connection approval',
    _s,
    'Password',
    _server,
    'password-click',
    boolean: false,
    choices: {
      'password': 'Password only',
      'click': 'Click to approve',
      'password-click': 'Password or click to approve',
    },
  ),
  RemoteSetting(
    'allow-websocket',
    'استفاده از WebSocket',
    'Use WebSocket',
    _n,
    'Network',
    _server,
    'N',
  ),
  RemoteSetting(
    'allow-insecure-tls-fallback',
    'اجازه جایگزین TLS غیرامن',
    'Allow insecure TLS fallback',
    _n,
    'Network',
    _server,
    'Y',
  ),
  RemoteSetting(
    'disable-udp',
    'غیرفعال کردن UDP',
    'Disable UDP',
    _n,
    'Network',
    _server,
    'N',
  ),
  RemoteSetting(
    'force-always-relay',
    'همیشه از Relay استفاده شود',
    'Always use relay',
    _n,
    'Network',
    _server,
    'N',
  ),
  RemoteSetting(
    'view_style',
    'اندازه تصویر',
    'Default view style',
    _d,
    'Default view style',
    _display,
    'adaptive',
    boolean: false,
    choices: {'original': 'Scale original', 'adaptive': 'Scale adaptive'},
  ),
  RemoteSetting(
    'scroll_style',
    'شیوه پیمایش',
    'Default scroll style',
    _d,
    'Default scroll style',
    _display,
    'scrollauto',
    boolean: false,
    choices: {
      'scrollauto': 'ScrollAuto',
      'scrollbar': 'Scrollbar',
      'scrolledge': 'ScrollEdge',
    },
  ),
  RemoteSetting(
    'image_quality',
    'کیفیت تصویر',
    'Default image quality',
    _d,
    'Default image quality',
    _display,
    'low',
    boolean: false,
    choices: {
      'best': 'Good image quality',
      'balanced': 'Balanced',
      'low': 'Optimize reaction time',
      'custom': 'Custom',
    },
  ),
  RemoteSetting(
    'codec-preference',
    'کدک تصویر',
    'Default codec',
    _d,
    'Default codec',
    _display,
    'auto',
    boolean: false,
    choices: {
      'auto': 'Auto',
      'vp8': 'VP8',
      'vp9': 'VP9',
      'av1': 'AV1',
      'h264': 'H264',
      'h265': 'H265',
    },
  ),
  RemoteSetting(
    'privacy-mode-impl-key',
    'شیوه حریم خصوصی',
    'Privacy mode',
    _d,
    'Privacy mode',
    _server,
    'privacy_mode_impl_mag',
    boolean: false,
    choices: {
      'privacy_mode_impl_mag': 'Mode 1',
      'privacy_mode_impl_virtual_display': 'Mode 2',
    },
  ),
  RemoteSetting(
    'view_only',
    'فقط نمایش',
    'View mode',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'show_monitors_toolbar',
    'نمایش مانیتورها در نوار ابزار',
    'Show monitors in toolbar',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'collapse_toolbar',
    'جمع کردن نوار ابزار',
    'Collapse toolbar',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'show_remote_cursor',
    'نمایش نشانگر دستگاه مقصد',
    'Show remote cursor',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'follow_remote_cursor',
    'دنبال کردن نشانگر دستگاه مقصد',
    'Follow remote cursor',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'follow_remote_window',
    'دنبال کردن پنجره فعال مقصد',
    'Follow remote window focus',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'zoom-cursor',
    'بزرگ‌نمایی نشانگر',
    'Zoom cursor',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'show_quality_monitor',
    'نمایش آمار کیفیت',
    'Show quality monitor',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'disable_audio',
    'بی‌صدا',
    'Mute',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'enable-file-copy-paste',
    'کپی و چسباندن فایل',
    'Enable file copy and paste',
    _d,
    'Other default options',
    _display,
    'Y',
  ),
  RemoteSetting(
    'disable_clipboard',
    'غیرفعال کردن کلیپ‌بورد',
    'Disable clipboard',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'lock_after_session_end',
    'قفل کردن پس از پایان جلسه',
    'Lock after session end',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'privacy_mode',
    'حریم خصوصی در جلسه',
    'Privacy mode',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'i444',
    'رنگ واقعی 4:4:4',
    'True color (4:4:4)',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'reverse_mouse_wheel',
    'معکوس کردن چرخ ماوس',
    'Reverse mouse wheel',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'swap-left-right-mouse',
    'جابه‌جایی دکمه‌های ماوس',
    'Swap left-right mouse button',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'displays_as_individual_windows',
    'هر نمایشگر در پنجره جدا',
    'Show displays as individual windows',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'use_all_my_displays_for_the_remote_session',
    'استفاده از تمام نمایشگرهای من',
    'Use all my displays for the remote session',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'terminal-persistent',
    'حفظ ترمینال پس از قطع اتصال',
    'Keep terminal sessions on disconnect',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'allow-terminal-clipboard-write',
    'کپی از ترمینال به کلیپ‌بورد',
    'Allow terminal apps to copy to clipboard',
    _d,
    'Other default options',
    _display,
    'N',
  ),
  RemoteSetting(
    'printer-incomming-job-action',
    'کارهای چاپ ورودی',
    'Incoming print jobs',
    _p,
    'Incoming print jobs',
    _local,
    '',
    boolean: false,
    choices: {
      'dismiss': 'Dismiss',
      '': 'Use the default printer',
      'selected': 'Use the selected printer',
    },
  ),
  RemoteSetting(
    'printer-selected-name',
    'نام چاپگر انتخاب‌شده',
    'Selected printer name',
    _p,
    'Incoming print jobs',
    _local,
    '',
    boolean: false,
  ),
  RemoteSetting(
    'allow-printer-auto-print',
    'چاپ خودکار با چاپگر انتخاب‌شده',
    'Print automatically using the selected printer',
    _p,
    'Incoming print jobs',
    _local,
    'N',
  ),
];

class RemoteControlProfile {
  RemoteControlProfile({
    RemoteServerConfig? server,
    Map<String, String>? values,
  }) : server =
           server ?? RemoteServerConfig.decode(RemoteServerConfig.suppliedCode),
       values = {
         for (final option in remoteSettings) option.key: option.defaultValue,
         ...?values,
       };

  RemoteServerConfig server;
  final Map<String, String> values;
  static const _key = 'remote.control.profile.v1';

  static Future<RemoteControlProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_key);
    if (raw == null) return RemoteControlProfile();
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final values = Map<String, String>.from(data['values'] as Map);
      // 6.0.0 shipped password-only approval, hiding Accept in the incoming
      // window. Upgrade once; later explicit password-only choices are kept.
      if ((data['schema'] as int? ?? 1) < 2 &&
          values['approve-mode'] == 'password') {
        values['approve-mode'] = 'password-click';
      }
      return RemoteControlProfile(
        server: RemoteServerConfig.decode(data['server'] as String),
        values: values,
      );
    } catch (_) {
      return RemoteControlProfile();
    }
  }

  Future<void> save() async =>
      (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode({'schema': 2, 'server': server.encode(), 'values': values}),
      );

  Map<String, String> get serverOptions => {
    for (final option in remoteSettings)
      if (option.scope == RemoteOptionScope.server)
        option.key: values[option.key]!,
    ...server.engineOptions,
  };
}

/// Upstream display toggles use an empty value for off (except file copying).
/// Writing "N" to presence-based session options enables them accidentally.
String remoteDisplayValue(RemoteSetting setting, String value) =>
    setting.boolean && setting.key != 'enable-file-copy-paste' && value == 'N'
    ? ''
    : value;
