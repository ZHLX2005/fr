import 'dart:convert';

/// mn-ws 的数据形状。
///
/// ── 为什么这里自己解析而不用生成的 api client ────────────────────────────────
/// mn-ws 有两类响应，形状完全不同：
///   · **它自己的端点**（/auth/oidc/config、/auth/oidc/callback、/api/catalog）：
///     字段平铺在顶层（`{ok:true, apps:[...]}`）
///   · **被代理的服务**（如 nx-kv 的 /api/repos）：`{ok:true, data:...}` 信封
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

/// mn-ws 的业务令牌（server 半自签的 HS256 JWT）。
///
/// 它是 mn-ws 自己的领域凭据：90 天有效、可被服务端按 jti 单独吊销。
/// 由 `POST /auth/oidc/callback` 换得 —— 换码在服务端做，认证中心的
/// access_token / refresh_token 不出服务端。
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
  /// 路由标识：`X-Mn-Ws-App` 的值 / 路径前缀
  final String app;
  /// 显示名（动态注册的应用由用户起，server 半不替它猜）
  final String title;
  final int? port;
  final String? base;
  final String bridgeId;
  final String connectedAt;

  /// 这台 PC 的**电脑名**（注册时 client 自报）。
  final String pcName;

  /// 这个 app 名当前**路由不到**这台 PC（被别的 PC 顶替了）。
  ///
  /// 说清楚比不说好：否则用户会以为「目录里有就能打」。
  final bool pcNameMissing;

  const MnWsApp({
    required this.app,
    required this.title,
    required this.port,
    required this.base,
    required this.bridgeId,
    required this.connectedAt,
    this.pcName = '',
    this.pcNameMissing = false,
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
      pcName: '${json['pcName'] ?? ''}',
      pcNameMissing: json['pcNameMissing'] == true,
    );
  }
}

/// 目录里的一个 **PC 分组**（`GET /api/catalog` 的 `pcs[]`）。
///
/// 多台 PC 同时接入时，用户想看的不是一长串应用，而是
/// 「我有哪几台电脑，每台上跑着什么」—— 所以目录按 PC 分组。
class MnWsPcGroup {
  /// 这台 PC 的标识（bridgeId）。
  final String bridgeId;

  /// **电脑名**（client 注册时自报；多台 PC 同时接入时靠它区分）。
  final String name;

  /// 属主（userId；门禁是 `@gate`）。
  final String userId;

  final String connectedAt;

  /// 这台 PC 上登记的应用。
  final List<MnWsPcApp> apps;

  const MnWsPcGroup({
    required this.bridgeId,
    required this.name,
    required this.userId,
    required this.connectedAt,
    required this.apps,
  });

  factory MnWsPcGroup.fromJson(Map<String, dynamic> json) {
    final rawApps = json['apps'];
    final apps = <MnWsPcApp>[];
    if (rawApps is List) {
      for (final e in rawApps) {
        if (e is Map<String, dynamic>) apps.add(MnWsPcApp.fromJson(e));
      }
    }
    return MnWsPcGroup(
      bridgeId: '${json['bridgeId'] ?? ''}',
      name: '${json['name'] ?? json['bridgeId'] ?? ''}',
      userId: '${json['userId'] ?? ''}',
      connectedAt: '${json['connectedAt'] ?? ''}',
      apps: apps,
    );
  }
}

/// PC 分组里的一个应用。
class MnWsPcApp {
  final String app;
  final String title;
  final int? port;
  final String? base;
  final String bridgeId;

  /// 这个 app 名当前**路由到**这台 PC 吗？
  ///
  /// 两台 PC 跑同名 app 时，路由归后来者 —— 另一台就「看得见、打不到」。
  /// 这个标记让界面能如实说出来。
  final bool active;

  /// 本机服务是否在监听（client 探测上报；老服务端没有这个字段 → 按 true 算）。
  ///
  /// 「注册了」与「跑着」是两回事：注册了就该显示，没跑如实标出来。
  final bool alive;

  const MnWsPcApp({
    required this.app,
    required this.title,
    required this.port,
    required this.base,
    required this.bridgeId,
    required this.active,
    this.alive = true,
  });

  factory MnWsPcApp.fromJson(Map<String, dynamic> json) {
    final port = json['port'];
    return MnWsPcApp(
      app: '${json['app'] ?? ''}',
      title: '${json['title'] ?? json['app'] ?? ''}',
      port: port is num ? port.toInt() : null,
      base: json['base'] == null ? null : '${json['base']}',
      bridgeId: '${json['bridgeId'] ?? ''}',
      active: json['active'] != false,
      alive: json['alive'] != false,
    );
  }

  /// 转成扁平目录里的那条应用（`MnWsApp`）。
  MnWsApp toApp({String pcName = '', String connectedAt = ''}) => MnWsApp(
        app: app,
        title: title,
        port: port,
        base: base,
        bridgeId: bridgeId,
        connectedAt: connectedAt,
        pcName: pcName,
        pcNameMissing: !active,
      );
}

/// 远端目录（`GET /api/catalog`）。
///
/// 两份视图：
///   · [pcs] —— 按 PC 分组（多台 PC 同时接入时的主要视图）
///   · [apps] —— 扁平列表（老服务端没有 pcs 时的回落）
class MnWsCatalog {
  final List<MnWsApp> apps;
  final List<MnWsPcGroup> pcs;

  const MnWsCatalog({this.apps = const [], this.pcs = const []});

  factory MnWsCatalog.fromJson(Map<String, dynamic> json) {
    final rawApps = json['apps'];
    final apps = <MnWsApp>[];
    if (rawApps is List) {
      for (final e in rawApps) {
        if (e is Map<String, dynamic>) apps.add(MnWsApp.fromJson(e));
      }
    }
    final rawPcs = json['pcs'];
    final pcs = <MnWsPcGroup>[];
    if (rawPcs is List) {
      for (final e in rawPcs) {
        if (e is Map<String, dynamic>) pcs.add(MnWsPcGroup.fromJson(e));
      }
    }
    return MnWsCatalog(apps: apps, pcs: pcs);
  }

  /// 目录里一共有几个应用（分组视图优先）。
  int get count => pcs.isNotEmpty
      ? pcs.fold(0, (n, g) => n + g.apps.length)
      : apps.length;
}

/// 一次请求的结果。
class MnWsResponse {  final int status;
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
