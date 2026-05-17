import 'package:flutter/foundation.dart';

enum LogSeverity {
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
  static const _maxEntries = 500;

  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries.reversed);

  void info(String message) => _add(LogSeverity.info, message);
  void warning(String message) => _add(LogSeverity.warning, message);
  void error(String message) => _add(LogSeverity.error, message);

  String dump() => _entries.map((entry) => entry.line).join('\n');

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void _add(LogSeverity severity, String message) {
    _entries.add(
      LogEntry(timestamp: DateTime.now(), severity: severity, message: message),
    );
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    notifyListeners();
  }
}
