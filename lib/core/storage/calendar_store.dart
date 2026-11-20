import '../calendar/domain/calendar_task.dart';

/// 日历任务存储的领域契约。
///
/// UI 只依赖这些方法，不关心底层是 SQLite 还是 Hive；具体实现由存储模块
/// 自己持有数据库/box 句柄，禁止把底层对象泄漏到页面。
abstract interface class CalendarTaskRepository {
  Future<List<CalendarTask>> tasksOnDay(
    DateTime day, {
    bool includeCompleted = true,
  });

  Future<Set<String>> taskDateKeysBetween(
    DateTime start,
    DateTime end, {
    bool includeCompleted = true,
  });

  Future<CalendarTask> create(CalendarTaskDraft draft);

  Future<void> update(CalendarTask task);

  Future<void> toggleCompleted(CalendarTask task);

  Future<void> delete(int id);
}

/// 轻量键值设置契约（日历视图偏好、周起始日等）。
abstract interface class KeyValueRepository {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> remove(String key);
}
