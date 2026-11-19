import 'package:sqflite/sqflite.dart';

/// SQLite 的库名、表名与 schema 版本。
///
/// **只允许本模块内部改这里**：新增表/字段时，把 [version] +1，并在
/// [_migrate] 里追加一个新的 `case`；已经发布过的迁移分支不要再改。
class SqliteMigrations {
  SqliteMigrations._();

  /// 数据库文件放在平台默认 databases 目录下。
  static const String databaseName = 'xiaodouzi_fr.sqlite';

  /// 当前 schema 版本。每次结构变更 +1。
  static const int version = 2;

  /// 应用级键值设置表（后续设置项统一走 SqliteSettingsRepository）。
  static const String appSettingsTable = 'app_settings';

  /// 日历任务表。
  static const String calendarTasksTable = 'calendar_tasks';

  static Future<void> onCreate(Database db, int version) =>
      _migrate(db, from: 0, to: version);

  static Future<void> onUpgrade(Database db, int oldVersion, int newVersion) =>
      _migrate(db, from: oldVersion, to: newVersion);

  static Future<void> _migrate(
    Database db, {
    required int from,
    required int to,
  }) async {
    for (var target = from + 1; target <= to; target++) {
      switch (target) {
        case 1:
          await db.execute('''
CREATE TABLE IF NOT EXISTS $appSettingsTable (
  key TEXT PRIMARY KEY NOT NULL CHECK (length(key) > 0),
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
        case 2:
          await db.execute('''
CREATE TABLE IF NOT EXISTS $calendarTasksTable (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL CHECK (length(title) > 0),
  notes TEXT,
  start_at INTEGER NOT NULL,
  end_at INTEGER,
  all_day INTEGER NOT NULL DEFAULT 0 CHECK (all_day IN (0, 1)),
  completed_at INTEGER,
  priority INTEGER NOT NULL DEFAULT 0,
  color INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_calendar_tasks_range '
            'ON $calendarTasksTable (start_at, end_at)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_calendar_tasks_completed '
            'ON $calendarTasksTable (completed_at)',
          );
        default:
          throw StateError('未知的 SQLite 迁移版本: $target');
      }
    }
  }
}
