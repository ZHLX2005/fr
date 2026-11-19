import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'sqlite_migrations.dart';

/// 低层 SQLite 访问封装。
///
/// **本类不对外导出**：外部只能拿到 [SqliteStorage] 暴露的 Repository。
/// 这里刻意不提供 `Database` getter、不暴露 `openDatabase` 的返回对象，
/// 所有读写都必须经过下面这些内部函数，避免 feature 代码持有全局数据库句柄。
class SqliteStore {
  SqliteStore._(this._db, this.databasePath);

  final Database _db;

  /// 当前数据库文件的绝对路径（仅用于诊断/日志，不用于访问）。
  final String databasePath;

  static Future<SqliteStore> open({String? path}) async {
    final dbPath =
        path ?? p.join(await getDatabasesPath(), SqliteMigrations.databaseName);

    final db = await openDatabase(
      dbPath,
      version: SqliteMigrations.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA busy_timeout = 5000');
      },
      onCreate: SqliteMigrations.onCreate,
      onUpgrade: SqliteMigrations.onUpgrade,
    );

    return SqliteStore._(db, dbPath);
  }

  Future<List<Map<String, Object?>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    return _db.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> insert(String table, Map<String, Object?> values) {
    return _db.insert(table, values);
  }

  /// 覆盖写入（主键冲突时替换整行）。
  Future<int> replace(String table, Map<String, Object?> values) {
    return _db.insert(
      table,
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    return _db.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    return _db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<T> transaction<T>(Future<T> Function(SqliteTransaction tx) action) {
    return _db.transaction((tx) async {
      return action(SqliteTransaction._(tx));
    });
  }

  Future<void> close() => _db.close();
}

/// 事务内的访问器。
///
/// 只暴露与 [SqliteStore] 相同的内部函数，不把 sqflite 的 `Transaction`
/// 交给调用方，避免事务对象被带出作用域后继续使用。
class SqliteTransaction {
  SqliteTransaction._(this._tx);

  final Transaction _tx;

  Future<List<Map<String, Object?>>> query(
    String table, {
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    return _tx.query(
      table,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> insert(String table, Map<String, Object?> values) {
    return _tx.insert(table, values);
  }

  Future<int> replace(String table, Map<String, Object?> values) {
    return _tx.insert(
      table,
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
  }) {
    return _tx.update(table, values, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    return _tx.delete(table, where: where, whereArgs: whereArgs);
  }
}
