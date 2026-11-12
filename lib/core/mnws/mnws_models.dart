import 'dart:convert';

/// mn-ws 的数据形状。
///
/// ── 为什么这里自己解析而不用生成的 api client ────────────────────────────────
/// mn-ws 有两类响应，形状完全不同：
///   · **它自己的端点**（/auth/oidc/config、/auth/verify、/api/catalog）：
///     字段平铺在顶层（`{ok:true, apps:[...]}`）
///   · **被代理的 nx 服务**（/api/repos 等）：`{ok:true, data:...}` 信封
/// 混在一套生成代码里会让「哪一层信封」这件事说不清，所以这里手写解析，
/// 并且**两种形状都如实呈现**（请求 UI 显示原始 body，不替用户猜结构）。

/// mn-ws 的错误类型。
enum MnWsErrorKind {
  /// 服务不可达（网络层失败）
  unreachable,

  /// 没登录 / 凭据无效
  unauthorized,

  /// 服务端有话说（4xx/5xx）
  rejected,

  /// 返回的东西看不懂
  malformed,
}

/// mn-ws 调用失败。
class MnWsException implements Exception {
  final MnWsErrorKind kind;
  final String message;
  final int? status;

  const MnWsException(this.kind, this.message, {this.status});

  @override
  String toString() => 'MnWsException($kind): $message';
}

/// server 半发布的统一登录公开参数（`GET /auth/oidc/config`）。
class MnWsAuthConfig {
  final bool enabled;
  final String issuer;
  /// server 半自己的身份（mn-ws-server）
  final String clientId;
  /// **client 半**的身份（mn-ws-client）—— 真正发起授权码流程的是它
  final String loginClientId;
  final String authorizationEndpoint;
  final String tokenEndpoint;
  final List<String> scopes;
  final bool idpAvailable;

  const MnWsAuthConfig({
    required this.enabled,
    required this.issuer,
    required this.clientId,
    required this.loginClientId,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.scopes,
    required this.idpAvailable,
  });

  factory MnWsAuthConfig.fromJson(Map<String, dynamic> json) {
    List<String> scopeList = const [];
    final rawScopes = json['scopes'];
    if (rawScopes is List) {
      scopeList = rawScopes.map((e) => '$e').where((e) => e.isNotEmpty).toList();
    }
    return MnWsAuthConfig(
      enabled: json['enabled'] == true,
      issuer: '${json['issuer'] ?? ''}',
      clientId: '${json['clientId'] ?? ''}',
      // 老服务端没有这个字段 → 回落 clientId（那时两端是同一个身份）
      loginClientId: '${json['loginClientId'] ?? json['clientId'] ?? ''}',
      authorizationEndpoint: '${json['authorizationEndpoint'] ?? ''}',
      tokenEndpoint: '${json['tokenEndpoint'] ?? ''}',
      scopes: scopeList,
      idpAvailable: json['idpAvailable'] == true,
    );
  }
}

/// mn-ws 设备令牌（server 半自签的 HS256 JWT）。
///
/// 它是 mn-ws 自己的领域凭据：90 天有效、可被服务端按 jti 单独吊销。
class MnWsGrant {
  final String token;
  final String userId;
  final String email;
  final String nickname;
  final String clientId;
  final String deviceName;
  final int? tokenExpiresAt;

  const MnWsGrant({
    required this.token,
    required this.userId,
    required this.email,
    required this.nickname,
    required this.clientId,
    required this.deviceName,
    required this.tokenExpiresAt,
  });

  bool get isExpired {
    final exp = tokenExpiresAt;
    if (exp == null || exp <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch >= exp;
  }

  factory MnWsGrant.fromJson(Map<String, dynamic> json) {
    final exp = json['tokenExpiresAt'];
    return MnWsGrant(
      token: '${json['token'] ?? ''}',
      userId: '${json['userId'] ?? ''}',
      email: '${json['email'] ?? ''}',
      nickname: '${json['nickname'] ?? ''}',
      clientId: '${json['clientId'] ?? ''}',
      deviceName: '${json['deviceName'] ?? ''}',
      tokenExpiresAt: exp is num ? exp.toInt() : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'userId': userId,
        'email': email,
        'nickname': nickname,
        'clientId': clientId,
        'deviceName': deviceName,
        'tokenExpiresAt': tokenExpiresAt,
      };
}

/// 目录里的一条应用（`GET /api/catalog`）。
///
/// 这就是「服务端支持哪些端口、应用名是什么」的答案：
/// server 半把它收到的所有桥的 app 表汇总成一份目录，远端客户端拉它就知道能打谁。
class MnWsApp {
  /// 路由标识：`X-Nx-App` 的值 / 路径前缀
  final String app;
  /// 显示名（动态注册的应用由用户起，server 半不替它猜）
  final String title;
  final int? port;
  final String? base;
  final String bridgeId;
  final String connectedAt;

  const MnWsApp({
    required this.app,
    required this.title,
    required this.port,
    required this.base,
    required this.bridgeId,
    required this.connectedAt,
  });

  factory MnWsApp.fromJson(Map<String, dynamic> json) {
    final port = json['port'];
    return MnWsApp(
      app: '${json['app'] ?? ''}',
      title: '${json['title'] ?? json['app'] ?? ''}',
      port: port is num ? port.toInt() : null,
      base: json['base'] == null ? null : '${json['base']}',
      bridgeId: '${json['bridgeId'] ?? ''}',
      connectedAt: '${json['connectedAt'] ?? ''}',
    );
  }
}

/// 一次请求的结果。
class MnWsResponse {
  final int status;
  final String body;
  final Map<String, String> headers;
  final Duration elapsed;

  const MnWsResponse({
    required this.status,
    required this.body,
    required this.headers,
    required this.elapsed,
  });

  /// 尽量按 JSON 解析一下，解析不了就当纯文本。
  dynamic get json {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}
