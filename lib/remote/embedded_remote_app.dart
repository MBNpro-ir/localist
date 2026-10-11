import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/main.dart' as remote;
import 'package:flutter_hbb/common.dart' as engine;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/common/widgets/overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/remote_control_settings.dart';
import '../services/log_service.dart';
import 'remote_theme.dart';

class LocalistRemoteRuntime {
  static Future<void>? _starting;
  static Process? _hostProcess;

  static File get statusFile => File(
    '${Platform.environment['APPDATA']}\\PRS\\Localist\\remote-status.json',
  );

  static Future<Map<String, dynamic>?> desktopStatus() async {
    try {
      final data =
          jsonDecode(await statusFile.readAsString()) as Map<String, dynamic>;
      if (DateTime.now().millisecondsSinceEpoch - (data['updatedMs'] as int) >
          5000) {
        return null;
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  static Future<void> ensureStarted() =>
      _starting ??= _start().catchError((Object error) {
        _starting = null;
        throw error;
      });

  static Future<void> _start() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remote.localPassword');
    if (Platform.isWindows) {
      if ((await desktopStatus())?['ready'] == true) return;
      final executable = File(
        '${File(Platform.resolvedExecutable).parent.path}\\LocalistRemote.exe',
      );
      if (!executable.existsSync()) {
        throw StateError('The bundled remote-control engine is unavailable.');
      }
      final process = await Process.start(executable.path, [
        '--localist-host',
      ], workingDirectory: executable.parent.path);
      _hostProcess = process;
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      unawaited(
        process.exitCode.then((_) {
          if (identical(_hostProcess, process)) {
            _hostProcess = null;
            _starting = null;
          }
        }),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline)) {
        if ((await desktopStatus())?['ready'] == true) return;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      throw TimeoutException('The remote-control host did not become ready.');
    } else if (Platform.isAndroid) {
      remote.localistThemeBootstrap = RemoteThemeSync.start;
      remote.kBootArgs = [];
      await remote.initEnv(kAppTypeMain);
      androidChannelInit();
      platformFFI.syncAndroidServiceAppDirConfigPath();
      await applyNativeRemoteProfile();
      // Capture permission is requested only by Localist's hosting button.
      await engine.gFFI.invokeMethod('check_service');
    }
  }

  static Future<void> stop() async {
    _hostProcess?.kill();
    _hostProcess = null;
    _starting = null;
  }
}

Future<void> runEmbeddedRemote() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('localist/remote');
  final launch =
      jsonDecode(await channel.invokeMethod<String>('launchOptions') ?? '{}')
          as Map;
  await LocalistRemoteRuntime.ensureStarted();
  draggablePositions.load();
  runApp(remote.App(home: const Scaffold(body: SizedBox.shrink())));
  final target = launch['target'];
  if (target is String && target.isNotEmpty) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = engine.globalKey.currentContext;
      if (context != null) {
        engine.connect(
          context,
          target,
          isFileTransfer: launch['mode'] == 'file-transfer',
          isViewCamera: launch['mode'] == 'view-camera',
          isTerminal: launch['mode'] == 'terminal',
          password: launch['password'] as String?,
          forceRelay: launch['relay'] as bool? ?? false,
        );
      }
    });
  } else {
    await channel.invokeMethod<bool>('close');
  }
}

void configureEmbeddedDesktop({bool host = false}) {
  remote.localistThemeBootstrap = RemoteThemeSync.start;
  // Only session/approval windows are visible; main dispatch stays hidden.
  remote.localistHideHome = true;
  remote.localistBootstrap = () async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (!await bind.optionSynced()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Remote IPC initialization timed out.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await applyNativeRemoteProfile();
  };
  remote.localistOnReady = () async {
    if (!host) return;
    Future<void> sync() async {
      try {
        await applyNativeRemoteProfile();
        final state = jsonDecode(await bind.mainGetConnectStatus()) as Map;
        final file = LocalistRemoteRuntime.statusFile;
        await file.parent.create(recursive: true);
        await file.writeAsString(
          jsonEncode({
            'ready': true,
            'pid': pid,
            'updatedMs': DateTime.now().millisecondsSinceEpoch,
            'id': await bind.mainGetMyId(),
            'statusNum': state['status_num'],
            'profile': _appliedProfile,
          }),
        );
      } catch (error) {
        LogService.instance.warning(
          'Remote host synchronization failed: $error',
        );
      }
    }

    await sync();
    var syncing = false;
    Timer.periodic(const Duration(seconds: 1), (_) async {
      if (syncing) return;
      syncing = true;
      try {
        await sync();
      } finally {
        syncing = false;
      }
    });
  };
}

String? _appliedProfile;
Future<void>? _applyingProfile;
Future<void> applyNativeRemoteProfile() => _applyingProfile ??= _applyProfile()
    .whenComplete(() => _applyingProfile = null);

Future<void> _applyProfile() async {
  final profile = await RemoteControlProfile.load();
  final signature = jsonEncode({
    'server': profile.server.encode(),
    'values': profile.values,
  });
  if (signature == _appliedProfile) return;
  final existing = Map<String, String>.from(
    jsonDecode(bind.mainGetOptionsSync()) as Map,
  );
  await bind.mainSetOptions(
    json: jsonEncode({
      ...existing,
      ...profile.serverOptions,
      'allow-auto-update': 'N',
    }),
  );
  for (final setting in remoteSettings) {
    final value = profile.values[setting.key] ?? setting.defaultValue;
    switch (setting.scope) {
      case RemoteOptionScope.server:
        break;
      case RemoteOptionScope.local:
        if (setting.key == 'theme') break;
        final effective = setting.key == 'enable-check-update' ? 'N' : value;
        if (bind.mainGetLocalOption(key: setting.key) != effective) {
          await bind.mainSetLocalOption(key: setting.key, value: effective);
        }
      case RemoteOptionScope.display:
        if (setting.key == 'allow-terminal-clipboard-write') {
          await bind.mainSetLocalOption(key: setting.key, value: value);
        } else {
          await bind.mainSetUserDefaultOption(
            key: setting.key,
            value: remoteDisplayValue(setting, value),
          );
        }
      case RemoteOptionScope.native:
        // Native settings have explicit Localist controls. Applying a profile
        // must not silently generate 2FA secrets or change an elevated registry.
        break;
    }
  }
  _appliedProfile = signature;
}
