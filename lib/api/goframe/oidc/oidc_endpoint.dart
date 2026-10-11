import '../../api_client.dart';
import '../../api_response.dart';
import 'oidc_models.dart';

/// 业务后端的统一登录端点（`/api/v1/user/oidc/*`）。
///
/// 走 ApiClient 的统一拦截器链：这两个端点本身是公开的（无需登录），
/// 但用同一套信封解析、超时与重试策略，没有另开一条路的理由。
///
/// ── 这两个端点是"用登录态换业务 token"链条的后半段 ──────────────────────
///
///   ① GET  /user/oidc/config    问后端"你在认证中心注册成了什么"
///   ② App 拿统一登录平台的登录态，静默完成 authorize + consent，得到 code
///      与 code_verifier（见 AuthHubSessionClient.mintCodeForClient）
///   ③ POST /user/oidc/callback  把 code + verifier 交给后端，换回它自己的 JWT
///
/// 后端拿 code 去认证中心换 token 用的是**它自己的** client 身份，
/// 那批 token 留在后端、不下发给 App。所以 App 自始至终只持有两样东西：
/// 统一登录平台的登录态，和业务后端的 JWT。
class OidcEndpoint {
  final ApiClient _client;

  OidcEndpoint(this._client);

  /// 发起统一登录所需的公开参数。
  Future<ApiResponse<BackendOidcConfig>> config() =>
      _client.request<BackendOidcConfig>(
        method: 'GET',
        path: '/api/v1/user/oidc/config',
        fromJson: (json) => BackendOidcConfig.fromJson(json),
      );

  /// 用授权码换业务后端的会话。
  ///
  /// [redirectUri] 必须是**发起授权时那一个**，两边不一致认证中心会拒绝换码。
  /// 所以它由调用方从 config() 的返回值一路带过来，不在这里重新获取。
  Future<ApiResponse<BackendSession>> callback({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) =>
      _client.request<BackendSession>(
        method: 'POST',
        path: '/api/v1/user/oidc/callback',
        body: {
          'code': code,
          'codeVerifier': codeVerifier,
          'redirectUri': redirectUri,
        },
        fromJson: (json) => BackendSession.fromJson(json),
      );
}
