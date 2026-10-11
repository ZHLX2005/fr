import 'token_storage.dart';

/// 续期回调：拿 refresh_token 换一枚新的 access_token，成功返回 true。
///
/// 为什么用注入的回调而不是让 TokenManager 自己去调认证中心：
/// `token/` 的职责是"token 生命周期"，规范明确禁止它碰 HTTP 细节
/// （见 api-module-auth 的职责边界表）。让它 import authhub 端点，
/// 两者就会互相依赖；而且"怎么续期"是个业务事实，
/// 焊死在基础设施层里等于每换一个签发方都要回来改这里。
typedef TokenRefreshHandler = Future<bool> Function(String refreshToken);

/// Token / API Key 生命周期管理。
///
/// 现在同时服务两种签发方（见 [AuthTokenKind]）。统一认证中心的 access_token
/// 只有 10 分钟，所以**必须**能自动续期 —— 否则接了统一登录的 App
/// 会在十几分钟后所有业务接口集体 401，而用户刚登录完什么也没做错。
class TokenManager {
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  AuthTokenKind _kind = AuthTokenKind.none;
  final TokenStorage _storage;

  /// 提前多久就视为该续期。为 null 表示不做主动续期，只在 401 后被动刷。
  final Duration? refreshSkew;

  TokenRefreshHandler? _refresher;

  /// 进行中的续期。并发的多个 401 只应触发一次 refresh ——
  /// 同一枚 refresh_token 被并发用两次，第二次可能被判为重放而整条续期链作废。
  Future<bool>? _inflight;

  TokenManager({required TokenStorage storage, this.refreshSkew})
      : _storage = storage;

  /// 装配期注入续期实现。
  ///
  /// 用 setter 而不是构造参数：TokenManager 是基础设施、authhub 端点是某个
  /// 后端的实现，构造参数会把两者焊成一条依赖链，DI 图里谁也测不了谁。
  void attachRefresher(TokenRefreshHandler handler) => _refresher = handler;

  Future<String?> get accessToken async {
    if (_accessToken != null && !_isExpired) return _accessToken;
    await _hydrate();
    // 主动续期放在这个 getter 里，而不是让每个调用方自己判断还剩几分钟：
    // "凭据快到期了"这件事全仓库只该有一个处理点，漏一处就是一次莫名的 401。
    if (_accessToken != null && _accessToken!.isNotEmpty && _nearExpiry) {
      await tryRefresh();
    }
    return _accessToken;
  }

  Future<AuthTokenKind> get tokenKind async {
    if (_kind != AuthTokenKind.none) return _kind;
    await _hydrate();
    return _kind;
  }

  /// 当前 refresh_token（登出时用于吊销）。
  ///
  /// 单独开这个口子，是为了不把 `_refreshToken` 变成 public final：
  /// 它是续期与吊销的唯一凭据，暴露成可写字段就等于允许任何地方悄悄改掉它。
  Future<String?> get refreshToken async {
    final cached = _refreshToken;
    if (cached != null) return cached;
    _refreshToken = await _storage.refreshToken;
    return _refreshToken;
  }

  bool get _isExpired =>
      _expiresAt != null && DateTime.now().isAfter(_expiresAt!);

  bool get _nearExpiry {
    final exp = _expiresAt;
    final skew = refreshSkew;
    if (exp == null) return false; // 不知道有效期就别瞎刷
    if (skew == null) return DateTime.now().isAfter(exp);
    return DateTime.now().add(skew).isAfter(exp);
  }

  Future<void> setAccessToken(String token) async {
    _accessToken = token;
    await _storage.save(accessToken: token);
  }

  /// 写入一整套凭据。
  ///
  /// [kind] 必须显式传：签发方决定能不能续期，猜错的症状是
  /// "过一会儿全体掉线"，现场完全指不到根因上。
  ///
  /// 注意这里对 `refreshToken == null` 的处理是**保留旧值**，与字段名直觉相反：
  /// 认证中心的 refresh_token 不是滚动签发的，续期响应里常常没有新
  /// refresh_token；若照单全收地把内存里的置成 null，一次续期成功
  /// 就会永久断掉后续所有续期能力 —— 而且要到 7 天后才第一次暴露。
  Future<void> setTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    AuthTokenKind kind = AuthTokenKind.idp,
  }) async {
    _accessToken = accessToken;
    _kind = kind;
    if (refreshToken != null) _refreshToken = refreshToken;
    if (expiresAt != null) _expiresAt = expiresAt;
    await _storage.save(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      kind: kind,
    );
  }

  /// 尝试续期。返回 false 表示"刷不动了"，调用方应当引导重新登录。
  Future<bool> tryRefresh() async {
    final inflight = _inflight;
    if (inflight != null) return inflight;

    final future = _doRefresh();
    _inflight = future;
    try {
      return await future;
    } finally {
      _inflight = null;
    }
  }

  Future<bool> _doRefresh() async {
    final token = _refreshToken ?? await _storage.refreshToken;
    if (token == null || token.isEmpty) return false;

    final kind = _kind == AuthTokenKind.none
        ? await _storage.tokenKind
        : _kind;
    // legacyBackend 没有续期端点。硬去调认证中心会拿回一个 invalid_grant，
    // 把"本来就该重新登录"伪装成"认证中心拒绝了我"。
    if (kind != AuthTokenKind.idp) return false;

    final handler = _refresher;
    if (handler == null) return false;

    try {
      return await handler(token);
    } catch (_) {
      // 续期失败一律收敛成"这次没刷动"，不外抛：调用方（拦截器）要的是
      // "要不要带新 token 重试一次"这个布尔值，抛出去会让一次网络抖动
      // 变成未捕获异常。
      return false;
    }
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _kind = AuthTokenKind.none;
    await _storage.clear();
  }

  Future<void> _hydrate() async {
    _accessToken = await _storage.accessToken;
    _refreshToken = await _storage.refreshToken;
    _expiresAt = await _storage.expiresAt;
    _kind = await _storage.tokenKind;
  }
}
