import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../calendar_store.dart';
import 'sqlite_storage.dart';

/// SQLite 存储实例。
///
/// 默认 `null`（Web / 未启用平台），由组合根在数据库打开成功后覆盖。
/// feature 代码只允许读这个 provider，不允许自己 `openDatabase`。
final sqliteStorageProvider = Provider<SqliteStorage?>((ref) => null);

/// 设置访问层。数据库不可用时为 `null`，调用方必须显式处理。
///
/// 对外暴露领域契约而不是 [SqliteSettingsRepository]，这样页面和测试都
/// 不需要认识 SQLite 类型，也不会绕开仓储直接碰数据库。
final sqliteSettingsRepositoryProvider = Provider<KeyValueRepository?>((ref) {
  return ref.watch(sqliteStorageProvider)?.settings;
});

/// 日历任务访问层。数据库不可用时为 `null`，页面须显式处理空状态。
final sqliteCalendarRepositoryProvider =
    Provider<CalendarTaskRepository?>((ref) {
  return ref.watch(sqliteStorageProvider)?.calendar;
});
