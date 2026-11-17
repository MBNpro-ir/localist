import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/developer_bridge_models.dart';

class DeveloperBridgeAdbService extends ChangeNotifier {
  String? executablePath;
  String? version;
  List<AdbDevice> devices = const [];
  List<AdbMdnsService> wirelessServices = const [];
  final Set<String> _managedEndpoints = {};
  DeveloperBridgeFailure? failure;
  String diagnosticOutput = '';
  bool busy = false;
  bool _disposed = false;
  int _generation = 0;
  Process? _activeProcess;

  @override
  void dispose() {
    _disposed = true;
    _activeProcess?.kill();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> initialize() async {
    final generation = ++_generation;
    if (!Platform.isWindows) {
      _fail(DeveloperBridgeErrorCode.unsupportedPlatform, '');
      return;
    }
    final path = await _findAdbExecutable();
    if (_disposed || generation != _generation) return;
    if (path == null) {
      _fail(DeveloperBridgeErrorCode.adbExecutableNotFound, '');
      return;
    }
    await useExecutable(path);
  }

  void deactivate() {
    _generation++;
  }

  Future<void> useExecutable(String path) async {
    if (_disposed) return;
    final normalized = path.trim().replaceAll('"', '');
    if (normalized.isEmpty || !await File(normalized).exists()) {
      _fail(DeveloperBridgeErrorCode.invalidAdbExecutable, '');
      return;
    }
    executablePath = normalized;
    version = null;
    failure = null;
    busy = true;
    _notify();
    try {
      final result = await _run(const ['version']);
      if (result.exitCode != 0) {
        _fail(classifyAdbFailure(result.output), result.output);
        return;
      }
      version = result.output
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .firstWhere(
            (line) => line.startsWith('Android Debug Bridge version'),
            orElse: () => 'ADB version detected',
          );
      diagnosticOutput = result.output.trim();
      failure = null;
      _notify();
    } on DeveloperBridgeFailure catch (error) {
      failure = error;
      _notify();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> discoverWirelessServices() async {
    final result = await _execute(const ['mdns', 'services']);
    if (result == null) return;
    wirelessServices = parseAdbMdnsServices(result.output);
    final failed =
        result.exitCode != 0 ||
        result.output.toLowerCase().contains('mdns subsystem unavailable');
    failure = failed
        ? DeveloperBridgeFailure(
            classifyAdbFailure(result.output),
            _safeOutput(result.output.trim()),
          )
        : null;
    diagnosticOutput = _safeOutput(result.output.trim());
    _notify();
  }

  Future<void> refreshDevices() async {
    final result = await _execute(const ['devices', '-l']);
    if (result == null) return;
    devices = parseAdbDevices(result.output);
    diagnosticOutput = result.output.trim();
    failure = result.exitCode == 0
        ? devices.isEmpty
              ? const DeveloperBridgeFailure(
                  DeveloperBridgeErrorCode.deviceNotDetected,
                  '',
                )
              : null
        : DeveloperBridgeFailure(
            classifyAdbFailure(result.output),
            _safeOutput(result.output),
          );
    _notify();
  }

  Future<void> connect(String endpointText) async {
    final endpoint = AdbEndpoint.tryParse(endpointText);
    if (endpoint == null) {
      _fail(
        endpointText.trim().isEmpty
            ? DeveloperBridgeErrorCode.phoneIpUnavailable
            : DeveloperBridgeErrorCode.invalidEndpoint,
        '',
      );
      return;
    }
    final result = await _execute(['connect', endpoint.value]);
    if (result == null) return;
    final failed =
        result.exitCode != 0 ||
        result.output.toLowerCase().contains('failed to connect') ||
        result.output.toLowerCase().contains('cannot connect');
    if (failed) {
      _fail(classifyAdbFailure(result.output), result.output);
      return;
    }
    _managedEndpoints.add(endpoint.value);
    diagnosticOutput = _safeOutput(result.output.trim());
    failure = null;
    _notify();
    await refreshDevices();
  }

  Future<void> disconnect(String endpointText) async {
    final endpoint = AdbEndpoint.tryParse(endpointText);
    if (endpoint == null) {
      _fail(
        endpointText.trim().isEmpty
            ? DeveloperBridgeErrorCode.phoneIpUnavailable
            : DeveloperBridgeErrorCode.invalidEndpoint,
        '',
      );
      return;
    }
    final result = await _execute(['disconnect', endpoint.value]);
    if (result == null) return;
    if (result.exitCode != 0) {
      _fail(classifyAdbFailure(result.output), result.output);
      return;
    }
    _managedEndpoints.remove(endpoint.value);
    diagnosticOutput = _safeOutput(result.output.trim());
    failure = null;
    _notify();
    await refreshDevices();
  }

  Future<void> disconnectManagedEndpoints() async {
    for (final endpoint in _managedEndpoints.toList()) {
      await disconnect(endpoint);
    }
  }

  Future<void> pair(String endpointText, String pairingCode) async {
    final endpoint = AdbEndpoint.tryParse(endpointText);
    final code = pairingCode.trim();
    if (endpoint == null) {
      _fail(
        endpointText.trim().isEmpty
            ? DeveloperBridgeErrorCode.phoneIpUnavailable
            : DeveloperBridgeErrorCode.invalidEndpoint,
        '',
      );
      return;
    }
    if (code.isEmpty || !RegExp(r'^\d{4,12}$').hasMatch(code)) {
      _fail(DeveloperBridgeErrorCode.invalidPairingCode, '');
      return;
    }
    final result = await _execute(
      ['pair', endpoint.value],
      stdinLine: code,
      timeout: const Duration(seconds: 60),
      redact: [code],
    );
    if (result == null) return;
    final normalized = result.output.toLowerCase();
    final paired =
        result.exitCode == 0 &&
        (normalized.contains('successfully paired') ||
            normalized.contains('already paired'));
    if (!paired) {
      _fail(
        classifyAdbFailure(result.output, pairing: true),
        result.output,
        redact: [code],
      );
      return;
    }
    diagnosticOutput = _safeOutput(result.output.trim(), redact: [code]);
    failure = null;
    _notify();
  }

  Future<_AdbResult?> _execute(
    List<String> arguments, {
    String? stdinLine,
    Duration timeout = const Duration(seconds: 20),
    List<String> redact = const [],
  }) async {
    if (busy) return null;
    if (executablePath == null) {
      _fail(DeveloperBridgeErrorCode.adbExecutableNotFound, '');
      return null;
    }
    busy = true;
    failure = null;
    _notify();
    try {
      final result = await _run(
        arguments,
        stdinLine: stdinLine,
        timeout: timeout,
      );
      diagnosticOutput = _safeOutput(result.output.trim(), redact: redact);
      return result;
    } on DeveloperBridgeFailure catch (error) {
      failure = DeveloperBridgeFailure(
        error.code,
        _safeOutput(error.output, redact: redact),
      );
      _notify();
      return null;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<_AdbResult> _run(
    List<String> arguments, {
    String? stdinLine,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final path = executablePath;
    if (path == null) {
      throw const DeveloperBridgeFailure(
        DeveloperBridgeErrorCode.adbExecutableNotFound,
        '',
      );
    }
    Process process;
    try {
      process = await Process.start(path, arguments, runInShell: false);
    } on ProcessException {
      throw const DeveloperBridgeFailure(
        DeveloperBridgeErrorCode.invalidAdbExecutable,
        '',
      );
    }
    _activeProcess = process;
    try {
      if (_disposed) {
        process.kill();
        throw const DeveloperBridgeFailure(
          DeveloperBridgeErrorCode.adbCommandFailed,
          '',
        );
      }
      final stdout = process.st