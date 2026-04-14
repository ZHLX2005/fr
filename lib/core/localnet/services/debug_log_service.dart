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

/// 状态机日志条目，用于可视化服务状态转换
class StateMachineEntry {
  final DateTime timestamp;
  final String service;
  final String fromState;
  final String toState;
  final String? note;

  StateMachineEntry({
    required this.timestamp,
    required this.service,
    required this.fromState,
    required this.toState,
    this.note,
  });

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }

  String get displayText {
    final noteStr = note != null ? ' ← $note' : '';
    return '$fromState → $toState$noteStr';
  }
}

class DebugLogService {
  static final DebugLogService _instance = DebugLogService._internal();
  factory DebugLogService() => _instance;
  DebugLogService._internal();

  final List<LogEntry> _logs = [];
  final List<StateMachineEntry> _stateMachineLogs = [];
  static const int maxLogs = 500;

  final _logsController = StreamController<List<LogEntry>>.broadcast();
  final _stateMachineController =
      StreamController<List<StateMachineEntry>>.broadcast();

  Stream<List<LogEntry>> get logsStream => _logsController.stream;
  Stream<List<StateMachineEntry>> get stateMachineStream =>
      _stateMachineController.stream;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  List<StateMachineEntry> get stateMachineLogs =>
      List.unmodifiable(_stateMachineLogs);

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

  /// 记录状态机转换
  void logState(String service, String from, String to, {String? note}) {
    final entry = StateMachineEntry(
      timestamp: DateTime.now(),
      service: service,
      fromState: from,
      toState: to,
      note: note,
    );

    _stateMachineLogs.add(entry);
    if (_stateMachineLogs.length > 200) {
      _stateMachineLogs.removeAt(0);
    }

    _stateMachineController.add(List.unmodifiable(_stateMachineLogs));

    // 打印状态转换日志
    final noteStr = note != null ? ' ($note)' : '';
    log(LogLevel.info, service, '[$from] → [$to]$noteStr');
  }

  void d(String tag, String message) => log(LogLevel.debug, tag, message);
  void i(String tag, String message) => log(LogLevel.info, tag, message);
  void w(String tag, String message) => log(LogLevel.warning, tag, message);
  void e(String tag, String message) => log(LogLevel.error, tag, message);

  void clear() {
    _logs.clear();
    _stateMachineLogs.clear();
    _logsController.add(List.unmodifiable(_logs));
    _stateMachineController.add(List.unmodifiable(_stateMachineLogs));
  }
}

final debugLog = DebugLogService();
