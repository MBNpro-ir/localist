import 'dart:async';

import 'package:flutter/foundation.dart';

import 'log_service.dart';

class CrashReporterService {
  CrashReporterService._();

  static final CrashReporterService instance = CrashReporterService._();

  bool _installed = false;
  bool _fatalReportInProgress = false;
  String? _lastFatalSignature;
  DateTime? _lastFatalReportAt;
  String? _lastFrameworkSignature;
  DateTime? _lastFrameworkLogAt;

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

  Future<void> reportFlutterError(FlutterErrorDetails details) async {
    // Flutter framework errors are often recoverable rendering/build errors.
    // They must be logged for diagnosis, but reporting them as process crashes
    // causes modal-dialog loops when the same widget rebuilds repeatedly.
    final now = DateTime.now();
    final signature = [
      details.exceptionAsString(),
      details.library ?? '',
      details.context?.toDescription() ?? '',
    ].join('|');
    if (_lastFrameworkSignature == signature &&
        _lastFrameworkLogAt != null &&
        now.difference(_lastFrameworkLogAt!) < const Duration(seconds: 30)) {
      return;
    }
    _lastFrameworkSignature = signature;
    _lastFrameworkLogAt = now;
    LogService.instance.error(
      'Flutter framework error: ${details.exceptionAsString()}',
    );
    final stack = details.stack;
    if (stack != null) {
      LogService.instance.debug('Flutter framework error stack', stack: stack);
    }
  }

  Future<void> reportFatalError(Object error, StackTrace stack) async {
    final now = DateTime.now();
    final signature = '${error.runtimeType}|$error';
    if (_fatalReportInProgress ||
        (_lastFatalSignature == signature &&
            _lastFatalReportAt != null &&
            now.difference(_lastFatalReportAt!) < const Duration(minutes: 5))) {
      return;
    }
    _fatalReportInProgress = true;
    _lastFatalSignature = signature;
    _lastFatalReportAt = now;
    try {
      // Capture the error locally with the current user-selected logging
      // level. Never enable Debug, show startup modals or launch a mail client.
      LogService.instance.error('Unhandled Dart error: $error');
      LogService.instance.debug('Unhandled Dart error stack', stack: stack);
    } finally {
      _fatalReportInProgress = false;
    }
  }
}
