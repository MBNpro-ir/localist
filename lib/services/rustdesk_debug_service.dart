import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'feature_activity_service.dart';
import 'feature_permission_service.dart';
import '../models/remote_control_settings.dart';
import '../remote/embedded_remote_app.dart';
import '../remote/remote_native_api.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/common.dart' as remote;

/// Remote-control bridge. The upstream engine keeps ownership of its session
/// process and IPC; Localist provides discovery, settings and controls.
class RustDeskDebugService extends ChangeNotifier {
  String enginePath = '';
  String localId = '';
  String localPassword = '';
  Future<void>? _refreshing;
  String error = '';
  final Map<String, String> options = {};
  List<String> recent = [];
  bool busy = false;
  bool ready = false;
  bool online = false;
  int connectionStatus = 0;
  bool hasPermanentPassword = false;
  String get serverLabel => profile.server.idServer.isEmpty
      ? 'Public servers'
      : profile.server.idServer;
  bool hosting = false;
  bool sessionActive = false;
  bool inputEnabled = false;
  bool twoFactorEnabled = false;
  bool rdpShared = false;
  bool hardwareCodecSupported = false;
  bool installedService = false;
  Timer? _refreshTimer;
  RemoteControlProfile profile = RemoteControlProfile();
  String applyStatus = '';
  bool get engineAvailable =>
      Platform.isAndroid ||
      (Platform.isWindows && File(enginePath).existsSync());
  static const _native = MethodChannel('localist/remote');
  bool _disposed = false;
  static const modes = [
    'connect',
    'file-transfer',
    'view-camera',
    'terminal',
    'port-forward',
    'rdp',
  ];
  static const permissions = {
    'direct-server': 'Direct LAN access',
    'enable-lan-discovery': 'LAN discovery',
    'enable-keyboard': 'Keyboard and mouse',
    'enable-clipboard': 'Clipboard',
    'enable-file-transfer': 'File transfer',
    'enable-audio': 'System audio',
    'enable-camera': 'Camera',
    'enable-terminal': 'Terminal',
    'enable-tunnel': 'TCP tunneling',
    'enable-remote-restart': 'Remote restart',
    'enable-record-session': 'Session recording',
    'enable-block-input': 'Block local input',
    'enable-privacy-mode': 'Privacy mode',
    'enable-remote-printer': 'Remote printer',
    'allow-remote-config-modification': 'Remote settings modification',
    'enable-hwcodec': 'Hardware codec',
    'force-always-relay': 'Always use relay',
    'allow-always-software-render': 'Software rendering',
  };
  bool enabled(String key) =>
      key.startsWith('enable-') ? options[key] != 'N' : options[key] == 'Y';
  void _notify() {
    if (!_disposed) {
      FeatureActivityService.instance.setActive(
        this,
        LocalistFeature.remoteControl,
        sessionActive || (Platform.isAndroid && hosting),
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    FeatureActivityService.instance.setActive(
      this,
      LocalistFeature.remoteControl,
      false,
    );
    super.dispose();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await _updateProfile((_) {});
    final storedEnginePath = prefs.getString('remote.enginePath') ?? '';
    recent = prefs.getStringList('remote.recent') ?? [];
    if (Platform.isAndroid) localId = prefs.getString('remote.localId') ?? '';
    if (Platform.isWindows) {
      // All sessions use the engine packaged with this Localist build.
      final bundledEngine =
          '${File(Platform.resolvedExecutable).parent.path}\\LocalistRemote.exe';
      enginePath = File(bundledEngine).existsSync() ? bundledEngine : '';
      if (enginePath.isNotEmpty && enginePath != storedEnginePath) {
        await prefs.setString('remote.enginePath', enginePath);
      }
    }
    await refresh();
    if (ready &&
        !hasPermanentPassword &&
        profile.values['verification-method'] != 'use-temporary-password') {
      await saveProfileValue('verification-method', 'use-temporary-password');
      await refresh();
    }
    _refreshTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(refresh());
    });
  }

  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() {
    _refreshing = null;
  });

  Future<void> _refresh() async {
    if (_disposed) return;
    profile = await RemoteControlProfile.load();
    options.clear();
    localPassword = '';
    if (Platform.isAndroid) {
      try {
        await LocalistRemoteRuntime.ensureStarted();
        await applyNativeRemoteProfile();
        await remote.gFFI.invokeMethod('check_service');
        localId = await bind.mainGetMyId();
        localPassword = await bind.mainGetTemporaryPassword();
        final state = jsonDecode(await bind.mainGetConnectStatus()) as Map;
        ready = true;
        connectionStatus = (state['status_num'] as num? ?? 0).toInt();
        online = connectionStatus > 0;
        hasPermanentPassword =
            await bind.mainGetCommon(key: 'permanent-password-set') == 'true';
        hosting = remote.gFFI.serverModel.mediaOk;
        inputEnabled = remote.gFFI.serverModel.inputOk;
        options.addAll(
          Map<String, String>.from(
            jsonDecode(bind.mainGetOptionsSync()) as Map,
          ),
        );
        twoFactorEnabled = bind.mainHasValid2FaSync();
        hardwareCodecSupported = bind.mainHasHwcodec() || bind.mainHasVram();
        if (options['approve-mode'] == 'click' ||
            options['verification-method'] == 'use-permanent-password') {
          localPassword = '';
        }
        error = '';
      } catch (exception) {
        ready = false;
        online = false;
        error = '$exception';
      }
    }
    if (Platform.isWindows && File(enginePath).existsSync()) {
      try {
        error = '';
        await LocalistRemoteRuntime.ensureStarted();
        final status = await LocalistRemoteRuntime.desktopStatus();
        ready = status?['ready'] == true;
        sessionActive = (status?['activeSessions'] as num? ?? 0) > 0;
        connectionStatus = (status?['statusNum'] as num? ?? 0).toInt();
        online = ready && connectionStatus > 0;
        hosting = profile.values['stop-service'] != 'Y';
        final api = await RemoteNativeApi.get();
        hasPermanentPassword =
            await api.mainGetCommon(key: 'permanent-password-set') == 'true';
        final credentials = await LocalistRemoteRuntime.desktopCommand({
          'command': 'credentials',
        });
        localId = credentials['id'] as String? ?? '';
        localPassword = credentials['password'] as String? ?? '';
        twoFactorEnabled = api.mainHasValid2FaSync();
        rdpShared = api.mainIsShareRdp();
        hardwareCodecSupported = api.mainHasHwcodec() || api.mainHasVram();
        installedService = api.mainIsInstalled();
        options.addAll(
          Map<String, String>.from(jsonDecode(api.mainGetOptionsSync()) as Map),
        );
        if (options['approve-mode'] == 'click' ||
            options['verification-method'] == 'use-permanent-password') {
          localPassword = '';
        }
      } catch (exception) {
        ready = false;
        online = false;
        error = '$exception';
      }
    }
    _notify();
  }

  Future<void> saveProfileValue(String key, String value) async {
    final option = remoteSettings.where((s) => s.key == key).firstOrNull;
    if (option == null ||
        value.length > 2048 ||
        value.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const FormatException('Invalid setting.');
    }
    if (option.boolean && value != 'Y' && value != 'N') {
      throw const FormatException('Invalid switch value.');
    }
    if (option.choices != null && !option.choices!.containsKey(value)) {
      throw const FormatException('Invalid setting value.');
    }
    if (key == 'direct-access-port' &&
        (int.tryParse(value) == null ||
            int.parse(value) < 1 ||
            int.parse(value) > 65535)) {
      throw const FormatException('Port must be between 1 and 65535.');
    }
    if (key == 'relay-fallback-delay' &&
        (double.tryParse(value) == null ||
            !double.parse(value).isFinite ||
            double.parse(value) < 0 ||
            double.parse(value) > 30)) {
      throw const FormatException(
        'Relay delay must be between 0 and 30 seconds.',
      );
    }
    if (key == 'auto-disconnect-timeout' &&
        (int.tryParse(value) == null ||
            int.parse(value) < 1 ||
            int.parse(value) > 1440)) {
      throw const FormatException(
        'Inactivity timeout must be between 1 and 1440 minutes.',
      );
    }
    await _updateProfile((latest) => latest.values[key] = value);
    await _applyProfileNow();
    if (key == 'share-rdp' && Platform.isWindows) {
      final api = await RemoteNativeApi.get();
      if (api.mainIsShareRdp() != (value == 'Y')) {
        await api.mainSetShareRdp(enable: value == 'Y');
      }
      rdpShared = api.mainIsShareRdp();
      if (rdpShared != (value == 'Y')) {
        throw StateError(
          'Windows could not apply RDP sharing. Administrator approval may be required.',
        );
      }
    }
    applyStatus = 'Profile saved in Localist.';
    _notify();
  }

  Future<void> saveServerConfig(RemoteServerConfig config) async {
    config.validate();
    await _updateProfile((latest) => latest.server = config);
    await _applyProfileNow();
    applyStatus = 'Server configuration saved in Localist.';
    _notify();
  }

  /// Apply a persisted profile to the engine before reporting the setting as
  /// saved. Android can update the embedded engine directly. Windows keeps a
  /// single hidden host process, so send it an authenticated sync command; the
  /// periodic heartbeat remains only as a recovery path for edits made while
  /// the primary window is closed.
  Future<void> _applyProfileNow() async {
    if (Platform.isAndroid) {
      await applyNativeRemoteProfile();
      return;
    }
    if (Platform.isWindows && File(enginePath).existsSync()) {
      await LocalistRemoteRuntime.ensureStarted();
      await LocalistRemoteRuntime.desktopCommand({'command': 'syncProfile'});
    }
  }

  static Future<void> _writes = Future<void>.value();
  Future<void> _updateProfile(void Function(RemoteControlProfile) edit) =>
      _writes = _writes.catchError((Object _) {}).then((_) async {
        final latest = await RemoteControlProfile.load();
        edit(latest);
        await latest.save();
        profile = latest;
      });

  Future<void> launch({
    String? target,
    String mode = 'connect',
    bool relay = false,
    String password = '',
  }) async {
    if (target == null ||
        (target.trim().isEmpty ||
            target.length > 200 ||
            target.startsWith('-') ||
            target.contains(RegExp(r'[\r\n\x00]')))) {
      throw const FormatException('Enter a remote ID or local IP address.');
    }
    if (!modes.contains(mode)) {
      throw const FormatException('Unsupported connection mode');
    }
    await LocalistRemoteRuntime.ensureStarted();
    profile = await RemoteControlProfile.load();
    final api = await RemoteNativeApi.get();
    // Sync the chosen server before session creation; never route an ID via
    // stale public-server options while the hidden host applies a new profile.
    await api.mainSetOptions(
      json: jsonEncode({
        ...Map<String, String>.from(
          jsonDecode(api.mainGetOptionsSync()) as Map,
        ),
        ...profile.serverOptions,
        'allow-auto-update': 'N',
      }),
    );
    final targetId = normalizeRemoteTarget(target);
    // Repair off values written by Localist 6.0.0 to existing peer configs.
    for (final key in ['swap-left-right-mouse', 'i444', 'collapse_toolbar']) {
      if (api.mainGetPeerOptionSync(id: targetId, key: key) == 'N') {
        await api.mainSetPeerOption(id: targetId, key: key, value: '');
      }
    }
    if (Platform.isWindows) {
      if (!File(enginePath).existsSync()) {
        throw const FileSystemException(
          'The bundled remote-control engine is unavailable.',
        );
      }
      await LocalistRemoteRuntime.ensureStarted();
      await LocalistRemoteRuntime.desktopCommand({
        'command': 'openSession',
        'session': {
          'mode': mode,
          'target': targetId,
          'relay': relay || profile.server.usesRelay,
          'password': password,
        },
      });
    } else if (Platform.isAndroid) {
      if (mode == 'rdp' || mode == 'port-forward') {
        throw UnsupportedError('This mode requires the desktop client.');
      }
      await _native.invokeMethod<bool>(
        'open',
        jsonEncode({
          'target': targetId,
          'mode': mode,
          'relay': relay,
          if (password.isNotEmpty) 'password': password,
        }),
      );
    }
    {
      recent = [
        targetId,
        ...recent.where((id) => id != targetId),
      ].take(20).toList();
      await (await SharedPreferences.getInstance()).setStringList(
        'remote.recent',
        recent,
      );
      _notify();
    }
  }

  Future<void> setAndroidHosting(bool enabled) async {
    if (!Platform.isAndroid) return;
    await LocalistRemoteRuntime.ensureStarted();
    if (enabled) {
      if (!await FeaturePermissionService.instance.ensure([
        FeatureAccess.notifications,
        FeatureAccess.screenCapture,
      ])) {
        return;
      }
      await remote.gFFI.serverModel.startService();
    } else {
      remote.gFFI.serverModel.closeAll();
      await remote.gFFI.invokeMethod('release_capture');
    }
    await refresh();
  }

  Future<void> openInputPermission() async {
    if (Platform.isAndroid) {
      await FeaturePermissionService.instance.ensure([
        FeatureAccess.remoteInput,
      ]);
    }
  }

  Future<void> disableInputPermission() async {
    if (Platform.isAndroid) await remote.gFFI.invokeMethod('stop_input');
  }

  Future<void> setPermanentPassword(String password) async {
    password = password.trim();
    final passwordError = permanentPasswordValidationError(password);
    if (passwordError != null) {
      throw FormatException(passwordError);
    }
    final api = await RemoteNativeApi.get();
    if (!await api.mainSetPermanentPasswordWithResult(password: password)) {
      throw StateError('The engine could not save the permanent password.');
    }
    // Keep the password and the verification policy as one transaction from
    // the user's point of view. Saving the password alone is insufficient:
    // the remote engine will continue to ask for a one-time password until
    // verification-method is applied to the same native host.
    await _updateProfile((latest) {
      latest.values.addAll(remotePasswordPolicy(latest.values, password));
    });
    await _applyProfileNow();
    await refresh();
  }

  Future<List<String>> printerNames() async {
    if (!Platform.isWindows) return [];
    final raw = (await RemoteNativeApi.get()).mainGetPrinterNames();
    final names =
        (jsonDecode(raw.isEmpty ? '[]' : raw) as List)
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return names;
  }

  Future<List<String>> audioInputNames() async =>
      (await (await RemoteNativeApi.get()).mainGetSoundInputs())
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

  Future<void> regeneratePassword() async {
    await _applyProfileNow();
    if (Platform.isWindows && File(enginePath).existsSync()) {
      await LocalistRemoteRuntime.desktopCommand({
        'command': 'regeneratePassword',
      });
    } else {
      await (await RemoteNativeApi.get()).mainUpdateTemporaryPassword();
    }
    await refresh();
  }

  Future<Map<String, dynamic>> savedPeer(String id) async {
    final api = await RemoteNativeApi.get();
    final data = jsonDecode(api.mainGetPeerSync(id: id)) as Map;
    return Map<String, dynamic>.from(data['info'] as Map? ?? {});
  }

  Future<String> generateTwoFactor() async =>
      (await RemoteNativeApi.get()).mainGenerate2Fa();
  Future<bool> verifyTwoFactor(String code) async {
    final verified = await (await RemoteNativeApi.get()).mainVerify2Fa(
      code: code,
    );
    await refresh();
    return verified;
  }

  Future<void> disableTwoFactor() async {
    final api = await RemoteNativeApi.get();
    await api.mainSetOption(key: '2fa', value: '');
    await api.mainClearTrustedDevices();
    await refresh();
  }

  Future<void> setOption(String key, bool value) async {
    if (!permissions.containsKey(key) || busy) {
      return;
    }
    busy = true;
    error = '';
    _notify();
    try {
      await saveProfileValue(key, value ? 'Y' : 'N');
      await refresh();
    } finally {
      busy = false;
      _notify();
    }
  }
}

