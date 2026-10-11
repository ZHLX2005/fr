import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'remotetype_models.dart';

/// 远程输入桥凭据的持久化。
///
/// ── 存什么 ────────────────────────────────────────────────────────────────
/// 只存本服务自签的 `token`（可被服务端吊销）与身份快照。
/// **不存会话密钥（sessionKey）**：那是每台电脑一把、随 /my/devices 现取的，
/// 缓存下来只会造成"手机拿旧 key 连新 key 的电脑"这类静默对不上的故障。
///
/// ── 不存什么 ───────────────────────────────────────────────────────────────
/// 认证中心的 access_token / refresh_token 一个字节都不留。它们在换到本服务
/// 凭据的那一瞬间就已经用完；refresh_token 尤其不该出现在客户端 ——
/// 存了它就有静默续期，有静默续期用户就再也回不到认证中心，
/// 统一登出、周期性重新确认身份、认证策略变更全部形同虚设。
///
/// 过期就走一次重新授权（内部服务已自动同意，用户无感），不做任何续期机制。
class RemoteTypeGrantStore {
  static const _keyGrant = 'remotetype_grant';

  /// 历史上可能写歪过的键：**只删不写**。
  ///
  /// 放在 save() 里清而不是只在 clear() 里清 —— 装过旧版本的设备如果用户
  /// 从不主动登出，磁盘上那枚 refresh_token 就会一直留着。
  /// "它不该存在于客户端"是个结论，不该依赖用户做某个动作才成立。
  static const _legacyKeys = [
    'remotetype_refresh_token',
    'remotetype_idp_token',
    'remotetype_session_key', // 单键缓存密钥：多电脑场景下必错，改为每次现取
  ];

  /// 读回凭据。过期或格式不对一律返回 null（宁可重新授权，不要用一枚坏凭据）。
  Future<RtGrant?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyGrant);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final grant = RtGrant.fromJson(map);
      if (grant.token.isEmpty) return null;
      if (grant.isExpired) return null;
      return grant;
    } catch (_) {
      // 坏数据静默丢弃即可：重新走一次授权的成本是几秒钟，
      // 而为一个坏 JSON 抛错会把"能自愈的路径"变成"用户看到报错"。
      return null;
    }
  }

  Future<void> save(RtGrant grant) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGrant, jsonEncode(grant.toJson()));
    for (final k in _legacyKeys) {
      if (prefs.containsKey(k)) await prefs.remove(k);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGrant);
    for (final k in _legacyKeys) {
      await prefs.remove(k);
    }
  }
}
