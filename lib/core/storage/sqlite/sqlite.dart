/// SQLite 模块的唯一对外入口。
///
/// 约束：
/// - 只有本目录内部可以 import `package:sqflite`；
/// - 外部只能通过 [SqliteStorage] / Repository / provider 访问数据；
/// - 不允许持有 `Database`，也不允许在 feature 代码里 `openDatabase`。
///
/// 这个约束由 `test/core/storage/sqlite/sqlite_access_guard_test.dart` 守门。
library;

export 'sqlite_calendar_repository.dart';
export 'sqlite_providers.dart';
export 'sqlite_settings_repository.dart';
export 'sqlite_storage.dart';
