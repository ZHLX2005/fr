/// 业务后端（dev_ctr_hello）统一登录接口的数据模型。
///
/// 字段名保留后端的 camelCase（它用的是 GoFrame 默认序列化，与认证中心的
/// snake_case 不是同一套口径 —— 两处的差异如实反映，不做统一映射，
/// 否则任何一边改字段都会对不上且看不出来）。
library;

/// `GET /user/oidc/config` —— 发起统一登录所需的公开参数。
///
/// 刻意**不在 App 里硬编码** issuer / clientId / redirectUri：这三个值属于
/// 业务后端在认证中心的注册信息，改它的是后端。App 硬编码的话，
/// 后端换个回调地址就要重新发版才能登录。
class BackendOidcConfig {
  final bool enabled;
  final String issuer;
  final String clientId;
  final String redirectUri;
  final List<String> scopes;
  final String authorizationEndpoint;
  final String endSessionEndpoint;

  /// false 表示业务后端连不上认证中心（此时上面两个端点是按 issuer 兜底拼的）
  final bool idpAvailable;
  final String idpError;

  const BackendOidcConfig({
    required this.enabled,
    required this.issuer,
    required this.clientId,
    required this.redirectUri,
    required this.scopes,
    required this.authorizationEndpoint,
    required this.endSessionEndpoint,
    required this.idpAvailable,
    required this.idpError,
  });

  factory BackendOidcConfig.fromJson(Map<String, dynamic> j) =>
      BackendOidcConfig(
        enabled: j['enabled'] as bool? ?? false,
        issuer: j['issuer'] as String? ?? '',
        clientId: j['clientId'] as String? ?? '',
        redirectUri: j['redirectUri'] as String? ?? '',
        scopes: (j['scopes'] as List?)?.map((e) => '$e').toList() ?? const [],
        authorizationEndpoint: j['authorizationEndpoint'] as String? ?? '',
        endSessionEndpoint: j['endSessionEndpoint'] as String? ?? '',
        idpAvailable: j['idpAvailable'] as bool? ?? false,
        idpError: j['idpError'] as String? ?? '',
      );
}

/// `POST /user/oidc/callback` —— 授权码换来的业务后端会话。
class BackendSession {
  /// 业务后端自己的 HS256 JWT。这才是 App 访问业务接口该用的凭据。
  final String token;
  final int userId;
  final String email;
  final String username;
  final String nickname;

  /// 认证中心侧的用户标识，仅作辅助定位
  final String sub;

  /// true = 认证中心给的邮箱在业务后端没有对应账号，本次自动建了号
  final bool provisioned;

  /// true = 本次第一次见到这个外部身份，新建了绑定
  final bool identityBound;

  /// true = 这个外部身份原本绑在别的本地账号上，本次按邮箱改绑了。
  ///
  /// 后端刻意把它回带给调用方而不是静默迁移（改绑是用户能感知到数据变化的
  /// 写操作）。App 侧应当把它显示出来 —— 悄悄换了账号是会被当成丢数据的。
  final bool rebound;

  const BackendSession({
    required this.token,
    required this.userId,
    required this.email,
    required this.username,
    required this.nickname,
    required this.sub,
    required this.provisioned,
    required this.identityBound,
    required this.rebound,
  });

  factory BackendSession.fromJson(Map<String, dynamic> j) => BackendSession(
        token: j['token'] as String? ?? '',
        userId: (j['userId'] as num?)?.toInt() ?? 0,
        email: j['email'] as String? ?? '',
        username: j['username'] as String? ?? '',
        nickname: j['nickname'] as String? ?? '',
        sub: j['sub'] as String? ?? '',
        provisioned: j['provisioned'] as bool? ?? false,
        identityBound: j['identityBound'] as bool? ?? false,
        rebound: j['rebound'] as bool? ?? false,
      );

  bool get isEmpty => token.isEmpty;

  String get displayName {
    final n = nickname.trim();
    if (n.isNotEmpty) return n;
    final u = username.trim();
    if (u.isNotEmpty) return u;
    return email;
  }
}
