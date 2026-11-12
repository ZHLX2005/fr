import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'mnws_models.dart';

/// mn-ws 设备令牌的持久化。
///
/// ── 存什么 ────────────────────────────────────────────────────────────────
/// 只存 mn-ws server 自签的设备令牌（可被服务端按 jti 单独吊销）与身份快照。
///
/// ── 不存什么 ──────────────────────────────────────────────────────────────
/// 认证中心的 access_token **一个字节都不留**。它 10 分钟就过期，
/// 存在的唯一意义是「换一枚 mn-ws 设备令牌」；留着它就等于留了一份
/// 指向整个平台身份的高价值凭据。过期就走一次重新授权（内部服务自动同意，
/// 用户无感），不做任何续期机制。
class MnWsGrantStore {
  static const _keyGrant = 'mnws_grant';

  /// 读回凭据。过期或格式不对一律返回 null（宁可重新授权，不要用一枚坏凭据）。
  Future<MnWsGrant?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyGrant);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final grant = MnWsGrant.fromJson(map);
      if (grant.token.isEmpty) return null;
      if (grant.isExpired) return null;
      return grant;
    } catch (_) {
      // 坏数据静默丢弃即可：重新走一次授权的成本是几秒钟，
      // 而为一个坏 JSON 抛错会把「能自愈的路径」变成「用户看到报错」。
      return null;
    }
  }

  Future<void> save(MnWsGrant grant) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGrant, jsonEncode(grant.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGrant);
  }
}
