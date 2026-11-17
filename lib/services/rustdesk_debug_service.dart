import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'feature_activity_service.dart';
import 'feature_permission_service.dart';
import 'log_service.dart';
import '../models/remote_control_settings.dart';
import '../remote/embedded_remote_app.dart';
import '../remote/remote_native_api.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/common.dart' as remote;

/// Remote-control bridge. The upstream engine keeps ownership of its session
/// process and IPC; Localist provides discovery, settings and controls.
class RustDeskDebugService extends ChangeNotifier {
  final LogService _logs = LogService.instance;
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
  bool _listeningForInput = false;
  void _inputPermissionChanged() {
    final enabled = remote.gFFI.serverModel.inputOk;
    if (inputEnabled != enabled && !_disposed) {
      inputEnabled = enabled;
      _logs.debug('Remote input permission changed enabled=$enabled');
      _notify();
    }
  }

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
    _logs.debug(
      'Remote control service disposing sessionActive=$sessionActive hosting=$hosting',
    );
    _disposed = true;
    if (_listeningForInput) {
      remote.gFFI.serverModel.removeListener(_inputPermissionChanged);
    }
    _refreshTimer?.cancel();
    FeatureActivityService.instance.setActive(
      this,
      LocalistFeature.remoteControl,
      false,
    );
    super.dispose();
  }

  Future<void> initialize() async {
    _logs.debug(
      'Remote control initialization started platform=${Platform.operatingSystem}',
    );
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
        _logs.debug('Remote control bundled engine detected and registered');
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
    _logs.debug(
      'Remote control initialization finished ready=$ready online=$online engineAvailable=$engineAvailable',
    );
  }

  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() {
    _refreshing = null;
  });

  Future<void> _refresh() async {
    if (_disposed) return;
    final wasReady = ready;
    final wasOnline = online;
    final wasActive = sessionActive;
    final wasHosting = hosting;
    final previousConnectionStatus = connectionStatus;
    profile = await RemoteControlProfile.load();
    options.clear();
    localPassword = '';
    if (Platform.isAndroid) {
      try {
        await LocalistRemoteRuntime.ensureStarted();
        if (!_listeningForInput) {
          _listeningForInput = true;
          remote.gFFI.serverModel.addListener(_inputPermissionChanged);
        }
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
        _logs.debug(
          'Remote Android state refresh failed type=${exception.runtimeType}',
        );
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
            await api.mainGetCommon(key: '