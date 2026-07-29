/// 专注会话模型
class FocusSession {
  final String id;
  final int durationMinutes;
  final DateTime startTime;
  final DateTime endTime;
  final FocusMode mode;
  final String? note;

  FocusSession({
    required this.id,
    required this.durationMinutes,
    required this.startTime,
    required this.endTime,
    required this.mode,
    this.note,
  });

  bool get isPomodoro => mode == FocusMode.pomodoro;
  bool get isFreeTime => mode == FocusMode.freeTime;

  FocusSession copyWith({
    String? id,
    int? durationMinutes,
    DateTime? startTime,
    DateTime? endTime,
    FocusMode? mode,
    String? note,
  }) {
    return FocusSession(
      id: id ?? this.id,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      mode: mode ?? this.mode,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'durationMinutes': durationMinutes,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'mode': mode.index,
        'note': note,
      };

  factory FocusSession.fromJson(Map<String, dynamic> json) {
    return FocusSession(
      id: json['id'] as String,
      durationMinutes: json['durationMinutes'] as int,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      mode: FocusMode.values[json['mode'] as int],
      note: json['note'] as String?,
    );
  }
}

/// 专注模式枚举
enum FocusMode {
  pomodoro, // 番茄钟（25分钟工作+5分钟休息）
  freeTime, // 自由计时（累加学时）
}

extension FocusModeExtension on FocusMode {
  String get label {
    switch (this) {
      case FocusMode.pomodoro:
        return '番茄钟';
      case FocusMode.freeTime:
        return '自由计时';
    }
  }

  String get description {
    switch (this) {
      case FocusMode.pomodoro:
        return '25分钟专注 + 5分钟休息';
      case FocusMode.freeTime:
        return '自由记录学习时长';
    }
  }
}
