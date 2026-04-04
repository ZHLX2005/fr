import 'dart:async';

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  });

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }

  String get levelIcon {
    switch (level) {
      case LogLevel.debug:
        return '🔍';
      case LogLevel.info:
        return '📡';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }
}

class DebugLogService {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  final List<LogEntry> _logs = [];
  static const int maxLogs = 500;

  final _logsController = StreamController<List<LogEntry>>.broadcast();
  Stream<List<LogEntry>> get logsStream => _logsController.stream;
  List<LogEntry> get logs => List.unmodifiable(_logs);

  void log(LogLevel level, String tag, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
    );

    _logs.add(entry);
    if (_logs.length > maxLogs) {
      _logs.removeAt(0);
    }

    _logsController.add(List.unmodifiable(_logs));

    // Also print to debug console
    debugPrint('[$tag] $message');
  }

  void d(String tag, String message) => log(LogLevel.debug, tag, message);
  void i(String tag, String message) => log(LogLevel.info, tag, message);
  void w(String tag, String message) => log(LogLevel.warning, tag, message);
  void e(String tag, String message) => log(LogLevel.error, tag, message);

  void clear() {
    _logs.clear();
    _logsController.add(List.unmodifiable(_logs));
  }
}

final debugLog = DebugLogService();
