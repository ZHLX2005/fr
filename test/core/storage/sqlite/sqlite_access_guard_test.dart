import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 架构守门：SQLite 只能从 `lib/core/storage/sqlite/` 内部访问。
///
/// 这不是功能测试，而是防止后续 feature 代码为了方便直接 import sqflite、
/// 持有 `Database` 或自己 `openDatabase`，把封装层绕过去。
void main() {
  test('SQLite 访问只允许经过 core/storage/sqlite 的内部函数', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: '测试需在项目根目录运行');

    final violations = <String>[];

    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final path = entity.path.replaceAll('\\', '/');
      final isSqliteModule = path.startsWith('lib/core/storage/sqlite/');
      if (isSqliteModule) continue;

      final source = entity.readAsStringSync();

      if (source.contains('package:sqflite/')) {
        violations.add('$path: 直接 import package:sqflite');
      }
      if (RegExp(r'\bSqliteStore\b').hasMatch(source)) {
        violations.add('$path: 直接引用 SqliteStore');
      }
      if (RegExp(r'\bSqliteTransaction\b').hasMatch(source)) {
        violations.add('$path: 直接引用 SqliteTransaction');
      }
      if (RegExp(r'\bopenDatabase\s*\(').hasMatch(source)) {
        violations.add('$path: 直接调用 openDatabase');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'SQLite 访问必须走 core/storage/sqlite 的 Repository：\n'
          '${violations.join('\n')}',
    );
  });
}
