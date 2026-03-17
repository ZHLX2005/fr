import 'package:json_annotation/json_annotation.dart';

part 'lab_clock_record.g.dart';

/// 单次运行会话
/// 每次启动倒计时创建一个会话，暂停时结束会话
@JsonSerializable()
class ClockSession {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;  // null 表示会话正在进行中

  ClockSession({
    required this.id,
    required this.startTime,
    this.endTime,
  });

  factory ClockSession.fromJson(Map<String, dynamic> json) => _$ClockSessionFromJson(json);

  Map<String, dynamic> toJson() => _$ClockSessionToJson(this);

  /// 获取会话时长（秒）
  /// 只有会话结束时才有值
  int get duration {
    if (endTime == null) return 0;
    return endTime!.difference(startTime).inSeconds;
  }

  /// 判断会话是否已结束
  bool get isCompleted => endTime != null;

  ClockSession copyWith({
    String? id,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return ClockSession(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  /// 结束会话
  ClockSession end() {
    return ClockSession(
      id: id,
      startTime: startTime,
      endTime: DateTime.now(),
    );
  }
}

/// 时钟使用记录
@JsonSerializable()
class LabClockRecord {
  final String id;
  final String clockId;
  final String clockTitle;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationSeconds; // 计划倒计时时长（秒）
  final bool completed; // 是否完成
  final List<ClockSession> sessions; // 运行会话列表

  LabClockRecord({
    required this.id,
    required this.clockId,
    required this.clockTitle,
    required this.startTime,
    this.endTime,
    required this.durationSeconds,
    this.completed = false,
    List<ClockSession>? sessions,
  }) : sessions = sessions ?? [];

  factory LabClockRecord.fromJson(Map<String, dynamic> json) => _$LabClockRecordFromJson(json);

  Map<String, dynamic> toJson() => _$LabClockRecordToJson(this);

  LabClockRecord copyWith({
    String? id,
    String? clockId,
    String? clockTitle,
    DateTime? startTime,
    DateTime? endTime,
    int? durationSeconds,
    bool? completed,
    List<ClockSession>? sessions,
  }) {
    return LabClockRecord(
      id: id ?? this.id,
      clockId: clockId ?? this.clockId,
      clockTitle: clockTitle ?? this.clockTitle,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      completed: completed ?? this.completed,
      sessions: sessions ?? this.sessions,
    );
  }

  /// 添加新会话（开始运行）
  LabClockRecord addSession(ClockSession session) {
    return LabClockRecord(
      id: id,
      clockId: clockId,
      clockTitle: clockTitle,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: durationSeconds,
      completed: completed,
      sessions: [...sessions, session],
    );
  }

  /// 结束当前会话（暂停）
  LabClockRecord endCurrentSession() {
    if (sessions.isEmpty) return this;

    final lastIndex = sessions.length - 1;
    final lastSession = sessions[lastIndex];

    // 如果最后一个会话已经结束，不做任何事
    if (lastSession.isCompleted) return this;

    // 结束最后一个会话
    final updatedSessions = List<ClockSession>.from(sessions);
    updatedSessions[lastIndex] = lastSession.end();

    return LabClockRecord(
      id: id,
      clockId: clockId,
      clockTitle: clockTitle,
      startTime: startTime,
      endTime: endTime,
      durationSeconds: durationSeconds,
      completed: completed,
      sessions: updatedSessions,
    );
  }

  /// 获取实际运行时长（秒）
  /// 累计所有已结束会话的时长
  int get actualDuration {
    return sessions.fold(0, (sum, session) => sum + session.duration);
  }

  /// 获取当前会话（用于检查是否在运行中）
  ClockSession? get currentSession {
    if (sessions.isEmpty) return null;
    final last = sessions.last;
    return last.isCompleted ? null : last;
  }

  /// 是否正在运行
  bool get isRunning => currentSession != null;

  /// 获取格式化的时间摘要
  String get summary {
    final running = actualDuration;
    final planned = durationSeconds;

    if (running == 0) return '未开始';
    if (running < 60) return '${running}秒';
    if (running < 3600) return '${(running / 60).toStringAsFixed(1)}分钟';
    return '${(running / 3600).toStringAsFixed(1)}小时';
  }
}
