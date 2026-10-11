import 'token_storage.dart';

/// Token / API Key 生命周期管理。
///
/// ── 为什么这里不再有 refresh_token ──────────────────────────────────────
///
/// 认证中心的 refresh_token 有效期 7 天、**没有任何发送方绑定**
/// （refresh 请求不带 PKCE、不校验设备），拿到字符串就等于拿到一周内随时
/// 铸造新 access_token 的能力；而接入扫码之后，这个能力还包括
/// **批准其他设备登录**。一枚泄露的 refresh_token ≈ 一周的完整账号接管。
///
/// 而本机的持久化层是 SharedPreferences —— 应用私有目录下的明文 XML，
/// 且 `android:allowBackup` 从未设置（默认 true）、也没有排除规则，
/// 意味着它会被自动备份带离设备。那种量级的凭据放这里是成立的不了。
///
/// 所以结论：**长期凭据不落客户端**。这里只存短命的 access_token，
/// 过期就走一次 WebView 重新授权（认证中心若仍保有全局会话，通常是无感的）。
///
/// ── 代价，说清楚不藏着 ──────────────────────────────────────────────────
///
/// access_token 只有 10 分钟。静置十分钟后再次操作就需要重新走一次授权，
/// 这是"不存长期凭据"的直接后果，不是 bug —— 想要永不掉线就得存
/// refresh_token，两者只能取其一。将来若要兼顾体验，正确做法是把凭据放进
/// Android Keystore 背书的安全存储（flutter_secure_storage），
/// 而不是放回 SharedPreferences。
class TokenManager {
  String? _accessToken;
  DateTime? _expiresAt;
  AuthTokenKind _kind = AuthTokenKind.none;
  final TokenStorage _storage;

  /// 距过期多久就视为"该重新授权了"。
  ///
  /// 留提前量是为了避开"发出请求时还剩 3 秒、往返路上过期"这种
  /// 在边界上随机失败的竞态。
  final Duration reauthLead;

  TokenManager({
    required TokenStorage storage,
    this.reauthLead = const Duration(seconds: 60),
  }) : _storage = storage;

  Future<String?> get accessToken async {
    if (_accessToken != null && !_isExpired) return _accessToken;
    await _hydrate();
    return _accessToken;
  }

  Future<AuthTokenKind> get tokenKind async {
    if (_kind != AuthTokenKind.none) return _kind;
    await _hydrate();
    return _kind;
  }

  /// 是否已过期或即将过期 —— 调用方据此主动触发重新授权。
  ///
  /// 这是"不存 refresh_token"换来的唯一新义务：续期做不了了，
  /// 就必须有人负责在过期前把用户带回授权页。把它做成一个明确的查询，
  /// 比让每个调用方自己去比时间戳可靠得多（漏一处就是一次莫名的 401）。
  Future<bool> get needsReauth async {
    final token = await accessToken;
    if (token == null || token.isEmpty) return true;
    final exp = _expiresAt;
    if (exp == null) return false; // 不知道有效期就别瞎猜
    return DateTime.now().add(reauthLead).isAfter(exp);
  }

  bool get _isExpired =>
      _expiresAt != null && DateTime.now().isAfter(_expiresAt!);

  Future<void> setAccessToken(String token) async {
    _accessToken = token;
    await _storage.save(accessToken: token);
  }

  /// 写入一次登录得到的凭据。
  ///
  /// [kind] 必须显式传：签发方决定这枚 token 能用在哪些接口上，
  /// 猜错的症状是"过一会儿全体 401"，而现场完全指不到根因。
  ///
  /// 参数里**没有** refreshToken —— 令牌端点会返回它，但这里刻意不接。
  /// 在边界上就丢掉，比"传进来再指望某人别存"可靠：字段一旦存在于签名里，
  /// 迟早会有某条路径把它写进磁盘。
  Future<void> setTokens({
    required String accessToken,
    DateTime? expiresAt,
    AuthTokenKind kind = AuthTokenKind.idp,
  }) async {
    _accessToken = accessToken;
    _kind = kind;
    if (expiresAt != null) _expiresAt = expiresAt;
    await _storage.save(
      accessToken: accessToken,
      expiresAt: expiresAt,
      kind: kind,
    );
  }

  /// 兼容 `AuthInterceptor` 的 401 重试钩子：当前架构下**永远刷不动**。
  ///
  /// 保留这个方法而不是删掉，是因为"客户端不持有长期凭据"就意味着
  /// 401 无法自愈，而返回 false 会让拦截器把 401 原样抛给上层，
  /// 上层据此引导重新授权 —— 那是对的。把它伪装成成功，或者直接删掉
  /// 让拦截器改不动，都会把一次正常的过期变成一处难查的死循环。
  Future<bool> tryRefresh() async => false;

  Future<void> clear() async {
    _accessToken = null;
    _expiresAt = null;
    _kind = AuthTokenKind.none;
    await _storage.clear();
  }

  Future<void> _hydrate() async {
    _accessToken = await _storage.accessToken;
    _expiresAt = await _storage.expiresAt;
    _kind = await _storage.tokenKind;
  }
}
