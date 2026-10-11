import 'token_storage.dart';

/// 拿到新 token 就返回 true；失败返回 false（调用方会把 401 原样抛给上层）。
typedef TokenReauthHandler = Future<bool> Function();

/// 业务后端会话凭据的生命周期管理。
///
/// ── 为什么这里不跟踪过期时间 ────────────────────────────────────────────
///
/// 业务后端的 JWT 有效期是**后端自己的策略**（当前配置是 30 天），
/// 而它的登录接口并不把 expires_in 告诉客户端。App 去猜一个时间，
/// 得到的只会是一个与后端不一致的本地假设 —— 猜短了无谓地重新登录，
/// 猜长了就在边界上随机失败。
///
/// 正确的做法是**反应式**的：token 用着用着收到 401，就说明它失效了，
/// 此时用统一登录平台的登录态静默重铸一枚（见 [attachReauth]）。
/// 失效的判定权交还给唯一真正知道答案的一方。
///
/// ── 为什么"静默重铸"是可行的 ────────────────────────────────────────────
///
/// 因为 App 还持有登录态。重铸不需要用户输口令，所以"不猜过期时间"
/// 不会带来任何体验损失 —— 这与上一版"只有 10 分钟的 access_token、
/// 又没有续期手段"的处境完全不同。
class TokenManager {
  final TokenStorage _storage;
  String? _cached;
  TokenReauthHandler? _reauth;
  Future<bool>? _inflight;

  TokenManager({required TokenStorage storage}) : _storage = storage;

  /// 注入"重新获取业务 token"的实现（装配期由 provider 挂上）。
  ///
  /// 用注入而不是让这里直接依赖 authhub：token/ 是基础设施层，
  /// 规范禁止它碰具体后端的 HTTP 细节。
  void attachReauth(TokenReauthHandler handler) => _reauth = handler;

  Future<String?> get accessToken async {
    final c = _cached;
    if (c != null) return c.isEmpty ? null : c;
    _cached = await _storage.accessToken;
    return _cached == null || _cached!.isEmpty ? null : _cached;
  }

  Future<void> setAccessToken(String token) async {
    _cached = token;
    await _storage.save(accessToken: token);
  }

  /// 401 之后尝试重铸。并发的多个 401 只触发一次（同一枚失效 token
  /// 各自去跑一遍 SSO 会平白生成多个会话）。
  Future<bool> tryRefresh() async {
    final inflight = _inflight;
    if (inflight != null) return inflight;
    final f = _doReauth();
    _inflight = f;
    try {
      return await f;
    } finally {
      _inflight = null;
    }
  }

  Future<bool> _doReauth() async {
    final handler = _reauth;
    if (handler == null) return false;
    try {
      return await handler();
    } catch (_) {
      // 收敛成"这次没成"，不外抛：拦截器要的是一个布尔值，
      // 抛出去会让一次网络抖动变成未捕获异常。
      return false;
    }
  }

  Future<void> clear() async {
    _cached = null;
    await _storage.clear();
  }
}
