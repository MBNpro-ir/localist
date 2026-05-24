import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_update_service.dart';
import 'log_service.dart';
import 'native_bridge_service.dart';

const _supportEmail = 'support@prs.localist';

class CrashReporterService {
  CrashReporterService._();

  static final CrashReporterService instance = CrashReporterService._();

  bool _installed = false;

  Future<void> initialize() async {
    if (_installed) {
      return;
    }
    _installed = true;
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterHandler?.call(details);
      unawaited(reportFlutterError(details));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(reportFatalError(error, stack));
      return true;
    };
  }

  Future<void> reportFlutterError(FlutterErrorDetails details) {
    return _sendReport(
      title: 'Flutter framework crash',
      error: details.exception,
      stack: details.stack,
      context: details.context?.toDescription(),
      library: details.library,
    );
  }

  Future<void> reportFatalError(Object error, StackTrace stack) {
    return _sendReport(
      title: 'Unhandled Dart crash',
      error: error,
      stack: stack,
    );
  }

  Future<void> _sendReport({
    required String title,
    required Object error,
    StackTrace? stack,
    String? context,
    String? library,
  }) async {
    try {
      final debugWasActive = LogService.instance.debugModeEnabled;
      await _enableDebugModeAfterCrash();
      LogService.instance.error('$title: $error');
      await _showWindowsCrashNotice(debugWasActive: debugWasActive);
      final body = await _buildBody(
        title: title,
        error: error,
        stack: stack,
        context: context,
        library: library,
      );
      final uri = Uri(
        scheme: 'mailto',
        path: _supportEmail,
        queryParameters: {'subject': 'Localist crash report', 'body': body},
      );
      await NativeBridgeService.instance.openUri(uri.toString());
    } catch (_) {
      // Crash reporting must never create a second crash.
    }
  }

  Future<void> _enableDebugModeAfterCrash() async {
    try {
      LogService.instance.setDebugMode(true, announce: false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_debugModePreferenceKey, true);
      LogService.instance.warning(
        'Crash detected. Active debug mode was enabled automatically.',
      );
    } catch (_) {
      // Crash reporting must keep going even when preferences are unavailable.
    }
  }

  Future<void> _showWindowsCrashNotice({required bool debugWasActive}) async {
    if (!Platform.isWindows) {
      return;
    }
    final logPath = LogService.instance.debugLogFilePath ?? 'debug.log';
    final message = debugWasActive
        ? 'Localist crashed while debug mode was active.\n\n'
              'The debug log was saved here:\n$logPath\n\n'
              'Send debug.log to the developer so the crash can be traced.'
        : 'Localist crashed.\n\n'
              'Debug mode was enabled automatically.\n'
              'Open Localist again so startup and runtime logs are saved here:\n'
              '$logPath';
    try {
      await NativeBridgeService.instance.showWindowsMessage(
        title: 'Localist crash detected',
        message: message,
        warning: true,
      );
    } catch (_) {
      // If the native bridge is gone, the native runner crash marker handles it.
    }
  }

  Future<String> _buildBody({
    required String title,
    required Object error,
    StackTrace? stack,
    String? context,
    String? library,
  }) async {
    final version = await AppVersion.current();
    final buffer = StringBuffer()
      ..writeln('Localist crash report')
      ..writeln('======================')
      ..writeln('Type: $title')
      ..writeln('Time: ${DateTime.now().toIso8601String()}')
      ..writeln('Version: ${version.displayName}')
      ..writeln(
        'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      )
      ..writeln('Dart: ${Platform.version}')
      ..writeln('Executable: ${Platform.resolvedExecutable}');
    if (Platform.isAndroid) {
      final sdk = await NativeBridgeService.instance.getAndroidSdkInt();
      final abis = await NativeBridgeService.instance.getAndroidSupportedAbis();
      buffer
        ..writeln('Android SDK: ${sdk ?? 'unknown'}')
        ..writeln('Android ABIs: ${abis.join(', ')}');
    }
    if (library != null && library.isNotEmpty) {
      buffer.writeln('Library: $library');
    }
    if (context != null && context.isNotEmpty) {
      buffer.writeln('Context: $context');
    }
    buffer
      ..writeln()
      ..writeln('Error')
      ..writeln('-----')
      ..writeln(error)
      ..writeln()
      ..writeln('Stack trace')
      ..writeln('-----------')
      ..writeln(stack ?? StackTrace.current)
      ..writeln()
      ..writeln('Application logs')
      ..writeln('----------------')
      ..writeln(
        LogService.instance.dump().isEmpty
            ? 'No logs recorded.'
            : LogService.instance.dump(),
      );
    return buffer.toString();
  }
}

const _debugModePreferenceKey = 'debug.activeMode';
