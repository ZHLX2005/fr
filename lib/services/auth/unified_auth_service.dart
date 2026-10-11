import '../../api/authhub/authhub_exception.dart';
import '../../api/authhub/authhub_models.dart';
import '../../api/authhub/authhub_native_login.dart';
import '../../api/authhub/authhub_oidc_endpoint.dart';
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

  /// 登录用的账号名，仅用于过期后重新登录时**预填**。
  /// 口令不在此列 —— 见 signInWithPassword 的说明。
  final String? username;

  const AuthSession({
    required this.idp,
    required this.expiresAt,
    this.backendUserId,
    this.backendNickname,
    this.username,
  });

  String get displayName {
    final n = backendNickname?.trim();
    if (n != null && n.isNotEmpty) return n;
    return idp.displayName;
  }
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
  final AuthHubNativeLoginFlow _native;
  final UserAuthService Function() _userApi;

  /// [userApi] 是工厂而不是实例：业务后端的账号服务在 GetIt 里是单例，
  /// 而它的注册发生在消息模块的 DI 初始化里。这里若直接收实例，
  /// provider 构建时机就会和那条注册顺序耦合上 —— 传工厂则推迟到真正要用时。
  const UnifiedAuthService({
    required TokenManager tokenManager,
    required AuthHubOidcEndpoint oidc,
    required AuthHubNativeLoginFlow native,
    required UserAuthService Function() userApi,
  })  : _tokenManager = tokenManager,
        _oidc = oidc,
        _native = native,
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

  /// 用账号口令完成一次原生登录，返回会话快照。
  ///
  /// 口令只在本次调用内存在：不写日志、不进异常消息、也不缓存在字段里
  /// （缓存在内存里"以便静默续期"看着方便，但那等于把口令的生命周期
  /// 从一次操作拉长到整个进程，而进程可能被 dump、可能被截图工具读到）。
  /// 因此过期时界面上就是"重新输一次口令"—— 这是选原生表单 +
  /// 不存长期凭据这个组合必然要付的代价，如实呈现比藏起来好。
  Future<AuthSession> signInWithPassword({
    required String username,
    required String password,
  }) async {
    final set = await _native.signInWithPassword(
      username: username,
      password: password,
    );

    // 只存 access_token。令牌端点同时返回的 refresh_token 在这里被丢弃：
    // 它是 7 天有效、无设备绑定的账号级凭据，而本机持久化层是明文存储。
    await _tokenManager.setTokens(
      accessToken: set.accessToken,
      expiresAt: set.expiresAt,
      kind: AuthTokenKind.idp,
    );

    final idp = await _oidc.userinfo(set.accessToken);
    return _attachBackendIdentity(AuthSession(
      idp: idp,
      expiresAt: set.expiresAt,
      // 顺手记下账号，供过期后重新登录时预填 —— 预填用户名不涉及任何凭据，
      // 却能把"重输一遍"的摩擦砍掉一半。
      username: username,
    ));
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
    // 吊销 access_token（不再有 refresh_token 可吊销 —— 客户端从未持有）。
    // 认证中心对未知/已失效 token 也返回 200，所以不能拿返回值判断成败。
    if (token != null && token.isNotEmpty) {
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
        username: session.username,
      );
    } catch (_) {
      return session;
    }
  }
}
