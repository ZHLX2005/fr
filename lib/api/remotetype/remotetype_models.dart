// lib/api/remotetype/remotetype_models.dart
//
// 远程输入桥的数据模型。全部是解析裸 JSON 的不可变值对象。

/// 服务端的统一登录公开参数（GET /auth/oidc/config）。
class RtAuthConfig {
  const RtAuthConfig({
    required this.enabled,
    required this.idpAvailable,
    required this.issuer,
    required this.clientId,
    required this.redirectUri,
    required this.scopes,
    required this.authorizationEndpoint,
  });

  /// 服务端是否开启统一登录。false → UI 退回手工配对 key。
  final bool enabled;

  /// 服务端**自己**是否连上了认证中心（它拉到发现文档才是 true）。
  ///
  /// 这个字段必须由客户端读并显示，而不能只看"请求成功"：
  /// 服务端连不上认证中心时接口照样 200 返回，表现是"点了登录没反应"。
  final bool idpAvailable;

  final String issuer;
  final String clientId;

  /// 授权码绑定的回调地址。**由服务端决定，客户端一律原样回传**。
  ///
  /// 它必须逐字命中该 client 在认证中心的白名单，而白名单形状（回环 + 固定路径）
  /// 是服务端的部署事实。客户端抄一份常量早晚和它漂移，
  /// 且漂移的表现是 authorize 一直 400，离真因由隔了三次跳转。
  final String redirectUri;
  final List<String> scopes;
  final String authorizationEndpoint;

  factory RtAuthConfig.fromJson(Map<String, dynamic> j) => RtAuthConfig(
        enabled: j['enabled'] == true,
        idpAvailable: j['idpAvailable'] == true,
        issuer: (j['issuer'] ?? '') as String,
        clientId: (j['clientId'] ?? '') as String,
        redirectUri: (j['redirectUri'] ?? '') as String,
        scopes: ((j['scopes'] as List?) ?? const ['openid', 'profile', 'email'])
            .map((e) => e.toString())
            .toList(),
        authorizationEndpoint: (j['authorizationEndpoint'] ?? '') as String,
      );
}

/// 一次授权换来的本服务凭据。
///
/// 只有 `token`（本服务自签的设备/用户令牌）与 `sessionKey`（会话密钥）值得留存。
/// 认证中心的 access_token / refresh_token 一律不在这里出现——它们在换到
/// 这两个值的那一瞬间就已经用完，留下任何一个都是把"谁拿到谁可用"的凭据
/// 复制到手机上，而 refresh_token 尤其会把用户永久挡在认证中心之外。
class RtGrant {
  const RtGrant({
    required this.token,
    required this.userId,
    required this.expiresAtMs,
    this.sessionKey = '',
    this.email = '',
    this.nickname = '',
    this.username = '',
  });

  final String token;
  final String userId;

  /// 令牌到期时间（epoch 毫秒）。0 = 服务端没给。
  final int expiresAtMs;

  /// PC 的会话密钥（十六进制）。手机端**不从这里拿** key，
  /// 每台电脑的 key 在 [RtComputer.sessionKey] 上——同一账号下可能有多把。
  final String sessionKey;

  final String email;
  final String nickname;
  final String username;

  bool get isExpired {
    if (expiresAtMs == 0) return false;
    return DateTime.now().millisecondsSinceEpoch >= expiresAtMs;
  }

  String get displayName {
    for (final v in [nickname, username, email]) {
      if (v.trim().isNotEmpty) return v.trim();
    }
    return userId;
  }

  factory RtGrant.fromJson(Map<String, dynamic> j) => RtGrant(
        token: (j['token'] ?? '') as String,
        userId: ((j['userId'] ?? j['sub']) ?? '') as String,
        expiresAtMs: (j['tokenExpiresAt'] as num?)?.toInt() ?? 0,
        sessionKey: (j['sessionKey'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        nickname: (j['nickname'] ?? '') as String,
        username: (j['username'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'userId': userId,
        'tokenExpiresAt': expiresAtMs,
        'sessionKey': sessionKey,
        'email': email,
        'nickname': nickname,
        'username': username,
      };
}

/// 我名下的一台电脑。
class RtComputer {
  const RtComputer({
    required this.clientId,
    required this.deviceName,
    required this.sessionKey,
    required this.online,
  });

  final String clientId;
  final String deviceName;

  /// 这台电脑的会话密钥。它就是旧流程里要人手复制的那个配对 key，
  /// 区别只是现在由服务端按属主发给同一账号下的手机。
  final String sessionKey;

  /// 电脑当前是否在线（PC 的 serve 是否连着）。
  final bool online;

  factory RtComputer.fromJson(Map<String, dynamic> j) => RtComputer(
        clientId: (j['clientId'] ?? '') as String,
        deviceName: (j['deviceName'] ?? '') as String,
        sessionKey: (j['sessionKey'] ?? '') as String,
        online: j['online'] == true,
      );

  String get label => deviceName.isEmpty ? clientId : deviceName;
}
