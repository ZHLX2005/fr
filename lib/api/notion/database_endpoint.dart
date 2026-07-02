import 'dart:convert';

import 'package:http/http.dart' as http;

import 'notion_config.dart';
import 'notion_exception.dart';

/// Notion Database 端点。
///
/// 参考 `.claude/repo/notion-cli/cmd/db.go` 的 GetDatabase / QueryDatabase 实现。
class NotionDatabaseEndpoint {
  final String token;
  final http.Client _client;

  NotionDatabaseEndpoint({required this.token, http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Notion-Version': NotionConfig.version,
        'Content-Type': 'application/json',
      };

  /// 查询数据库 schema（含 properties 定义）。
  ///
  /// 返回的 JSON 中 `properties` 是 `{propertyName: {id, type, ...}}`。
  Future<Map<String, dynamic>> getDatabase(String databaseId) async {
    final resp = await _client.get(
      Uri.parse('${NotionConfig.baseUrl}/v1/databases/$databaseId'),
      headers: _headers,
    );
    _checkError(resp);
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// 按 created_time desc 取 1 个最新 page。空数据库返回 null。
  Future<Map<String, dynamic>?> queryLatestPage(String databaseId) async {
    final body = jsonEncode({
      'sorts': [
        {'timestamp': 'created_time', 'direction': 'descending'},
      ],
      'page_size': 1,
    });
    final resp = await _client.post(
      Uri.parse('${NotionConfig.baseUrl}/v1/databases/$databaseId/query'),
      headers: _headers,
      body: body,
    );
    _checkError(resp);
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = decoded['results'] as List<dynamic>? ?? [];
    if (results.isEmpty) return null;
    return results.first as Map<String, dynamic>;
  }

  /// 列出当前 token 可访问的 database（用于选数据库）。
  Future<List<Map<String, dynamic>>> listDatabases() async {
    final resp = await _client.post(
      Uri.parse('${NotionConfig.baseUrl}/v1/search'),
      headers: _headers,
      body: jsonEncode({
        'filter': {'value': 'database', 'property': 'object'},
        'page_size': 50,
      }),
    );
    _checkError(resp);
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = decoded['results'] as List<dynamic>? ?? [];
    return results.cast<Map<String, dynamic>>();
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
      } catch (_) {
        // 响应不是 JSON — 保留 fallback message
      }
      throw NotionApiException(
        statusCode: resp.statusCode,
        code: code,
        message: message,
      );
    }
  }
}