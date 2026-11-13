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
///
/// ── 键名为什么不能直接用 Cookie 名 ──────────────────────────────────────
///
/// 早期版本把登录态存成 SharedPreferences['idp_session']，而同一时刻
/// token_storage.dart 把 'idp_session' 列进了它的「遗留键清理」列表
/// （那份列表原本是要清掉旧架构留下的凭据）。两个存储共用同一个键，
/// 于是**每铸一次业务 token，就顺手把登录态从磁盘上删掉**。
///
/// 症状与「登录态过期」几乎一样：认证中心的会话明明是 30 天 + 24h 看门狗续期
/// （服务端实测每条会话 TTL 都是 30 天），App 却总要重新登录 ——
/// 因为内存里的 _cached 还活着，同一进程内看不出问题；一重启 App 登录态就没了。
///
/// 所以这里用一个**带前缀的独立键**，并且不再与 Cookie 名共享命名空间。
class IdpSessionStore {
  /// 登录态在 SharedPreferences 里的键。
  ///
  /// 刻意带前缀：SharedPreferences 是全局扁平命名空间，而本 App 有多个存储
  /// （业务 token、mn-ws 凭据、mn-rt 凭据）共用它。裸键名迟早会撞车，
  /// 而撞车的后果是「一个存储删掉另一个存储的数据」——那类事故极难查。
  static const _keySession = 'authhub_idp_session';

  /// 撞键事故发生期间写下的键（`idp_session`）。
  ///
  /// 读的时候认它一次、迁移到新键就把它清掉：留着的理由与 token_storage
  /// 的遗留键清理一样 —— 升级后不该让旧凭据一直躺在磁盘上。
  /// 但**只迁移、不使用**：那枚 Cookie 是服务端签发的登录态，搬过来仍然有效，
  /// 所以老用户升级后不必被迫重新登录一次。
  static const _legacyKeySession = AuthHubConfig.sessionCookieName;

  String? _cached;

  /// 当前登录态；没有则 null。
  Future<String?> read() async {
    final c = _cached;
    if (c != null && c.isNotEmpty) return c;
    final prefs = await SharedPreferences.getInstance();

    var v = prefs.getString(_keySession);
    if (v == null || v.isEmpty) {
      // 旧键（撞键事故期间写入的）迁移一次。服务端那边的会话还有效，
      // 丢掉它等于让老用户升级后白白重新登录一次。
      final legacy = prefs.getString(_legacyKeySession);
      if (legacy != null && legacy.isNotEmpty) {
        await prefs.setString(_keySession, legacy);
        await prefs.remove(_legacyKeySession);
        v = legacy;
      }
    }
    _cached = v;
    return _cached;
  }

  Future<void> save(String cookieValue) async {
    _cached = cookieValue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySession, cookieValue);
    // 顺手清掉旧键：同一枚登录态留两份不是"备份"，而是下次读的时候
    // 分不清哪份是真的。
    if (prefs.containsKey(_legacyKeySession)) {
      await prefs.remove(_legacyKeySession);
    }
  }

  Future<void> clear() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySession);
    // 旧键也清：它是同一次登录的遗留副本，留着就等于登录态没退干净。
    await prefs.remove(_legacyKeySession);
  }

  Future<bool> get exists async => ((await read()) ?? '').isNotEmpty;
}
