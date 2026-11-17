import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/main.dart' as remote;
import 'package:flutter_hbb/common.dart' as engine;
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/mobile/pages/server_page.dart';
import 'package:flutter_hbb/common/widgets/overlay.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/localist/desktop_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/remote_control_settings.dart';
import '../models/app_settings.dart';
import '../l10n/app_localizations.dart';
import '../services/log_service.dart';
import '../services/feature_permission_service.dart';
import 'remote_theme.dart';
import 'remote_session_return.dart';
import 'android_remote_host.dart';
import 'desktop_host_bridge.dart';
import 'desktop_host_runtime.dart';
import 'desktop_host_launch.dart';
import 'remote_peer_presence.dart';

class LocalistRemoteRuntime {
  static Future<void>? _starting;
  static DesktopHostRuntime? _desktop;
  static Future<void>? _desktopPreparation;
  static Future<String>? _fingerprint;
  static final _androidPresence = RemotePeerPresenceStore();
  static String? _androidPresenceServer;

  static Future<Map<String, String>> peerPresence(List<String> ids) async {
    LogService.instance.debug(
      'Remote presence query dispatched platform=${Platform.operatingSystem} peerCount=${ids.length}',
    );
    if (Platform.isWindows) {
      final result = await desktopCommand({'command': 'presence', 'ids': ids});
      LogService.instance.debug(
        'Remote Windows presence query returned peerCount=${(result['states'] as Map).length}',
      );
      return Map<String, String>.from(result['states'] as Map);
    }
    if (Platform.isAndroid) {
      await ensureStarted();
      await applyNativeRemoteProfile();
      final server = (await RemoteControlProfile.load()).server.encode();
      if (server != _androidPresenceServer) {
        LogService.instance.debug(
          'Remote Android presence server changed; clearing previous states',
        );
        _androidPresenceServer = server;
        _androidPresence.clear();
      }
      await bind.queryOnlines(ids: ids);
      LogService.instance.debug(
        'Remote Android presence query sent peerCount=${ids.length}',
      );
      return _androidPresence.snapshot(ids);
    }
    return {};
  }

  static File get statusFile => File(
    '${Platform.environment['APPDATA']}\\PRS\\Localist\\remote-status.json',
  );

  static String get hostExecutablePath {
    final parent = File(Platform.resolvedExecutable).parent.path;
    return '$parent\\LocalistRemote.exe';
  }

  static Future<String> hostFingerprint() => _fingerprint ??= sha256
      .bind(File(hostExecutablePath).openRead())
      .first
      .then((digest) => digest.toString());

  static DesktopHostRuntime get _desktopRuntime =>
      _desktop ??= DesktopHostRuntime(
        statusFile: statusFile,
        executablePath: hostExecutablePath,
        fingerprint: hostFingerprint,
        isHostRunning: (status) async =>
            await const MethodChannel(
              'com.prs.localist.vpn',
            ).invokeMethod<bool>('isRemoteHostRunning', status) ??
            false,
        retireHost: (status) async =>
            await const MethodChannel(
              'com.prs.localist.vpn',
            ).invokeMethod<bool>('retireRemoteHost', status) ??
            false,
        startHost: () async {
          final executable = File(hostExecutablePath);
          final process = await Process.start(
            executable.path,
            desktopHostLaunchArguments,
            workingDirectory: executable.parent.path,
          );
          unawaited(process.stdout.drain<void>());
          unawaited(process.stderr.drain<void>());
          LogService.instance.info('Remote host started (PID ${process.pid}).');
          return DesktopHostProcess(process.pid, process.exitCode);
        },
      );

  static Future<Map<String, dynamic>?> desktopStatus() =>
      _desktopRuntime.status();

  static Future<Map<String, dynamic>> desktopCommand(
    Map<String, dynamic> command,
  ) async {
    const safeCommands = {
      'ping',
      'syncProfile',
      'regeneratePassword',
      'credentials',
      'openSession',
      'presence',
    };
    final operation = safeCommands.contains(command['command'])
        ? command['command']
        : 'unknown';
    LogService.instance.debug(
      'Remote desktop command stage=ensureHost kind=$operation',
    );
    await ensureStarted();
    var status = await desktopStatus();
    if (status == null) {
      LogService.instance.debug(
        'Remote desktop command host unavailable; restarting',
      );
      // An adopted host may have exited since initialization.
      _starting = null;
      await ensureStarted();
      status = await desktopStatus();
    }
    if (status == null) {
      LogService.instance.debug(
        'Remote desktop command failed host still unavailable',
      );
      throw StateError('The remote host is unavailable.');
    }
    LogService.instance.debug(
      'Remote desktop command stage=send kind=$operation',
    );
    return sendDesktopHostCommand(
      status,
      command,
      timeout: command['command'] == 'openSession'
          ? const Duration(seconds: 90)
          : const Duration(seconds: 20),
    );
  }

  static Future<void> ensureStarted() {
    LogService.instance.debug(
      'Remote runtime ensureStarted platform=${Platform.operatingSystem} startupPending=${_starting != null}',
    );
    if (Platform.isWindows) {
      return (_desktopPreparation ??= _prepareDesktop()).then(
        (_) => _desktopRuntime.ensureStarted(),
      );
    }
    return _starting ??= _start().catchError((Object error) {
      _starting = null;
      throw error;
    });
  }

  static Future<void> _prepareDesktop() async {
    LogService.instance.debug(
      'Remote desktop runtime checking bundled host compatibility',
    );
    final main = File(Platform.resolvedExecutable);
    final helper = File(hostExecutablePath);
    if (await helper.exists()) {
      final mainHash = await sha256.bind(main.openRead()).first;
      final helperHash = await sha256.bind(helper.openRead()).first;
      if (mainHash != helperHash) {
        LogService.instance.debug(
          'Remote desktop runtime host executable version mismatch',
        );
        throw StateError(
          'فایل‌های موتور ریموت با برنامه یکسان نیستند؛ بستهٔ کامل نسخهٔ جدید را نصب کنید. / '
          'Remote IPC executable mismatch. Install the complete current Localist package.',
        );
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remote.localPassword');
    LogService.instance.debug('Remote desktop runtime bundle check finished');
  }

  static Future<void> _start() async {
    LogService.instance.debug('Remote embedded runtime initialization started');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('remote.localPassword');
    if (Platform.isAndroid) {
      LogService.instance.debug(
        'Remote Android engine environment initializing',
      );
      remote.localistThemeBootstrap = RemoteThemeSync.start;
      remote.kBootArgs = [];
      engine.localistOwnsAndroidHosting = true;
      engine.localistPermissionRequest = (type) {
        final access = switch (type) {
          'android.permission.RECORD_AUDIO' => FeatureAccess.microphone,
          'android.permission.CAMERA' => FeatureAccess.camera,
          'android.permission.POST_NOTIFICATIONS' =>
            FeatureAccess.notifications,