// Notion API 测试共享工具。
//
// 跑法：
//   flutter test test/api/notion/
//
// 自定义 token / database_id：
//   NOTION_TOKEN=ntn_xxx NOTION_DB_ID=38b550be-... flutter test test/api/notion/
//
// 注意：默认 token 留空 — CI / 公共仓库环境下必须显式传 NOTION_TOKEN，
// 否则会跳过。生产代码不要硬编码 token。

import 'dart:io';

/// 测试用 Notion Integration Token — 必须通过环境变量 NOTION_TOKEN 传入。
///
/// 留空默认值是有意为之：避免真实 token 误入 git 历史。开发机本地
/// `export NOTION_TOKEN=...` 后再 `flutter test` 即可。
const String testToken = String.fromEnvironment(
  'NOTION_TOKEN',
  defaultValue: '',
);

/// 默认测试数据库 ID — 用户的 "me" 数据库。
const String testDatabaseId = String.fromEnvironment(
  'NOTION_DB_ID',
  defaultValue: '38b550be-064e-801c-b944-f437c9a65f8a',
);

/// 如果 testToken 为空直接抛错，提示用户先设置环境变量。
String requireTestToken() {
  if (testToken.isEmpty) {
    throw StateError(
      'testToken 为空。请用环境变量传入：\n'
      '  NOTION_TOKEN=ntn_xxx flutter test test/api/notion/\n'
      '或在 IDE 里设置 Run Configuration 的 --dart-define=NOTION_TOKEN=ntn_xxx',
    );
  }
  return testToken;
}

/// 读取 test/fixtures/test_image.png 的字节，供 File 上传测试用。
///
/// 该 PNG 是 100x100 红色、517 字节，已在 task T1 阶段生成。
List<int> readTestPngBytes() {
  final file = File('test/fixtures/test_image.png');
  if (!file.existsSync()) {
    throw StateError(
      'test/fixtures/test_image.png 不存在 — 请先生成（见 plan 步骤 T1）',
    );
  }
  return file.readAsBytesSync();
}

/// 打印当前测试用的 token / db（脱敏）— 调试用。
String summarizeCreds() {
  if (testToken.isEmpty) return 'token=<未设置> db=$testDatabaseId';
  final tokenMask = testToken.length > 8
      ? '${testToken.substring(0, 6)}...${testToken.substring(testToken.length - 4)}'
      : '***';
  return 'token=$tokenMask db=$testDatabaseId';
}