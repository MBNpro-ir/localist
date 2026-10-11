import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'native_bridge_service.dart';
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
  bool hosting = false;
  bool inputEnabled = false;
  bool twoFactorEnabled = false;
  bool rdpShared = false;
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
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    profile = await RemoteControlProfile.load();
    await profile.save();
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
    _refreshTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(refresh());
    });
  }

  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() {
    _refreshing = null;
  });

  Future<void> _refresh() async {
    if (_disposed) return;
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
        online = (state['status_num'] as num? ?? 0) > 0;
        hosting = remote.gFFI.serverModel.isStart;
        inputEnabled = remote.gFFI.serverModel.inputOk;
        options.addAll(
          Map<String, String>.from(
            jsonDecode(bind.mainGetOptionsSync()) as Map,
          ),
        );
        twoFactorEnabled = bind.mainHasValid2FaSync();
        if (options['approve-mode'] == 'click' ||
            options['verification-method'] == 'use-permanent-password') {
          localPassword = '';
        }
        error = '';
      } catch (exception) {
        ready = false;
        error = '$exception';
      }
    }
    if (Platform.isWindows && File(enginePath).existsSync()) {
      try {
        error = '';
        await LocalistRemoteRuntime.ensureStarted();
        final status = await LocalistRemoteRuntime.desktopStatus();
        ready = status?['ready'] == true;
        online = (status?['statusNum'] as num? ?? 0) > 0;
        hosting = profile.values['stop-service'] != 'Y';
        final api = await RemoteNativeApi.get();
        localId = await api.mainGetMyId();
        localPassword = await api.mainGetTemporaryPassword();
        twoFactorEnabled = api.mainHasValid2FaSync();
        rdpShared = api.mainIsShareRdp();
        options.addAll(
          Map<String, String>.from(jsonDecode(api.mainGetOptionsSync()) as Map),
        );
        if (options['approve-mode'] == 'click' ||
            options['verification-method'] == 'use-permanent-password') {
          localPassword = '';
        }
      } catch (exception) {
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
    profile.values[key] = value;
    await profile.save();
    if (Platform.isAndroid) await applyNativeRemoteProfile();
    if (key == 'share-rdp' && Platform.isWindows) {
      final api = await RemoteNativeApi.get();
      if (api.mainIsShareRdp() != (value == 'Y')) {
        await api.mainSetShareRdp(enable: value == 'Y');
      }
    }
    applyStatus = 'Profile saved in Localist.';
    _notify();
  }

  Future<void> saveServerConfig(RemoteServerConfig config) async {
    config.validate();
    profile.server = config;
    await profile.save();
    if (Platform.isAndroid) await applyNativeRemoteProfile();
    applyStatus = 'Server configuration saved in Localist.';
    _notify();
  }

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
    if (Platform.isWindows) {
      if (!File(enginePath).existsSync()) {
        throw const FileSystemException(
          'The bundled remote-control engine is unavailable.',
        );
      }
      await LocalistRemoteRuntime.ensureStarted();
      await Process.start(enginePath, [
        '--$mode',
        target.trim(),
        if (relay) '--relay',
        if (password.isNotEmpty) ...['--password', password],
      ], mode: ProcessStartMode.detached);
    } else if (Platform.isAndroid) {
      if (mode == 'rdp' || mode == 'port-forward') {
        throw UnsupportedError('This mode requires the desktop client.');
      }
      await _native.invokeMethod<bool>(
        'open',
        jsonEncode({
          'target': target.trim(),
          'mode': mode,
          'relay': relay,
          if (password.isNotEmpty) 'password': password,
        }),
      );
    }
    {
      recent = [
        target.trim(),
        ...recent.where((id) => id != target.trim()),
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
      await remote.gFFI.serverModel.startService();
    } else {
      await remote.gFFI.serverModel.stopService();
    }
    await refresh();
  }

  Future<void> openInputPermission() async {
    await _native.invokeMethod<bool>('inputSettings');
  }

  Future<void> setPermanentPassword(String password) async {
    final api = await RemoteNativeApi.get();
    if (!await api.mainSetPermanentPasswordWithResult(password: password)) {
      throw StateError('The engine could not save the permanent password.');
    }
  }

  Future<void> regeneratePassword() async {
    await (await RemoteNativeApi.get()).mainUpdateTemporaryPassword();
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
    if (!permissions.containsKey(key) || !Platform.isWindows || busy) {
      return;
    }
    busy = true;
    error = '';
    _notify();
    try {
      final option = value ? 'Y' : 'N';
      if (!await NativeBridgeService.instance.applyRustDeskOption(
        enginePath,
        key,
        option,
      )) {
        throw const FileSystemException(
          'Windows could not launch the remote settings command.',
        );
      }
      for (var attempt = 0; attempt < 10 && !_disposed; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await refresh();
        if (options[key] == option) return;
      }
      error =
          'Setting not confirmed. The installed service and administrator approval are required.';
    } finally {
      busy = false;
      _notify();
    }
  }
}
