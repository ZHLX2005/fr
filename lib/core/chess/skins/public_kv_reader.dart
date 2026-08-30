// lib/core/chess/skins/public_kv_reader.dart
//
// 匿名读取 public KV —— 走 /api/v1/kv/public/:key，不带鉴权头。
//
// 背景（实测于 2026-08-29，参见 docs/superpowers/specs/2026-08-29-chess-skin-kv-design.md）：
//   - 后端已有 public 公共组 groupId=190（"shared" 组，admin 可写）
//   - GET /api/v1/kv/public/:key?groupId=<gid> 可**匿名**读 public 值（无需 token）
//   - private / 不存在 → 返回 code 50 "key not found"
//   - 图片本身早已验证匿名可下：GET /files/<fileId>（见 file_resolver.dart）
//
// 语义：这是 best-effort 读取 —— 任何失败（网络 / 超时 / 格式错 / key 缺失）
// 都返回 null，**绝不抛异常**。调用方（chess_skin_meta_sync.dart）拿到 null
// 就回退本地 const catalog，保证零回归。

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// public KV 读取器 — 只读、匿名、无鉴权头。
///
/// 注入 [http.Client]（测试用 `package:http/testing` 的 MockClient）：
/// 默认 [http.Client] 实例在 Android 真机上直连后端公网地址。
class PublicKvReader {
  final String baseUrl;
  final int groupId;
  final http.Client _client;
  final Duration _timeout;

  /// 构造。[baseUrl] 不带尾斜杠（如 `http://47.110.80.47:8988`）。
  /// [groupId] 必须 ≥ 1（后端对 groupId<1 的 public 读可能视为无组）。
  PublicKvReader({
    required this.baseUrl,
    this.groupId = kChessSkinPublicGroupId,
    http.Client? client,
    Duration? timeout,
  })  : _client = client ?? http.Client(),
        _timeout = timeout ?? defaultTimeout;

  /// "shared" 公共组 id（用户是 admin，可写可读）。
  static const int kChessSkinPublicGroupId = 190;

  /// 皮肤 meta 索引在 KV 中的 key。值是 JSON array 文本
  /// （结构同 kChessSkinsCatalog 的条目数组，见 chess_skin_meta.dart）。
  static const String kSkinsIndexKey = 'chess_skin:index';

  /// 默认超时（真机踩坑：网络黑洞 —— 不可达但不立刻拒绝时 http.get 永不完成。
  /// 短超时保证 fire-and-forget 不会在后台挂死）。
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
      // 任何异常（ClientException / TimeoutException / FormatException / ...）
      // 一律静默吞掉 → 调用方回退本地。
      return null;
    }
  }

  /// 释放底层 http.Client（可选；fire-and-forget 路径不调也不泄漏——
  /// 默认 Client 生命周期随 process，close 只是显式释放）。
  void dispose() => _client.close();
}
