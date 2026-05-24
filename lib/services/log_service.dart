import 'dart:io';

import 'package:flutter/foundation.dart';

enum LogSeverity {
  debug('DEBUG'),
  info('Info'),
  warning('Warning'),
  error('Error');

  const LogSeverity(this.label);

  final String label;
}

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.severity,
    required this.message,
  });

  final DateTime timestamp;
  final LogSeverity severity;
  final String message;

  String get line {
    final time = timestamp.toIso8601String().replaceFirst('T', ' ');
    return '[$time] ${severity.label}: $message';
  }
}

class LogService extends ChangeNotifier {
  LogService._();

  static final LogService instance = LogService._();
  static const _maxEntries = 1200;
  static const _debugLogFileName = 'debug.log';

  final List<LogEntry> _entries = [];
  bool _debugModeEnabled = false;
  bool _debugFileWarningShown = false;

  List<LogEntry> get entries => List.unmodifiable(_entries.reversed);
  bool get debugModeEnabled => _debugModeEnabled;

  void debug(String message, {Object? error, StackTrace? stack}) {
    if (!_debugModeEnabled) {
      return;
    }
    _add(
      LogSeverity.debug,
      _withDebugSource(
        message,
        error: error,
        stack: stack ?? StackTrace.current,
      ),
    );
  }

  void info(String message) => _add(LogSeverity.info, message);
  void warning(String message) => _add(LogSeverity.warning, message);
  void error(String message) => _add(LogSeverity.error, message);

  String dump({bool includeDebug = true}) => _entries
      .where((entry) => includeDebug || entry.severity != LogSeverity.debug)
      .map((entry) => entry.line)
      .join('\n');

  void setDebugMode(bool enabled, {bool announce = true}) {
    if (_debugModeEnabled == enabled) {
      return;
    }
    _debugModeEnabled = enabled;
    if (enabled) {
      _startWindowsDebugFile();
    }
    if (announce) {
      _add(
        enabled ? LogSeverity.info : LogSeverity.warning,
        enabled
            ? 'Debug mode enabled. DEBUG logs are now being captured.'
            : 'Debug mode disabled. DEBUG logs are paused.',
      );
      if (enabled) {
        debug('Debug logger is ready.');
      } else {
        _deleteWindowsDebugFile();
      }
      return;
    }
    if (!enabled) {
      _deleteWindowsDebugFile();
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void _add(LogSeverity severity, String message) {
    if (severity == LogSeverity.debug && !_debugModeEnabled) {
      return;
    }
    _entries.add(
      LogEntry(timestamp: DateTime.now(), severity: severity, message: message),
    );
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    _appendWindowsDebugFile(_entries.last);
    notifyListeners();
  }

  File? get _windowsDebugFile {
    if (!Platform.isWindows) {
      return null;
    }
    final executable = File(Platform.resolvedExecutable);
    return File(
      '${executable.parent.path}${Platform.pathSeparator}$_debugLogFileName',
    );
  }

  void _startWindowsDebugFile() {
    final file = _windowsDebugFile;
    if (file == null) {
      return;
    }
    _debugFileWarningShown = false;
    try {
      file.writeAsStringSync(
        [
          'Localist debug log',
          '===================',
          'Started: ${DateTime.now().toIso8601String()}',
          'Executable: ${Platform.resolvedExecutable}',
          '',
        ].join('\n'),
        mode: FileMode.write,
        flush: true,
      );
    } catch (error) {
      _debugFileWarningShown = true;
      _entries.add(
        LogEntry(
          timestamp: DateTime.now(),
          severity: LogSeverity.warning,
          message:
              'Could not create debug.log beside the Windows executable: $error',
        ),
      );
    }
  }

  void _appendWindowsDebugFile(LogEntry entry) {
    if (!_debugModeEnabled || !Platform.isWindows) {
      return;
    }
    final file = _windowsDebugFile;
    if (file == null) {
      return;
    }
    try {
      file.writeAsStringSync(
        '${entry.line}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (error) {
      if (_debugFileWarningShown) {
        return;
      }
      _debugFileWarningShown = true;
      _entries.add(
        LogEntry(
          timestamp: DateTime.now(),
          severity: LogSeverity.warning,
          message: 'Could not append to Windows debug.log: $error',
        ),
      );
    }
  }

  void _deleteWindowsDebugFile() {
    final file = _windowsDebugFile;
    if (file == null) {
      return;
    }
    _debugFileWarningShown = false;
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Turning debug mode off should never crash the app.
    }
  }

  String _withDebugSource(
    String message, {
    Object? error,
    required StackTrace stack,
  }) {
    final details = <String>[message];
    final source = _callerFrom(stack);
    if (source != null) {
      details.add('source=$source');
    }
    if (error != null) {
      details.add('error=$error');
    }
    return details.join(' | ');
  }

  String? _callerFrom(StackTrace stack) {
    for (final line in stack.toString().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.contains('log_service.dart')) {
        continue;
      }
      final parenthesized = RegExp(r'\(([^)]+)\)').firstMatch(trimmed);
      if (parenthesized != null) {
        return parenthesized.group(1);
      }
      final fallback = RegExp(r'#\d+\s+(.+)$').firstMatch(trimmed);
      if (fallback != null) {
        return fallback.group(1)?.trim();
      }
    }
    return null;
  }
}
