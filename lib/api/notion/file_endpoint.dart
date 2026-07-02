import 'dart:convert';

import 'package:http/http.dart' as http;

import 'notion_config.dart';
import 'notion_exception.dart';

/// Notion File Upload 端点 — 三步上传图床。
///
/// 参考 `.claude/repo/notion-cli/cmd/file.go` 的 `uploadFromSource` 实现：
///   1. POST /v1/file_uploads — 拿到 upload_id
///   2. POST /v1/file_uploads/{id}/send — multipart 上传字节
///   3. PATCH /v1/blocks/{page_id}/children — 把 image block 追加到 page
class NotionFileEndpoint {
  final String token;
  final http.Client _client;

  NotionFileEndpoint({required this.token, http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> get _jsonHeaders => {
        'Authorization': 'Bearer $token',
        'Notion-Version': NotionConfig.version,
        'Content-Type': 'application/json',
      };

  /// Step 1: 创建一个 file_upload 对象，拿到 upload_id。
  ///
  /// [contentLength] 必须准确，否则 Notion 端 multipart 解析会失败。
  /// 当前实现只用 single_part 模式（< 5MB 单文件场景）。
  Future<String> createFileUpload({
    required String filename,
    required String contentType,
    required int contentLength,
  }) async {
    final body = jsonEncode({
      'filename': filename,
      'content_type': contentType,
      'content_length': contentLength,
      'mode': 'single_part',
    });
    final resp = await _client.post(
      Uri.parse('${NotionConfig.baseUrl}/v1/file_uploads'),
      headers: _jsonHeaders,
      body: body,
    );
    _checkError(resp);
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final uploadId = decoded['id'] as String?;
    if (uploadId == null || uploadId.isEmpty) {
      throw NotionApiException(
        statusCode: resp.statusCode,
        code: 'no_upload_id',
        message: 'Notion 返回的 file_upload 缺少 id 字段',
      );
    }
    return uploadId;
  }

  /// Step 2: 把文件字节通过 multipart/form-data 发送到 file_upload。
  ///
  /// Notion 要求 form 字段名固定为 `file`，filename 用真实文件名。
  /// `http.MultipartFile.fromBytes` 接收 `contentType` 参数（需要
  /// `http_parser` 的 MediaType）；但项目里 `http_parser` 只是 http 的
  /// 传递依赖，没有显式 export。所以这里直接用 StreamedRequest + 手工
  /// multipart body — 绕开 MediaType 依赖，依赖最小。
  Future<void> sendFileContent({
    required String uploadId,
    required String filename,
    required String contentType,
    required List<int> bytes,
  }) async {
    final url =
        Uri.parse('${NotionConfig.baseUrl}/v1/file_uploads/$uploadId/send');

    // 手工构造 multipart body，避免依赖 http_parser 的 MediaType。
    final boundary = '----notionUpload${DateTime.now().microsecondsSinceEpoch}';
    final filenameEscaped = filename.replaceAll('"', '\\"');
    final bodyBytes = <int>[];
    void writeString(String s) {
      bodyBytes.addAll(utf8.encode(s));
    }

    writeString('--$boundary\r\n');
    writeString(
      'Content-Disposition: form-data; name="file"; filename="$filenameEscaped"\r\n',
    );
    writeString('Content-Type: $contentType\r\n\r\n');
    bodyBytes.addAll(bytes);
    writeString('\r\n--$boundary--\r\n');

    final resp = await _client.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Notion-Version': NotionConfig.version,
        'Content-Type': 'multipart/form-data; boundary=$boundary',
      },
      body: bodyBytes,
    );
    _checkError(resp);
  }

  /// Step 3: 把 image block 追加到 page 末尾。
  ///
  /// Notion image block 的 source.type 必须是 `file_upload`，指向 Step 1
  /// 创建的 upload_id — Notion 会在 attach 时把 upload 转成正式 file URL。
  Future<Map<String, dynamic>> appendImageBlock({
    required String pageId,
    required String uploadId,
  }) async {
    final body = jsonEncode({
      'children': [
        {
          'object': 'block',
          'type': 'image',
          'image': {
            'type': 'file_upload',
            'file_upload': {'id': uploadId},
          },
        },
      ],
    });
    final resp = await _client.patch(
      Uri.parse('${NotionConfig.baseUrl}/v1/blocks/$pageId/children'),
      headers: _jsonHeaders,
      body: body,
    );
    _checkError(resp);
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = decoded['results'] as List<dynamic>? ?? [];
    if (results.isEmpty) {
      throw NotionApiException(
        statusCode: resp.statusCode,
        code: 'no_block_returned',
        message: 'appendImageBlock 后未返回 block',
      );
    }
    return results.first as Map<String, dynamic>;
  }

  /// 一站式：3 步链式调用 — 拍照后传 (imageBytes, filename) 即可。
  ///
  /// 默认 contentType 是 `image/jpeg`，image_picker 拍照结果就是 JPEG。
  Future<Map<String, dynamic>> uploadImageToPage({
    required String pageId,
    required List<int> imageBytes,
    required String filename,
    String contentType = 'image/jpeg',
  }) async {
    final uploadId = await createFileUpload(
      filename: filename,
      contentType: contentType,
      contentLength: imageBytes.length,
    );
    await sendFileContent(
      uploadId: uploadId,
      filename: filename,
      contentType: contentType,
      bytes: imageBytes,
    );
    return appendImageBlock(pageId: pageId, uploadId: uploadId);
  }

  void dispose() => _client.close();

  void _checkError(http.Response resp) {
    if (resp.statusCode >= 400) {
      String code = 'unknown';
      String message = 'HTTP ${resp.statusCode}';
      try {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        code = body['code'] as String? ?? code;
        message = body['message'] as String? ?? message;
      } catch (_) {}
      throw NotionApiException(
        statusCode: resp.statusCode,
        code: code,
        message: message,
      );
    }
  }
}