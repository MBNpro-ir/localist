import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'desktop_host_bridge.dart';

const desktopHostStatusVersion = 2;

class DesktopHostProcess {
  DesktopHostProcess(this.pid, this.exitCode);
  final int pid;
  final Future<int> exitCode;
}

/// A status file advertises a host; it does not establish its identity or
/// liveness. Keep startup serialized; a busy host can be verified through its
/// native process identity when its event loop cannot answer a ping. The native
/// callbacks check the actual image and creation time, independently of whether
/// a Flutter window is temporarily blocking status updates.
class DesktopHostRuntime {
  DesktopHostRuntime({
    required this.statusFile,
    required this.executablePath,
    required this.fingerprint,
    required this.startHost,
    required this.retireHost,
    required this.isHostRunning,
    this.startupTimeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(milliseconds: 150),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final File statusFile;
  final String executablePath;
  final Future<String> Function() fingerprint;
  final Future<DesktopHostProcess> Function() startHost;
  final Future<bool> Function(Map<String, dynamic>) retireHost;
  final Future<bool> Function(Map<String, dynamic>) isHostRunning;
  final Duration startupTimeout;
  final Duration pollInterval;
  final DateTime Function() _now;
  Future<void>? _starting;
  int? _hostPid;
  Map<String, dynamic>? _ownedStatus;

  Future<Map<String, dynamic>?> _read() async {
    try {
      return jsonDecode(await statusFile.readAsString())
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  bool _matches(Map<String, dynamic> data, String digest) =>
      data['statusVersion'] == desktopHostStatusVersion &&
      data['bridgeVersion'] == 1 &&
      data['hostExecutable'] is String &&
      (data['hostExecutable'] as String).replaceAll('/', '\\').toLowerCase() ==
          executablePath.replaceAll('/', '\\').toLowerCase() &&
      data['hostFingerprint'] == digest &&
      data['ready'] == true &&
      data['pid'] is int &&
      (data['pid'] as int) > 0;

  Future<Map<String, dynamic>?> status() async {
    final data = await _read();
    if (data == null || !_matches(data, await fingerprint())) return null;
    return _fresh(data) || await isHostRunning(data) ? data : null;
  }

  bool _fresh(Map<String, dynamic> data) {
    final updated = data['updatedMs'];
    if (updated is! int) return false;
    final age = _now().millisecondsSinceEpoch - updated;
    return age >= -5000 && age <= 5000;
  }

  Future<bool> _ping(Map<String, dynamic> data) async {
    try {
      final reply = await sendDesktopHostCommand(
        data,
        {'command': 'ping'},
        timeout: const Duration(milliseconds: 700),
      ).timeout(const Duration(seconds: 1));
      return reply['ready'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _retire(Map<String, dynamic> data) async {
    // A malformed file cannot authorize terminating a process. Remove it and
    // let the native mutex arbitrate startup instead.
    if (data['pid'] is! int ||
        (data['pid'] as int) <= 0 ||
        data['updatedMs'] is! int ||
        (data['updatedMs'] as int) <= 0) {
      return true;
    }
    return retireHost(data);
  }

  Future<void> ensureStarted() =>
      _starting ??= _ensureStarted().whenComplete(() => _starting = null);

  Future<void> _ensureStarted() async {
    final digest = await fingerprint();
    final previous = await _read();
    if (previous != null) {
      if (_matches(previous, digest) &&
          (await _ping(previous) || await isHostRunning(previous))) {
        _hostPid = previous['pid'] as int;
        _ownedStatus = previous;
        return;
      }
      final sessions = previous['activeSessions'];
      if (sessions is num &&
          sessions > 0 &&
          (_fresh(previous) ||
              await _ping(previous) ||
              await isHostRunning(previous))) {
        throw StateError(
          'Close the existing remote sessions before updating the remote host.',
        );
      }
      if (!await _retire(previous)) {
        throw StateError(
          'The previous remote host could not be safely stopped. Restart Localist.',
        );
      }
      await _removeStatusFor(previous);
    }
    final process = await startHost();
    _hostPid = process.pid;
    _ownedStatus = {
      'pid': process.pid,
      'hostExecutable': executablePath,
      'updatedMs': _now().millisecondsSinceEpoch,
    };
    int? exited;
    unawaited(process.exitCode.then((value) => exited = value));
    final deadline = _now().add(startupTimeout);
    try {
      while (_now().isBefore(deadline)) {
        final data = await status();
        if (data != null &&
            data['pid'] == process.pid &&
            (await _ping(data) || await isHostRunning(data))) {
          _ownedStatus = data;
          return;
        }
        if (exited != null) {
          throw StateError(
            'The remote host exited during startup (code $exited).',
          );
        }
        await Future<void>.delayed(pollInterval);
      }
      throw TimeoutException('The remote-control host did not become ready.');
    } catch (_) {
      // Do not leave a half-initialized process retaining the native mutex.
      await _retire(_ownedStatus!);
      await _removeStatusFor(_ownedStatus!);
      _hostPid = null;
      _ownedStatus = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    try {
      await _starting;
    } catch (_) {
      /* startup already cleaned up */
    }
    // Closing one app must never delete a different bundle's status or stop
    // a PID it did not adopt or start.
    if (_hostPid != null) {
      // Retain the original heartbeat for native PID-reuse detection. A new
      // status with the same recycled PID must not authorize its termination.
      final owned = _ownedStatus!;
      if (await _retire(owned)) await _removeStatusFor(owned);
    }
    _hostPid = null;
    _ownedStatus = null;
  }

  Future<void> _removeStatusFor(Map<String, dynamic> expected) async {
    final current = await _read();
    if (current?['pid'] != expected['pid'] ||
        (expected['commandToken'] != null &&
            current?['commandToken'] != expected['commandToken']) ||
        (expected['hostExecutable'] != null &&
            current?['hostExecutable'] != expected['hostExecutable'])) {
      return;
    }
    try {
      await statusFile.delete();
    } on FileSystemException catch (_) {}
  }
}
