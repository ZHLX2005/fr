import 'package:flutter/foundation.dart';

/// 日历任务领域模型。
///
/// 数据层与 UI 层共用；不依赖 sqflite，也不持有数据库句柄。
@immutable
class CalendarTask {
  const CalendarTask({
    required this.id,
    required this.title,
    required this.start,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.end,
    this.allDay = false,
    this.completedAt,
    this.priority = 0,
    this.colorValue,
  });

  final int id;
  final String title;
  final String? notes;

  /// 本地时间；全天任务为当天 00:00。
  final DateTime start;

  /// 结束时间。全天任务通常为次日 00:00；单点任务可为空。
  final DateTime? end;

  final bool allDay;

  /// 非空即已完成。
  final DateTime? completedAt;

  /// 0 = 普通；数值越大优先级越高。
  final int priority;

  /// ARGB 颜色值；null 时 UI 用主题强调色。
  final int? colorValue;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get completed => completedAt != null;

  CalendarTask copyWith({
    int? id,
    String? title,
    String? notes,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    int? priority,
    int? colorValue,
    bool clearColorValue = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CalendarTask(
      id: id ?? this.id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      start: start ?? this.start,
      end: end ?? this.end,
      allDay: allDay ?? this.allDay,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      priority: priority ?? this.priority,
      colorValue: clearColorValue ? null : (colorValue ?? this.colorValue),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory CalendarTask.fromRow(Map<String, Object?> row) {
    final startAt = row['start_at'] as int;
    final endAt = row['end_at'] as int?;
    final completedAt = row['completed_at'] as int?;

    return CalendarTask(
      id: row['id'] as int,
      title: row['title'] as String,
      notes: row['notes'] as String?,
      start: DateTime.fromMillisecondsSinceEpoch(startAt),
      end: endAt == null ? null : DateTime.fromMillisecondsSinceEpoch(endAt),
      allDay: (row['all_day'] as int? ?? 0) != 0,
      completedAt: completedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(completedAt),
      priority: row['priority'] as int? ?? 0,
      colorValue: row['color'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  Map<String, Object?> toRow({bool includeId = true}) {
    return {
      if (includeId) 'id': id,
      'title': title,
      'notes': notes,
      'start_at': start.millisecondsSinceEpoch,
      'end_at': end?.millisecondsSinceEpoch,
      'all_day': allDay ? 1 : 0,
      'completed_at': completedAt?.millisecondsSinceEpoch,
      'priority': priority,
      'color': colorValue,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }
}

/// 新建任务时的输入；由 UI 的添加任务表单产出。
@immutable
class CalendarTaskDraft {
  const CalendarTaskDraft({
    required this.title,
    required this.start,
    this.notes,
    this.end,
    this.allDay = false,
    this.priority = 0,
    this.colorValue,
  });

  final String title;
  final String? notes;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final int priority;
  final int? colorValue;
}
