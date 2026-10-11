import 'package:shared_preferences/shared_preferences.dart';

import 'authhub_config.dart';

/// 统一登录平台的**登录态**存储。
///
/// ── 为什么它是独立的一个槽，而不是塞进 TokenStorage ──────────────────────
///
/// 本 App 现在同时持有两个凭据，它们**回答的是不同的问题**：
///
///   idp_session   「这台设备在统一登录平台还算不算已登录」
///                 → 用于批准扫码，以及静默换取业务后端的 token
///   业务后端 JWT   「这台设备在 8988 那个平台上是谁」
///                 → 用于所有业务接口
///
/// 把两者混在一个存储里，迟早会再出上一次那种事故：一枚凭据被拿去兼两个用途，
/// 于是它的有效期同时满足不了两边的需求，然后就开始给平台级参数打补丁。
/// 分开存，各自的过期、清理、吊销路径也就自然分开了。
///
/// ── 为什么是会话而不是 access_token ──────────────────────────────────────
///
/// 会话在服务端是 `user_sessions` 表里的一行，**可以被立刻吊销**（RP 发起登出、
/// 管理员处置被盗账号都会删它）。access_token / refresh_token 都是为
/// "给依赖方用"设计的，而本 App 不是任何人的依赖方——它只是想要一个登录态。
///
/// 存的是 Cookie 原文。它和 8988 那枚 30 天 JWT 落在同一个 SharedPreferences 里，
/// 风险同级（而且因为它可吊销，严格说更低）。
class IdpSessionStore {
  static const _keySession = AuthHubConfig.sessionCookieName;

  String? _cached;

  /// 当前登录态；没有则 null。
  Future<String?> read() async {
    final c = _cached;
    if (c != null && c.isNotEmpty) return c;
    final prefs = await SharedPreferences.getInstance();
    _cached = prefs.getString(_keySession);
    return _cached;
  }

  Future<void> save(String cookieValue) async {
    _cached = cookieValue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySession, cookieValue);
  }

  Future<void> clear() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySession);
  }

  Future<bool> get exists async => ((await read()) ?? '').isNotEmpty;
}
