// lib/core/game_kit/skin/public_kv_reader.dart
//
// Generic public KV reader (extracted from lib/core/chess/skins/public_kv_reader.dart).
// chess re-exports this.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// public KV 读取器 — 只读、匿名、无鉴权头。
///
/// 注入 [http.Client]（测试用 `package:http/testing` 的 MockClient）.
class PublicKvReader {
  final String baseUrl;
  final int groupId;
  final http.Client _client;
  final Duration _timeout;

  /// 构造。[baseUrl] 不带尾斜杠（如 `http://47.110.80.47:8988`）。
  /// [groupId] 必须 ≥ 1.
  PublicKvReader({
    required this.baseUrl,
    this.groupId = kPublicGroupId,
    http.Client? client,
    Duration? timeout,
  })  : _client = client ?? http.Client(),
        _timeout = timeout ?? defaultTimeout;

  /// "shared" 公共组 id（用户是 admin，可写可读）。
  static const int kPublicGroupId = 190;

  /// 向后兼容别名（chess 旧代码用 kChessSkinPublicGroupId）.
  static const int kChessSkinPublicGroupId = kPublicGroupId;

  /// 已废弃：请用各游戏的 GameSkinSpec.kvIndexKey（chess_skin:index 等）.
  /// 保留仅为兼容旧调用 `PublicKvReader.kSkinsIndexKey`.
  @Deprecated('Use GameSkinSpec.forGame(gameId).kvIndexKey')
  static const String kSkinsIndexKey = 'chess_skin:index';

  /// 默认超时
  static const Duration defaultTimeout = Duration(seconds: 5);

  /// 读取 public KV 的 [key] 的 value 字符串。
  ///
  /// 返回 null 的三种情况（调用方一律回退本地）：
  ///   1. 网络异常 / 超时
  ///   2. HTTP 非 200
  ///   3. body 不是标准 `{code, message, data}` 信封，或 code != 0，或 data.value 缺失
  ///
  /// 绝不抛出 —— 这是纯 best-effort 读取。
  Future<String?> readString(String key) async {
    try {
      final base = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl;
      final uri = Uri.parse('$base/api/v1/kv/public/$key?groupId=$groupId');
      final resp = await _client.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body);
      if (json is! Map<String, dynamic>) return null;
      final code = json['code'];
      if (code is! int || code != 0) return null;
      final data = json['data'];
      if (data is! Map<String, dynamic>) return null;
      final value = data['value'];
      return value is String ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// 释放底层 http.Client（可选；fire-and-forget 路径不调也不泄漏).
  void dispose() => _client.close();
}
