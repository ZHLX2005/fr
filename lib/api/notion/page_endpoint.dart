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
  ///
  /// **时区处理（关键，已实测验证）**：
  /// 用户在北京（UTC+8）期望 date mention 显示**当前北京时间**。
  /// 已通过 test/api/notion/notion_timezone_real_test.dart 验证：
  ///   - 无时区 `2026-07-02T17:57:00` → 显示 `17:57+00:00` ❌
  ///   - `-08:00` → 显示 `17:57-08:00`（Notion 不偏移）❌
  ///   - `+08:00` → 显示 `July 2, 2026 5:57 PM` ✅ = 当前北京时间
  ///
  /// 结论：必须在 ISO 字符串后加 `+08:00` 后缀（中国用户）。
  /// 未来支持其他时区：把 `_localTzOffset` 改成动态读取
  /// `DateTime.now().timeZoneOffset`。
  Future<Map<String, dynamic>> createPageWithTimestamp({
    required String databaseId,
    String? titlePropertyName,
  }) async {
    final propertyName = titlePropertyName ?? '名称';
    final nowLocal = DateTime.now();
    final localIsoNoTz = nowLocal.toIso8601String();
    // 当前固定为东八区（北京时间）。其他时区扩展时改成
    // `nowLocal.timeZoneOffset` 动态算。
    const localTzOffset = '+08:00';
    final notionDateStart = '$localIsoNoTz$localTzOffset';
    final body = jsonEncode({
      'parent': {'database_id': databaseId},
      'properties': {
        propertyName: {
          'title': [
            {
              'type': 'mention',
              'mention': {
                'type': 'date',
                'date': {'start': notionDateStart},
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

  /// 从 page JSON 中提取可读的 title 文本。
  ///
  /// title 是 rich_text array，可能含多种类型：
  ///   - type=text → text.content
  ///   - type=mention → mention.date.start（取 ISO 字符串直接显示）
  ///
  /// 返回 plain_text 拼接后的字符串，作为 user-facing 展示用。
  static String extractTitle(Map<String, dynamic> pageJson) {
    final props = pageJson['properties'] as Map<String, dynamic>?;
    if (props == null) return '(无标题)';
    // 找到 type=title 的属性（按 entry 顺序遍历）
    Map<String, dynamic>? titleProp;
    for (final p in props.values) {
      if ((p as Map<String, dynamic>)['type'] == 'title') {
        titleProp = p;
        break;
      }
    }
    if (titleProp == null) return '(无标题)';
    final titleArr = titleProp['title'] as List?;
    if (titleArr == null || titleArr.isEmpty) return '(空标题)';
    final parts = <String>[];
    for (final t in titleArr) {
      final type = t['type'];
      if (type == 'text') {
        parts.add((t['text']['content'] as String?) ?? '');
      } else if (type == 'mention') {
        final mention = t['mention'] as Map<String, dynamic>?;
        if (mention?['type'] == 'date') {
          parts.add((mention!['date']['start'] as String?) ?? '');
        } else if (mention?['type'] == 'user') {
          parts.add('@user');
        }
      }
    }
    final joined = parts.join('').trim();
    return joined.isEmpty ? '(空标题)' : joined;
  }

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