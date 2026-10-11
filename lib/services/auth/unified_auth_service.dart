import '../../api/authhub/authhub_config.dart';
import '../../api/authhub/authhub_exception.dart';
import '../../api/authhub/authhub_models.dart';
import '../../api/authhub/authhub_oidc_endpoint.dart';
import '../../api/authhub/authhub_pkce.dart';
import '../../api/token/token_manager.dart';
import '../../api/token/token_storage.dart';
import '../../api/user/user_auth_service.dart';
import '../../core/chess/p2p/chess_identity.dart';

/// 一次统一登录后的会话快照。
class AuthSession {
  /// 认证中心侧身份（sub / email / 昵称）
  final IdpUser idp;

  /// access_token 到期时刻
  final DateTime expiresAt;

  /// 业务后端（dev_ctr_hello）认出的本地账号 id。
  ///
  /// 单独存它而不是"用的时候再查"：国际象棋的玩家稳定身份就是
  /// `uid-<userId>`（见 chess_identity.dart），token 会随续期变化、不能当身份。
  final int? backendUserId;
  final String? backendNickname;

  const AuthSession({
    required this.idp,
    required this.expiresAt,
    this.backendUserId,
    this.backendNickname,
  });

  String get displayName {
    final n = backendNickname?.trim();
    if (n != null && n.isNotEmpty) return n;
    return idp.displayName;
  }
}

/// 发起授权所需的一切（URL + 那把只有本机知道的 PKCE 私货）。
///
/// 必须成对返回并成对持有：code_verifier 与 state 只在发起方内存里，
/// 一旦分开传，回调时就没人能验证"这个 code 是回给我的"。
class SignInRequest {
  final String authorizeUrl;
  final AuthPkce pkce;
  final String redirectUri;

  const SignInRequest({
    required this.authorizeUrl,
    required this.pkce,
    required this.redirectUri,
  });
}

/// 统一登录编排：认证中心授权 → 存 token → 让业务后端认领本地账号。
///
/// ── 为什么登录成功后还要多打一次业务后端的 /user/info ──────────────────
///
/// 统一登录只证明"这个人是认证中心里的 sub"，而本 App 大量功能认的是
/// **业务后端的本地 userId**（象棋身份、云同步归属都挂在它上面）。
/// 业务后端已经支持用认证中心的 access_token 调它的接口
/// （Bearer 回落：验票后按邮箱认领/自动建号），所以这里打一次 /user/info
/// 就同时完成了"认领"与"把本地 id 取回来"。
///
/// 这一步失败**不算登录失败**：认证中心的身份已经拿到、token 已存，
/// 只有依赖本地 id 的少数功能会暂时不可用。把它做成硬失败的话，
/// 用户会遇到"明明登录成功了却提示失败"，比功能暂时缺失更糟。
class UnifiedAuthService {
  final TokenManager _tokenManager;
  final AuthHubOidcEndpoint _oidc;
  final UserAuthService Function() _userApi;

  /// [userApi] 是工厂而不是实例：业务后端的账号服务在 GetIt 里是单例，
  /// 而它的注册发生在消息模块的 DI 初始化里。这里若直接收实例，
  /// provider 构建时机就会和那条注册顺序耦合上 —— 传工厂则推迟到真正要用时。
  const UnifiedAuthService({
    required TokenManager tokenManager,
    required AuthHubOidcEndpoint oidc,
    required UserAuthService Function() userApi,
  })  : _tokenManager = tokenManager,
        _oidc = oidc,
        _userApi = userApi;

  /// 认证中心是否可达。
  ///
  /// 供"要不要把统一登录作为默认入口"决策用：不可达时界面应回落到
  /// 邮箱密码登录，而不是给一个点了必然失败的按钮。
  Future<bool> probeIdp() async {
    try {
      await _oidc.discover();
      return true;
    } on AuthHubException {
      return false;
    }
  }

  /// 生成授权请求。每次调用都产生全新的 PKCE / state / nonce / 端口。
  ///
  /// 端口随机是为了让"同一次安装的多次登录"之间不互相干扰；
  /// 认证中心白名单放行 `127.0.0.1:*`，所以任意端口都合法。
  Future<SignInRequest> beginSignIn() async {
    final e = await _oidc.discover();
    final pkce = AuthPkce.generate();
    final port = 30000 + (DateTime.now().microsecondsSinceEpoch % 20000);
    final redirectUri = AuthHubConfig.redirectUriFor(port);

    final params = <String, String>{
      'response_type': 'code',
      'client_id': AuthHubConfig.clientId,
      'redirect_uri': redirectUri,
      'scope': AuthHubConfig.scopes.join(' '),
      'state': pkce.state,
      'nonce': pkce.nonce,
      ...pkce.challengeParams,
    };

    final url = Uri.parse(e.authorizationEndpoint)
        .replace(queryParameters: {..._queryOf(e.authorizationEndpoint), ...params})
        .toString();

    return SignInRequest(authorizeUrl: url, pkce: pkce, redirectUri: redirectUri);
  }