/// Setting a password must also enable password authentication. In manual-only
/// approval mode even the correct password is intentionally ignored upstream.
Map<String, String> remotePasswordPolicy(
  Map<String, String> current,
  String password,
) => {
  'verification-method': password.isEmpty
      ? 'use-temporary-password'
      : current['verification-method'] == 'use-permanent-password'
      ? 'use-permanent-password'
      : 'use-both-passwords',
  if (password.isNotEmpty && current['approve-mode'] == 'click')
    'approve-mode': 'password-click',
};

/// Keep Localist validation aligned with RustDesk's desktop password dialog.
/// The native engine accepts an empty value to remove the password, otherwise
/// it limits the encrypted storage to 128 characters. RustDesk's UI also
/// requires a digit, upper-case letter and lower-case letter before sending
/// the request to the daemon.
String? permanentPasswordValidationError(String password) {
  if (password.isEmpty) return null;
  if (password.length > 128 || password.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    return 'Permanent password must be 128 characters or fewer and contain no control characters.';
  }
  if (password.length < 8) {
    return 'Permanent password must contain at least 8 characters.';
  }
  if (!RegExp(r'[0-9]').hasMatch(password)) {
    return 'Permanent password must contain a digit.';
  }
  final hasUppercase = password.runes.any((rune) {
    final character = String.fromCharCode(rune);
    return character.toUpperCase() == character &&
        character.toLowerCase() != character;
  });
  if (!hasUppercase) {
    return 'Permanent password must contain an uppercase letter.';
  }
  final hasLowercase = password.runes.any((rune) {
    final character = String.fromCharCode(rune);
    return character.toLowerCase() == character &&
        character.toUpperCase() != character;
  });
  if (!hasLowercase) {
    return 'Permanent password must contain a lowercase letter.';
  }
  return null;
}

String normalizeRemoteTarget(String target) {
  final trimmed = target.trim();
  return RegExp(r'^[\d\s]+$').hasMatch(trimmed)
      ? trimmed.replaceAll(RegExp(r'\s'), '')
      : trimmed;
}
