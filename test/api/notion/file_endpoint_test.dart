// ignore_for_file: avoid_print
// 本文件是诊断 / e2e 链路脚本，控制台输出即测试结果本身，
// 不属于 avoid_print 所指的「生产代码」。
// NotionFileEndpoint 链路测试 — 验证 3 步上传图床的完整链路。
//
//   1. createFileUpload — 拿 upload_id
//   2. sendFileContent — multipart 发送字节
//   3. appendImageBlock — 把 image block 追加到指定 page 末尾
//
// 验证：
//   - 3 步分别能跑通
//   - 链式 uploadImageToPage 一站式也能跑通
//   - image block 返回后 type=image 且 file.source 存在

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/api/notion/file_endpoint.dart';
import 'package:xiaodouzi_fr/api/notion/database_endpoint.dart';

import 'notion_test_helpers.dart';

void main() {
  group('NotionFileEndpoint', () {
    late NotionFileEndpoint fileEndpoint;
    late NotionDatabaseEndpoint dbEndpoint;

    setUpAll(() {
      print('--- ${summarizeCreds()} ---');
      final token = requireTestToken();
      fileEndpoint = NotionFileEndpoint(token: token);
      dbEndpoint = NotionDatabaseEndpoint(token: token);
    });

    test('createFileUpload 拿到 upload_id', () async {
      final bytes = readTestPngBytes();

      final uploadId = await fileEndpoint.createFileUpload(
        filename: 'test_${DateTime.now().millisecondsSinceEpoch}.png',
        contentType: 'image/png',
        contentLength: bytes.length,
      );

      expect(uploadId, isNotEmpty);
      expect(uploadId.length, 36);
      print('--- upload_id = $uploadId ---');
    });

    test('完整链路：upload → send → append 到最新 page 末尾', () async {
      // 1. 先找到最新 page
      final latestPage = await dbEndpoint.queryLatestPage(testDatabaseId);
      expect(latestPage, isNotNull);
      final pageId = latestPage!['id'] as String;

      // 2. 一站式上传
      final bytes = readTestPngBytes();
      final filename =
          'test_${DateTime.now().millisecondsSinceEpoch}.png';

      final block = await fileEndpoint.uploadImageToPage(
        pageId: pageId,
        imageBytes: bytes,
        filename: filename,
        contentType: 'image/png',
      );

      // 3. 验证返回的 block 是 image 类型
      expect(block['object'], 'block');
      expect(block['type'], 'image');
      expect(block['image'], isNotNull);
      expect(block['image']['type'], 'file',
          reason: 'append 后 Notion 会把 file_upload 转成 file source');

      print('--- appended block id = ${block['id']} ---');
    });

    test('无效 token 的 createFileUpload 应该抛 NotionApiException', () async {
      // 用一个格式错误的 token（不是以 ntn_ 开头，长度也不对）— Notion
      // 会立刻 401 unauthorized。
      final badEndpoint = NotionFileEndpoint(token: 'invalid_token_xxx');
      final bytes = readTestPngBytes();
      await expectLater(
        badEndpoint.createFileUpload(
          filename: 'should_fail.png',
          contentType: 'image/png',
          contentLength: bytes.length,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}