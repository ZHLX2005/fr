import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../pi_config.dart';
import '../pi_exception.dart';

/// 会话列表里的一条（`GET /sessions?summary=1`）。
///
/// 字段以真机返回为准；未建模的字段留在 [raw] 里。
class PiSessionSummary {
  final String id;
  final String? cwd;
  final String? name;
  final String? filePath;
  final DateTime? updatedAt;
  final Map<String, dynamic> raw;

  const PiSessionSummary({
    required this.id,
    this.cwd,
    this.name,
    this.filePath,
    this.updatedAt,
    this.raw = const {},
  });

  /// 展示名：优先 name，其次工作目录，最后退化为 id 前缀。
  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final c = cwd?.trim();
    if (c != null && c.isNotEmpty) return c;
    return id.length > 8 ? id.substring(0, 8) : id;
  }

  factory PiSessionSummary.fromJson(Map<String, dynamic> json) {
    DateTime? updated;
    for (final key in const ['updatedAt', 'modifiedAt', 'lastModified']) {
      final v = json[key];
      if (v is String) {
        updated = DateTime.tryParse(v);
        if (updated != null) break;
      } else if (v is num) {
        updated = DateTime.fromMillisecondsSinceEpoch(v.toInt());
        break;
      }
    }
    return PiSessionSummary(
      id: (json['id'] ?? json['sessionId'] ?? '').toString(),
      cwd: json['cwd']?.toString(),
      name: json['name']?.toString(),
      filePath: json['filePath']?.toString(),
      updatedAt: updated,
      raw: json,
    );
  }
}

/// 会话列表 + 在跑会话集合。
class PiSessionList {
  final List<PiSessionSummary> sessions;
  final Set<String> runningSessionIds;

  const PiSessionList({this.sessions = const [], this.runningSessionIds = const {}});

  factory PiSessionList.fromJson(Map<String, dynamic> json) {
    final list = (json['sessions'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(PiSessionSummary.fromJson)
        .toList();
    final running = (json['runningSessionIds'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toSet();
    return PiSessionList(sessions: list, runningSessionIds: running);
  }
}

/// pi 会话端点：列表、详情、状态、改名、删除。
class PiSessionsEndpoint {
  final PiConfig Function() _config;
  final http.Client _client;

  PiSessionsEndpoint({required PiConfig Function() config, http.Client? client})
      : _config = config,
        _client = client ?? http.Client();

  Map<String, String> _headers() => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (_config().token.isNotEmpty)
          'Authorization': 'Bearer ${_config().token}',
      };

  /// 会话列表。[summary] 为 true 时只取头部元数据，首屏更快。
  Future<PiSessionList> list({bool summary = true}) async {
    final cfg = _config();
    final uri = cfg.uri('/sessions', summary ? {'summary': '1'} : null);
    final json = await _getJson(uri);
    return PiSessionList.fromJson(json);
  }

  /// 会话详情：含 filePath / info / context / stats —— 用于进会话先拉历史。
  Future<Map<String, dynamic>> detail(String sessionId) =>
      _getJson(_config().uri('/sessions/$sessionId'));

  /// 运行状态（轻量，不启动会话）。
  Future<Map<String, dynamic>> state(String sessionId) =>
      _getJson(_config().uri('/sessions/$sessionId/state'));

  /// 上下文占用（percent / contextWindow / tokens）。
  Future<Map<String, dynamic>> context(String sessionId) =>
      _getJson(_config().uri('/sessions/$sessionId/context'));

  /// 改名。pi-web 用 PATCH /sessions/:id。
  Future<void> rename(String sessionId, String name) async {
    final cfg = _config();
    final resp = await _send(
      'PATCH',
      cfg.uri('/sessions/$sessionId'),
      body: {'name': name},
    );
    _ensureOk(resp);
  }

  /// 删除会话（pi-web 用 DELETE）。
  Future<void> delete(String sessionId) async {
    final resp = await _send('DELETE', _config().uri('/sessions/$sessionId'));
    _ensureOk(resp);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final resp = await _send('GET', uri);
    _ensureOk(resp);
    final decoded = json.decode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw PiApiException(
        statusCode: resp.statusCode,
        message: '响应不是 JSON 对象: ${resp.body}',
      );
    }
    return decoded;
  }

  Future<http.Response> _send(String method, Uri uri, {Object? body}) async {
    final cfg = _config();
    if (!cfg.isConfigured) {
      throw const PiApiException(
        statusCode: 0,
        message: 'pi 未配置：请先在设置里填写服务地址与 device token',
        code: 'NOT_CONFIGURED',
      );
    }
    final req = http.Request(method, uri)..headers.addAll(_headers());
    if (body != null) req.body = json.encode(body);
    try {
      final streamed = await _client.send(req).timeout(const Duration(seconds: 60));
      return http.Response.fromStream(streamed);
    } on TimeoutException {
      throw PiApiException(
        statusCode: 0,
        message: '请求超时：$method ${uri.path}',
        code: 'TIMEOUT',
      );
    } catch (e) {
      throw PiApiException(statusCode: 0, message: '$e', code: 'NETWORK');
    }
  }

  void _ensureOk(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw PiApiException.fromResponse(resp.statusCode, resp.body);
    }
  }

  void close() => _client.close();
}
