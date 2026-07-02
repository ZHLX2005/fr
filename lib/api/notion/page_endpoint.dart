import 'dart:convert';

import 'package:http/http.dart' as http;

import 'notion_config.dart';
import 'notion_exception.dart';

/// Notion Page 端点 — 创建 page（按数据库模板）。
///
/// 参考 `.claude/repo/notion-cli/cmd/db.go` 的 `dbAddCmd` 实现。
class NotionPageEndpoint {
  final String token;
  final http.Client _client;

  NotionPageEndpoint({required this.token, http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Notion-Version': NotionConfig.version,
        'Content-Type': 'application/json',
      };

  /// 在指定数据库下创建新 page，标题用 ISO 时间戳 mention.date。
  ///
  /// 复用现有 "me" 数据库的标题风格（date mention + 一个空格）。
  /// [titlePropertyName] 默认 `"名称"` — 与用户 me 数据库 schema 对齐。
  Future<Map<String, dynamic>> createPageWithTimestamp({
    required String databaseId,
    String? titlePropertyName,
  }) async {
    final propertyName = titlePropertyName ?? '名称';
    final nowIso = DateTime.now().toIso8601String();
    final body = jsonEncode({
      'parent': {'database_id': databaseId},
      'properties': {
        propertyName: {
          'title': [
            {
              'type': 'mention',
              'mention': {
                'type': 'date',
                'date': {'start': nowIso},
              },
            },
            {'type': 'text', 'text': {'content': ' '}},
          ],
        },
      },
    });
    final resp = await _client.post(
      Uri.parse('${NotionConfig.baseUrl}/v1/pages'),
      headers: _headers,
      body: body,
    );
    _checkError(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
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