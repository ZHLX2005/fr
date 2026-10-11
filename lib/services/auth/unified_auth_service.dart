import '../../api/authhub/authhub_pkce.dart';
import '../../api/authhub/authhub_exception.dart';
import '../../api/authhub/authhub_session_client.dart';
import '../../api/authhub/idp_session_store.dart';
import '../../api/goframe/oidc/oidc_models.dart';
import '../../api/goframe/oidc/oidc_endpoint.dart';
import '../../api/token/token_manager.dart';
import '../../core/chess/p2p/chess_identity.dart';

/// App 当前持有的两份凭据的状态快照。
class AppAuthState {
  /// 统一登录平台的身份（登录态对应的人）。null = 没有登录态。
  final IdpIdentity? idp;

  /// 业务后端认出的本地账号。仅在刚换完 token 时有值（含 provisioned/rebound 等
  /// 一次性信号）；启动恢复时不重建成假对象，用 [hasBackendToken] 表达"有没有"。
  final BackendSession? backend;

  /// 磁盘上是否存有业务后端的会话凭据。
  final bool hasBackendToken;

  /// 用登录态换业务 token 时后端是否新建了本地账号
  final bool provisioned;

  /// 后端是否把这个外部身份改绑到了另一个本地账号。
  ///
  /// 必须显示出来而不是吞掉：改绑意味着"你看到的数据换了一个账号"，
  /// 静默发生会被用户当成丢数据。后端刻意把它回带上来就是这个原因。
  final bool rebound;

  const AppAuthState({
    this.idp,
    this.backend,
    this.hasBackendToken = false,
    this.provisioned = false,
    this.rebound = false,
  });

  bool get hasIdpSession => idp != null;

  String get displayName {
    final b = backend?.displayName.trim();
    if (b != null && b.isNotEmpty) return b;
    return idp?.displayName ?? '';
  }
}

/// 统一登录编排：登录态 → 静默换业务 token。
///
/// ── 两个凭据，各管各的 ──────────────────────────────────────────────────
///
///   统一登录平台登录态   用于批准扫码，以及静默换业务 token
///   业务后端 JWT         用于所有业务接口
///
/// 上一版把这两个职责压在同一个 access_token 上，于是它的 10 分钟有效期
/// 同时满足不了两边，接着就要么引入 refresh_token、要么去改平台级 TTL ——
/// 那两个补丁都是第一个错误的派生物，不是真需求。
///
/// ── 为什么业务 token 失效时能静默恢复 ──────────────────────────────────
///
/// 因为登录态还在。收到 401 → 用登录态重走一遍授权 → 拿新 token，
/// 用户完全无感。所以 App 既不需要猜业务 token 的有效期，
/// 也不需要任何长期凭据（refresh_token）。
class UnifiedAuthService {
  final AuthHubSessionClient _idp;
  final IdpSessionStore _sessionStore;
  final OidcEndpoint _oidc;
  final TokenManager _tokens;

  const UnifiedAuthService({
    required AuthHubSessionClient idp,
    required IdpSessionStore sessionStore,
    required OidcEndpoint oidc,
    required TokenManager tokens,
  })  : _idp = idp,
        _sessionStore = sessionStore,
        _oidc = oidc,
        _tokens = tokens;

  /// 口令登录：先拿登录态，再用它换业务 token。
  ///
  /// 第二步失败**不算登录失败**（见 [_mintBackendToken] 的说明），
  /// 返回的状态里 idp 有值、backend 为 null，界面据此提示重试。
  Future<AppAuthState> signInWithPassword({
    required String username,
    required String password,
  }) async {
    final idp = await _idp.signInWithPassword(
        username: username, password: password);
    final backend = await _mintBackendToken();
    return AppAuthState(
      idp: idp,
      backend: backend,
      hasBackendToken: (backend?.token ?? '').isNotEmpty,
      provisioned: backend?.provisioned ?? false,
      rebound: backend?.rebound ?? false,
    );
  }

  /// 恢复当前状态（App 启动时判断"我是谁"）。
  Future<AppAuthState> restore() async {
    final idp = await _idp.me();
    if (idp == null) {
      // 没有登录态就没有一切：业务 token 即便还在磁盘上，
      // 也无法在失效后自愈，留着只会造成"看着已登录、一操作就 401"。
      await _tokens.clear();
      return const AppAuthState();
    }
    var token = await _tokens.accessToken;
    if (token == null || token.isEmpty) {
      token = (await _mintBackendToken())?.token;
    }
    return AppAuthState(idp: idp, hasBackendToken: (token ?? '').isNotEmpty);
  }

  /// 用登录态换一枚业务后端 token 并落盘。
  ///
  /// 失败时返回 null 而不是抛：登录态已经拿到了，业务 token 只是还没换到。
  /// 把它做成硬失败会出现"明明登录成功却提示失败"，比暂时用不了业务接口更糟。
  Future<BackendSession?> _mintBackendToken() async {
    try {
      final cfgRes = await _oidc.config();
      if (!cfgRes.isSuccess || cfgRes.data == null) return null;
      final cfg = cfgRes.data!;
      if (!cfg.enabled || cfg.clientId.isEmpty || cfg.redirectUri.isEmpty) {
        return null;
      }

      // PKCE 由 App 生成、verifier 由 App 保管并原样转交给业务后端。
      // 谁拿去换 token，谁就该持有 verifier —— 这正是"捡到 code 换不出东西"的保证。
      final pkce = AuthPkce.generate();
      final issued = await _idp.mintCodeForClient(
        client: cfg.clientId,
        redirectUri: cfg.redirectUri,
        scopes: cfg.scopes.isEmpty ? const ['openid', 'profile', 'email'] : cfg.scopes,
        state: pkce.state,
        nonce: pkce.nonce,
        codeChallenge: pkce.codeChallenge,
      );

      final res = await _oidc.callback(
        code: issued.code,
        codeVerifier: pkce.codeVerifier,
        redirectUri: cfg.redirectUri,
      );
      if (!res.isSuccess || res.data == null || res.data!.isEmpty) return null;

      final session = res.data!;
      await _tokens.setAccessToken(session.token);
      if (session.userId > 0) {
        // 象棋玩家身份是 uid-<userId>，稳定标识；token 会随重铸变化，不能当身份。
        await ChessIdentity.persistUserId(session.userId);
      }
      return session;
    } on AuthHubException {
      return null;
    }
  }

  /// 退出：两份凭据一起清。
  Future<void> signOut() async {
    await _idp.signOut();
    await _tokens.clear();
  }

  /// 供 TokenManager 注入的重铸钩子：业务 token 401 时用它静默换一枚。
  Future<bool> reauthBackendToken() async => await _mintBackendToken() != null;

  /// 是否还有登录态。批准扫码前必须为真。
  Future<bool> get hasIdpSession => _sessionStore.exists;
}
