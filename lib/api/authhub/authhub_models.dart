/// 认证中心相关的数据模型。
///
/// 字段名一律保留后端的 snake_case（与仓库既有约定一致：后端怎么发就怎么接，
/// 中间加一层驼峰映射只会多一处对不上的地方）。
library;

/// 令牌集（`POST /oauth2/token` 的响应）。
class AuthTokenSet {
  final String accessToken;
  final String? refreshToken;

  /// 认证中心的 access_token 是**不透明随机串**（后端查 oauth_access_tokens 表校验），
  /// 不是 JWT。所以不要试图在本地解析它的有效期或身份 —— 只能问 userinfo。
  final String? idToken;
  final String tokenType;
  final String? scope;

  /// 绝对过期时刻。由 `expires_in`（相对秒）换算而来。
  final DateTime expiresAt;

  const AuthTokenSet({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
    this.idToken,
    this.tokenType = 'Bearer',
    this.scope,
  });

  factory AuthTokenSet.fromJson(Map<String, dynamic> json) {
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 600;
    return AuthTokenSet(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String?,
      idToken: json['id_token'] as String?,
      tokenType: json['token_type'] as String? ?? 'Bearer',
      scope: json['scope'] as String?,
      // 以**本地时钟**为基准换算。认证中心的绝对时间戳拿不到也不该拿：
      // 设备时钟偏差是常态，用相对秒数换算至少不会因时区/格式解析出错。
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  /// 是否已该刷新（含提前量，避免在边界上随机失败）
  bool needsRefresh(Duration skew) =>
      DateTime.now().add(skew).isAfter(expiresAt);

  bool get isEmpty => accessToken.isEmpty;
}

/// 认证中心侧的用户身份（`GET /oauth2/userinfo`）。
class IdpUser {
  final String sub;
  final String? email;

  /// 是否已验证邮箱。认证中心目前恒为 true（注册需邀请码），
  /// 但字段保留：业务后端以邮箱为主键认领账号，这个标志的语义将来会有用。
  final bool emailVerified;
  final String? preferredUsername;
  final String? name;

  const IdpUser({
    required this.sub,
    this.email,
    this.emailVerified = false,
    this.preferredUsername,
    this.name,
  });

  factory IdpUser.fromJson(Map<String, dynamic> json) => IdpUser(
        sub: json['sub'] as String? ?? '',
        email: json['email'] as String?,
        emailVerified: json['email_verified'] as bool? ?? false,
        preferredUsername: json['preferred_username'] as String?,
        name: json['name'] as String?,
      );

  /// 展示名：昵称 > 账号 > sub。
  ///
  /// 兜底到 sub 而不是返回空串：界面上一个空白用户名会让人以为没登录成功。
  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final u = preferredUsername?.trim();
    if (u != null && u.isNotEmpty) return u;
    return sub;
  }

  bool get isEmpty => sub.isEmpty;
}

/// 发现文档里本模块要用的端点。
class OidcEndpoints {
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String userinfoEndpoint;
  final String endSessionEndpoint;

  const OidcEndpoints({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.userinfoEndpoint,
    required this.endSessionEndpoint,
  });

  factory OidcEndpoints.fromJson(Map<String, dynamic> json, String issuer) {
    String pick(String key) {
      final v = json[key] as String?;
      if (v != null && v.isNotEmpty) return v;
      // 发现文档没 advertise 该端点时按 issuer 兜底拼：让失败发生在
      // "认证中心确实没有这个端点"这条明确的路上，而不是本地 null 崩溃。
      final trimmed = issuer.endsWith('/') ? issuer.substring(0, issuer.length - 1) : issuer;
      switch (key) {
        case 'authorization_endpoint':
          return '$trimmed/oauth2/auth';
        case 'token_endpoint':
          return '$trimmed/oauth2/token';
        case 'userinfo_endpoint':
          return '$trimmed/oauth2/userinfo';
        case 'end_session_endpoint':
          return '$trimmed/oauth2/logout';
        default:
          return trimmed;
      }
    }

    return OidcEndpoints(
      authorizationEndpoint: pick('authorization_endpoint'),
      tokenEndpoint: pick('token_endpoint'),
      userinfoEndpoint: pick('userinfo_endpoint'),
      endSessionEndpoint: pick('end_session_endpoint'),
    );
  }
}

/// 扫码票据状态。取值与后端 `entity.QRStatus*` 一一对应，**是契约不是提示**。
enum QrStatus {
  pending,
  scanned,
  confirmed,
  consumed,
  cancelled,
  expired;

  static QrStatus parse(String? raw) => QrStatus.values.firstWhere(
        (s) => s.name == raw,
        // 认不出的状态按 pending 处理而不是抛异常：后端将来加新状态时，
        // 旧版本 App 应该继续等待并允许用户刷新，而不是整个确认页崩掉。
        orElse: () => QrStatus.pending,
      );

  /// 手机端可发起确认的状态（终态与已批准都不行）
  bool get canApprove => this == QrStatus.pending || this == QrStatus.scanned;

  bool get isTerminal =>
      this == QrStatus.consumed ||
      this == QrStatus.cancelled ||
      this == QrStatus.expired;
}

/// `POST /api/qr/sessions` 的结果（PC 侧建的票，本 App 只作为扫码方使用其 URL）。
class QrSession {
  final String ticket;
  final String qrContent;
  final int expiresIn;
  final int intervalMs;

  const QrSession({
    required this.ticket,
    required this.qrContent,
    required this.expiresIn,
    required this.intervalMs,
  });

  factory QrSession.fromJson(Map<String, dynamic> json) => QrSession(
        ticket: json['ticket'] as String? ?? '',
        qrContent: json['qr_content'] as String? ?? '',
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 120,
        intervalMs: (json['interval_ms'] as num?)?.toInt() ?? 1500,
      );
}

/// `GET /api/qr/sessions/{ticket}/preview` —— 手机确认页的全部素材。
///
/// [pc] 是用户点"确认登录"前**唯一**能核对的东西：点下去等价于在另一台机器上
/// 输入自己的密码。所以这个结构缺字段时界面必须拒绝出确认按钮。
class QrPreview {
  final QrStatus status;
  final String pcUa;
  final String pcIp;
  final String pcGeo;
  final String pcCreatedAt;

  const QrPreview({
    required this.status,
    required this.pcUa,
    required this.pcIp,
    required this.pcGeo,
    required this.pcCreatedAt,
  });

  factory QrPreview.fromJson(Map<String, dynamic> json) {
    final pc = json['pc'] as Map<String, dynamic>? ?? const {};
    return QrPreview(
      status: QrStatus.parse(json['status'] as String?),
      pcUa: pc['ua'] as String? ?? '',
      pcIp: pc['ip'] as String? ?? '',
      pcGeo: pc['geo'] as String? ?? '',
      pcCreatedAt: pc['created_at'] as String? ?? '',
    );
  }

  /// 设备画像是否足够让人做出判断。
  ///
  /// 只要 ua 与 ip 全空，就宁可让用户重扫 —— 对着一条无法验证的信息点确认，
  /// 比不给确认按钮更危险。
  bool get hasMeaningfulDeviceInfo =>
      pcUa.trim().isNotEmpty || pcIp.trim().isNotEmpty;
}
