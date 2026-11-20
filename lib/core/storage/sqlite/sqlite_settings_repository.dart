import '../calendar_store.dart';
import 'sqlite_migrations.dart';
import 'sqlite_store.dart';

/// 应用级设置访问层。
///
/// 所有 SQL 都收口在这里：外部只看到 `read/write/remove/readAll/clear`，
/// 拿不到 `SqliteStore`，更拿不到 sqflite 的 `Database`。
class SqliteSettingsRepository implements KeyValueRepository {
  SqliteSettingsRepository(this._store);

  final SqliteStore _store;

  @override
  Future<String?> read(String key) async {
    final rows = await _store.query(
      SqliteMigrations.appSettingsTable,
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  @override
  Future<void> write(String key, String value) async {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', '设置键不能为空');
    }
    await _store.replace(SqliteMigrations.appSettingsTable, {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> remove(String key) async {
    await _store.delete(
      SqliteMigrations.appSettingsTable,
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  Future<Map<String, String>> readAll() async {
    final rows = await _store.query(
      SqliteMigrations.appSettingsTable,
      orderBy: 'key ASC',
    );
    return {
      for (final row in rows) row['key']! as String: row['value']! as String,
    };
  }

  Future<void> clear() async {
    await _store.delete(SqliteMigrations.appSettingsTable);
  }
}
