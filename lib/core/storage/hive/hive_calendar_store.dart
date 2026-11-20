import 'package:hive_flutter/hive_flutter.dart';

import '../../calendar/domain/calendar_date_utils.dart';
import '../../calendar/domain/calendar_task.dart';
import '../calendar_store.dart';
import 'hive_store.dart';

/// 非 SQLite 平台（Web / Windows / Linux）或 SQLite 打开失败时的本地缓存实现。
///
/// 数据形状与 SQLite 行保持一致（同一套 `CalendarTask.toRow/fromRow`），
/// 因此切换实现不会改变领域模型；UI 始终只拿到 [CalendarTaskRepository]。
class HiveCalendarStore {
  HiveCalendarStore._(Box<dynamic> tasks, Box<dynamic> settings)
    : calendar = HiveCalendarRepository(tasks),
      settings = HiveSettingsRepository(settings);

  final HiveCalendarRepository calendar;
  final HiveSettingsRepository settings;

  static Future<HiveCalendarStore> open() async {
    final tasks = await HiveStore.instance.openUntyped('calendar_tasks_v1');
    final settings =
        await HiveStore.instance.openUntyped('calendar_settings_v1');
    return HiveCalendarStore._(tasks, settings);
  }
}

class HiveCalendarRepository implements CalendarTaskRepository {
  HiveCalendarRepository(this._box);

  final Box<dynamic> _box;

  List<CalendarTask> _allTasks() {
    final tasks = <CalendarTask>[];
    for (final value in _box.values) {
      if (value is! Map) continue;
      final row = <String, Object?>{};
      for (final entry in value.entries) {
        row['${entry.key}'] = entry.value;
      }
      try {
        tasks.add(CalendarTask.fromRow(row));
      } catch (_) {
        // 旧缓存字段不完整时跳过，不让单条坏数据拖垮整页。
      }
    }
    return tasks;
  }

  @override
  Future<List<CalendarTask>> tasksOnDay(
    DateTime day, {
    bool includeCompleted = true,
  }) async {
    final start = calendarDayStart(day);
    final end = calendarDayEnd(day);
    final tasks = _allTasks().where((task) {
      if (!includeCompleted && task.completed) return false;
      final taskStart = task.start;
      final taskEnd = task.end;
      final overlaps = taskStart.isBefore(end) &&
          (taskEnd == null
              ? !taskStart.isBefore(start)
              : taskEnd.isAfter(start));
      return overlaps;
    }).toList();

    tasks.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      return a.start.compareTo(b.start);
    });
    return tasks;
  }

  @override
  Future<Set<String>> taskDateKeysBetween(
    DateTime start,
    DateTime end, {
    bool includeCompleted = true,
  }) async {
    final rangeStart = calendarDayStart(start);
    final rangeEnd = calendarDayEnd(end);
    final rangeLast = rangeEnd.subtract(const Duration(days: 1));
    final result = <String>{};

    for (final task in _allTasks()) {
      if (!includeCompleted && task.completed) continue;
      final taskStart = calendarDateOnly(task.start);
      final endAt = task.end;
      DateTime lastDay;
      if (endAt == null) {
        lastDay = taskStart;
      } else {
        final endDay = calendarDateOnly(endAt);
        final endsAtMidnight =
            endAt.hour == 0 &&
            endAt.minute == 0 &&
            endAt.second == 0 &&
            endAt.millisecond == 0;
        lastDay = endsAtMidnight
            ? endDay.subtract(const Duration(days: 1))
            : endDay;
      }

      var cursor = calendarMaxDate(taskStart, rangeStart);
      final limit = calendarMinDate(lastDay, rangeLast);
      while (!cursor.isAfter(limit)) {
        result.add(calendarDateKey(cursor));
        cursor = cursor.add(const Duration(days: 1));
      }
    }
    return result;
  }

  @override
  Future<CalendarTask> create(CalendarTaskDraft draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) {
      throw ArgumentError.value(draft.title, 'title', '任务标题不能为空');
    }

    final now = DateTime.now();
    final start = draft.allDay ? calendarDayStart(draft.start) : draft.start;
    final end =
        draft.end ??
        (draft.allDay
            ? start.add(const Duration(days: 1))
            : start.add(const Duration(hours: 1)));

    var nextId = 1;
    for (final key in _box.keys) {
      if (key is int && key >= nextId) nextId = key + 1;
    }

    final task = CalendarTask(
      id: nextId,
      title: title,
      notes: draft.notes?.trim().isEmpty == true ? null : draft.notes?.trim(),
      start: start,
      end: end,
      allDay: draft.allDay,
      priority: draft.priority,
      colorValue: draft.colorValue,
      createdAt: now,
      updatedAt: now,
    );
    await _box.put(task.id, task.toRow());
    return task;
  }

  @override
  Future<void> update(CalendarTask task) async {
    await _box.put(task.id, task.toRow());
  }

  @override
  Future<void> toggleCompleted(CalendarTask task) async {
    final now = DateTime.now();
    final next = task.copyWith(
      completedAt: task.completed ? null : now,
      clearCompletedAt: task.completed,
      updatedAt: now,
    );
    await update(next);
  }

  @override
  Future<void> delete(int id) async {
    await _box.delete(id);
  }
}

class HiveSettingsRepository implements KeyValueRepository {
  HiveSettingsRepository(this._box);

  final Box<dynamic> _box;

  @override
  Future<String?> read(String key) async {
    final value = _box.get(key);
    return value is String ? value : null;
  }

  @override
  Future<void> write(String key, String value) async {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', '设置键不能为空');
    }
    await _box.put(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _box.delete(key);
  }
}
