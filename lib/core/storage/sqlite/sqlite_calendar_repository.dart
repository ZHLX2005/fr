import '../../calendar/domain/calendar_date_utils.dart';
import '../../calendar/domain/calendar_task.dart';
import 'sqlite_migrations.dart';
import 'sqlite_store.dart';

/// 日历任务的数据访问层。
///
/// 所有 SQL 只在这里出现；UI 通过 provider 拿到本类，不接触 `SqliteStore`。
class SqliteCalendarRepository {
  SqliteCalendarRepository(this._store);

  final SqliteStore _store;

  Future<List<CalendarTask>> tasksOnDay(
    DateTime day, {
    bool includeCompleted = true,
  }) async {
    final start = calendarDayStart(day);
    final end = calendarDayEnd(day);
    final rows = await _store.query(
      SqliteMigrations.calendarTasksTable,
      where:
          'start_at < ? AND ((end_at IS NULL AND start_at >= ?) OR end_at > ?)',
      whereArgs: [
        end.millisecondsSinceEpoch,
        start.millisecondsSinceEpoch,
        start.millisecondsSinceEpoch,
      ],
      orderBy: 'all_day DESC, start_at ASC, id ASC',
    );

    final tasks = rows.map(CalendarTask.fromRow).toList();
    if (!includeCompleted) {
      tasks.removeWhere((task) => task.completed);
    }
    tasks.sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      return a.start.compareTo(b.start);
    });
    return tasks;
  }

  /// 月视图的任务点：返回范围内有任务的日期 key（`yyyy-mm-dd`）。
  Future<Set<String>> taskDateKeysBetween(
    DateTime start,
    DateTime end, {
    bool includeCompleted = true,
  }) async {
    final rangeStart = calendarDayStart(start);
    final rangeEnd = calendarDayEnd(end);
    final rangeLast = rangeEnd.subtract(const Duration(days: 1));

    final rows = await _store.query(
      SqliteMigrations.calendarTasksTable,
      columns: const ['start_at', 'end_at', 'all_day', 'completed_at'],
      where: 'start_at < ? AND (end_at IS NULL OR end_at > ?)',
      whereArgs: [
        rangeEnd.millisecondsSinceEpoch,
        rangeStart.millisecondsSinceEpoch,
      ],
    );

    final result = <String>{};
    for (final row in rows) {
      final completedAt = row['completed_at'] as int?;
      if (!includeCompleted && completedAt != null) continue;

      final taskStart = calendarDateOnly(
        DateTime.fromMillisecondsSinceEpoch(row['start_at'] as int),
      );
      final endAt = row['end_at'] as int?;
      DateTime lastDay;
      if (endAt == null) {
        lastDay = taskStart;
      } else {
        final end = DateTime.fromMillisecondsSinceEpoch(endAt);
        final endDay = calendarDateOnly(end);
        final endsAtMidnight =
            end.hour == 0 &&
            end.minute == 0 &&
            end.second == 0 &&
            end.millisecond == 0;
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

    final task = CalendarTask(
      id: 0,
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

    final id = await _store.insert(
      SqliteMigrations.calendarTasksTable,
      task.toRow(includeId: false),
    );
    return task.copyWith(id: id);
  }

  Future<void> update(CalendarTask task) async {
    await _store.update(
      SqliteMigrations.calendarTasksTable,
      task.toRow(includeId: false),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<void> toggleCompleted(CalendarTask task) async {
    final now = DateTime.now();
    final next = task.copyWith(
      completedAt: task.completed ? null : now,
      clearCompletedAt: task.completed,
      updatedAt: now,
    );
    await update(next);
  }

  Future<void> delete(int id) async {
    await _store.delete(
      SqliteMigrations.calendarTasksTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
