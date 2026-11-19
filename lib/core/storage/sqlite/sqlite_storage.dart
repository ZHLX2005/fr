import 'sqlite_calendar_repository.dart';
import 'sqlite_settings_repository.dart';
import 'sqlite_store.dart';

/// 应用 SQLite 存储的**唯一对外入口**。
///
/// 生命周期由组合根（`main.dart`）持有，并通过 Riverpod provider 注入；
/// 本类不提供全局单例，也不向外暴露低层 [SqliteStore]。
class SqliteStorage {
  SqliteStorage._(this._store)
    : settings = SqliteSettingsRepository(_store),
      calendar = SqliteCalendarRepository(_store);

  final SqliteStore _store;

  /// 设置类数据访问层。
  final SqliteSettingsRepository settings;

  /// 日历任务数据访问层。
  final SqliteCalendarRepository calendar;

  String get databasePath => _store.databasePath;

  /// 打开数据库并跑完迁移。
  ///
  /// [path] 仅供测试或特殊环境指定；正常运行时走平台默认 databases 目录。
  static Future<SqliteStorage> open({String? path}) async {
    final store = await SqliteStore.open(path: path);
    return SqliteStorage._(store);
  }

  Future<void> close() => _store.close();
}