  /// 用回调 URL 里的 code 完成登录。
  ///
  /// [callbackUrl] 是 WebView 拦下来的那条 redirect_uri 完整地址。
  /// 这里做两件不能省的事：校验 state、以及从 URL 里区分"带了 code"和
  /// "带了 error"（用户在认证中心点拒绝时是后者）。
  Future<AuthSession> completeSignIn({
    required String callbackUrl,
    required SignInRequest request,
  }) async {
    final uri = Uri.tryParse(callbackUrl);
    if (uri == null) {
      throw const AuthHubException(
        error: AuthHubException.errNoCode,
        message: '回调地址无法解析',
      );
    }

    final q = uri.queryParameters;
    if ((q['state'] ?? '') != request.pkce.state) {
      // 不匹配只有两种可能：回调被串了，或者有人试图伪造一次授权完成。
      // 两种都必须中止，且不能退化成"那就当没这回事重试一次"。
      throw const AuthHubException(
        error: AuthHubException.errStateMismatch,
        message: '授权回调的 state 与发起时不一致，已中止登录',
      );
    }
    if (q['error'] != null) {
      throw AuthHubException(
        error: q['error']!,
        message: q['error_description'] ?? '认证中心拒绝了这次授权',
      );
    }
    final code = q['code'] ?? '';
    if (code.isEmpty) {
      throw const AuthHubException(
        error: AuthHubException.errNoCode,
        message: '回调里没有 authorization code',
      );
    }

    final set = await _oidc.exchangeCode(
      code: code,
      codeVerifier: request.pkce.codeVerifier,
      // 必须回传发起时那一个 redirect_uri（含端口）：两边不一致认证中心直接拒
      redirectUri: request.redirectUri,
    );

    await _tokenManager.setTokens(
      accessToken: set.accessToken,
      refreshToken: set.refreshToken,
      expiresAt: set.expiresAt,
      kind: AuthTokenKind.idp,
    );

    final idp = await _oidc.userinfo(set.accessToken);
    final session = AuthSession(
      idp: idp,
      expiresAt: set.expiresAt,
      backendUserId: null,
    );
    return _attachBackendIdentity(session);
  }

  /// 已有会话则取回（App 启动时判断"我是谁"）。未登录返回 null。
  Future<AuthSession?> restore() async {
    final token = await _tokenManager.accessToken;
    if (token == null || token.isEmpty) return null;
    try {
      final idp = await _oidc.userinfo(token);
      return AuthSession(idp: idp, expiresAt: DateTime.now().add(const Duration(hours: 1)));
    } on AuthHubException catch (e) {
      if (e.isFatalAuthError) {
        // 认证中心明确说票不行：本地状态已经不可信，清掉比留着好。
        // 留着的话每次启动都会拿一枚死票去撞，表现为"一直登录失败"。
        await _tokenManager.clear();
      }
      return null;
    }
  }

  /// 登出：吊销 refresh_token + 清本地凭据。
  ///
  /// 刻意**不**跳 end_session_endpoint：那会销毁用户在认证中心的全局会话，
  /// 连带把浏览器里其它已登录的业务系统一起踢下线。
  /// "从这个 App 登出"和"从统一登录平台登出"是两件事，混做一次会很伤人。
  Future<void> signOut() async {
    final token = await _tokenManager.accessToken;
    final refresh = await _tokenManager.refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      await _oidc.revoke(refresh);
    } else if (token != null && token.isNotEmpty) {
      await _oidc.revoke(token);
    }
    await _tokenManager.clear();
  }

  /// 让业务后端认领本地账号并把 userId 取回来。失败静默降级。
  Future<AuthSession> _attachBackendIdentity(AuthSession session) async {
    try {
      final res = await _userApi().userInfo();
      if (!res.isSuccess || res.data == null) return session;
      final data = res.data!;
      final uid = (data['id'] ?? data['userId']) as int?;
      if (uid != null) {
        // best-effort：持久化失败不影响登录本身（象棋身份会回退到设备 UUID）
        await ChessIdentity.persistUserId(uid);
      }
      return AuthSession(
        idp: session.idp,
        expiresAt: session.expiresAt,
        backendUserId: uid,
        backendNickname: data['nickname'] as String?,
      );
    } catch (_) {
      return session;
    }
  }

  Map<String, String> _queryOf(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return const {};
    return u.queryParameters;
  }
}
