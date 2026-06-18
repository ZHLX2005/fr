import 'dart:convert';
import 'dart:io';

import 'toml_codec.dart';

/// 一次性迁移：把 `notes/` 下的老 `*.json` 笔记转写为 `*.toml`。
///
/// 设计要点：
/// - **幂等**：只有写 `.toml` 成功后才删 `.json`；中断后下次重试安全。
/// - **容错**：单个文件解析失败不中断整体，保留坏 `.json` + 打印日志。
/// - **无状态触发**：调用方负责"只跑一次"的守护（见 [NoteRepository]）。
/// - **纯 Map 转换**：JSON Map → TOML Map，不经过 Block 领域对象。
class NoteMigration {
  final TomlCodec _tomlCodec;

  NoteMigration(this._tomlCodec);

  /// 扫描 [notesDir] 下的 `*.json`，逐个迁移为同名 `.toml`。
  ///
  /// 返回成功迁移的文件数（0 = 无需迁移）。
  Future<int> migrateIfNeeded(Directory notesDir) async {
    if (!await notesDir.exists()) return 0;

    int migrated = 0;
    final jsonFiles = notesDir
        .listSync(followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'));

    for (final jsonFile in jsonFiles) {
      final ok = await _migrateOne(jsonFile);
      if (ok) migrated++;
    }
    return migrated;
  }

  /// 迁移单个文件。成功 = 写了 `.toml` 且删了 `.json`。
  Future<bool> _migrateOne(File jsonFile) async {
    final tomlPath =
        '${jsonFile.path.substring(0, jsonFile.path.length - 5)}.toml';
    final tomlFile = File(tomlPath);

    try {
      final raw = await jsonFile.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final tomlString = _tomlCodec.encode(map);
      await tomlFile.writeAsString(tomlString);
      await jsonFile.delete();
      return true;
    } catch (e) {
      // 保留坏文件，仅日志，不抛——下次启动可重试或人工介入。
      // ignore: avoid_print
      print('[NoteMigration] skip ${jsonFile.path}: $e');
      return false;
    }
  }
}
