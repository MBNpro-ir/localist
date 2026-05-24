import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'app_update_service.dart';
import 'log_service.dart';
import 'native_bridge_service.dart';

class LogExportService {
  LogExportService._();

  static final LogExportService instance = LogExportService._();

  Future<SavedTextFileResult> saveDebugLog() async {
    final logs = LogService.instance;
    logs.debug('Log export requested');
    final report = await buildDebugReport();
    final result = await NativeBridgeService.instance.saveTextFile(
      text: report,
      suggestedName: _suggestedName(),
      mimeType: 'text/plain',
    );
    logs.debug(
      'Log export completed saved=${result.saved} canceled=${result.canceled} path=${result.path}',
    );
    return result;
  }

  Future<String> buildDebugReport() async {
    final version = await AppVersion.current();
    final nativeDetails = await _loadNativeDetails();
    final interfaces = await _loadNetworkInterfaces();
    final logs = LogService.instance;
    final entries = logs.entries;
    final now = DateTime.now();
    final locales = PlatformDispatcher.instance.locales
        .map((locale) => locale.toLanguageTag())
        .join(', ');
    final buffer = StringBuffer()
      ..writeln('Localist debug log export')
      ..writeln('==========================')
      ..writeln('Generated at: ${now.toIso8601String()}')
      ..writeln('App version: ${version.displayName}+${version.build}')
      ..writeln('Build mode: ${_buildMode()}')
      ..writeln('Debug mode active: ${logs.debugModeEnabled}')
      ..writeln('Log entries: ${entries.length}')
      ..writeln('Platform: ${Platform.operatingSystem}')
      ..writeln('Platform version: ${Platform.operatingSystemVersion}')
      ..writeln('Dart runtime: ${Platform.version}')
      ..writeln('Executable: ${Platform.resolvedExecutable}')
      ..writeln('Locale: ${PlatformDispatcher.instance.locale.toLanguageTag()}')
      ..writeln('Locales: ${locales.isEmpty ? 'unknown' : locales}')
      ..writeln('Processors: ${Platform.numberOfProcessors}')
      ..writeln('Path separator: ${Platform.pathSeparator}')
      ..writeln()
      ..writeln('Native device details')
      ..writeln('---------------------');
    if (nativeDetails.isEmpty) {
      buffer.writeln('No native device details returned.');
    } else {
      for (final entry in nativeDetails.entries) {
        buffer.writeln('${entry.key}: ${_formatDetailValue(entry.value)}');
      }
    }
    buffer
      ..writeln()
      ..writeln('Selected environment')
      ..writeln('--------------------');
    for (final key in _environmentKeys) {
      final value = Platform.environment[key];
      if (value != null && value.isNotEmpty) {
        buffer.writeln('$key: $value');
      }
    }
    buffer
      ..writeln()
      ..writeln('Network interfaces')
      ..writeln('------------------');
    if (interfaces.isEmpty) {
      buffer.writeln('No network interfaces returned.');
    } else {
      for (final line in interfaces) {
        buffer.writeln(line);
      }
    }
    buffer
      ..writeln()
      ..writeln('Application logs')
      ..writeln('----------------')
      ..writeln(logs.dump().isEmpty ? 'No logs recorded.' : logs.dump());
    return buffer.toString();
  }

  Future<Map<String, Object?>> _loadNativeDetails() async {
    try {
      return await NativeBridgeService.instance.getDeviceDetails();
    } catch (error, stack) {
      LogService.instance.debug(
        'Failed to load native device details for log export',
        error: error,
        stack: stack,
      );
      return const {};
    }
  }

  Future<List<String>> _loadNetworkInterfaces() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: true,
        includeLoopback: true,
      ).timeout(const Duration(seconds: 3));
      return [
        for (final interface in interfaces)
          '${interface.name} index=${interface.index} addresses=${interface.addresses.map(_addressLine).join('; ')}',
      ];
    } catch (error, stack) {
      LogService.instance.debug(
        'Failed to enumerate network interfaces for log export',
        error: error,
        stack: stack,
      );
      return const ['Network interface enumeration failed.'];
    }
  }

  String _addressLine(InternetAddress address) {
    final kind = address.type == InternetAddressType.IPv6 ? 'IPv6' : 'IPv4';
    final flags = <String>[
      if (address.isLoopback) 'loopback',
      if (address.isLinkLocal) 'linkLocal',
      if (address.isMulticast) 'multicast',
    ];
    final suffix = flags.isEmpty ? '' : ' (${flags.join(', ')})';
    return '$kind ${address.address}$suffix';
  }

  String _buildMode() {
    if (kReleaseMode) {
      return 'release';
    }
    if (kProfileMode) {
      return 'profile';
    }
    return 'debug';
  }

  String _formatDetailValue(Object? value) {
    if (value is Iterable) {
      return value.map(_formatDetailValue).join(', ');
    }
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}=${_formatDetailValue(entry.value)}')
          .join(', ');
    }
    return value?.toString() ?? 'null';
  }

  String _suggestedName() {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .replaceAll('T', '_');
    return 'localist-debug-log-$stamp.txt';
  }

  static const _environmentKeys = [
    'COMPUTERNAME',
    'USERNAME',
    'USERDOMAIN',
    'OS',
    'PROCESSOR_ARCHITECTURE',
    'PROCESSOR_IDENTIFIER',
    'NUMBER_OF_PROCESSORS',
    'APPDATA',
    'LOCALAPPDATA',
    'ANDROID_ROOT',
    'ANDROID_DATA',
    'EXTERNAL_STORAGE',
  ];
}
