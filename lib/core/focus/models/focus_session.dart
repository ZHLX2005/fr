/// 专注会话模型
class FocusSession {
  final String id;
  final String subjectId;
  final int durationMinutes; // 专注时长（分钟）
  final DateTime startTime;
  final DateTime endTime;
  final FocusMode mode; // 专注模式
  final String? note; // 心流感悟

  FocusSession({
    required this.id,
    required this.subjectId,
    required this.durationMinutes,
    required this.startTime,
    required this.endTime,
    required this.mode,
    this.note,
  });

  /// 是否为番茄钟模式
  bool get isPomodoro => mode == FocusMode.pomodoro;

  /// 是否为自由计时模式
  bool get isFreeTime => mode == FocusMode.freeTime;

  FocusSession copyWith({
    String? id,
    String? subjectId,
    int? durationMinutes,
    DateTime? startTime,
    DateTime? endTime,
    FocusMode? mode,
    String? note,
  }) {
    return FocusSession(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      mode: mode ?? this.mode,
      note: note ?? this.note,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subjectId': subjectId,
      'durationMinutes': durationMinutes,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'mode': mode.index,
      'note': note,
    };
  }

  /// 从JSON转换
  factory FocusSession.fromJson(Map<String, dynamic> json) {
    return FocusSession(
      id: json['id'] as String,
      subjectId: json['subjectId'] as String,
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
