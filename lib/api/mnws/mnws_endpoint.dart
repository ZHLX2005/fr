import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mnws_config.dart';
import 'mnws_models.dart';

/// mn-ws server 半的调用端点。
///
/// ── 凭据从哪来 ────────────────────────────────────────────────────────────
/// 门禁凭据（`X-Mn-Ws-Token`）由 [grantReader] 提供，**不出现在方法签名里**：
/// 签名里一旦有 token 形参，调用方传错哪一种字符串都能通过类型检查，
/// 要到运行时才炸（同 authhub 那侧的教训）。
///
/// ── 四类调用 ──────────────────────────────────────────────────────────────
///   ① authConfig   问 server 半「你连的是哪个认证中心、用哪个 client 登录」
///   ② exchangeCode 授权码 → **mn-ws 自己**的令牌（换码在服务端做）
///   ③ catalog      拉元信息目录（服务端支持哪些端口、应用名是什么）
///   ④ request      任意路径请求（自动带上门禁头与应用标识头）
class MnWsEndpoint {
  MnWsEndpoint({
    http.Client? client,
    String? baseUrl,
    required this.grantReader,
  })  : _client = client ?? http.Client(),
        _base = (baseUrl ?? MnWsConfig.baseUrl).replaceAll(RegExp(r'/+$'), '');

  final http.Client _client;
  final String _base;

  /// 当前有效凭据的来源。返回 null = 还没登录。
  final Future<MnWsGrant?> Function() grantReader;

  // ── ① server 半的公开参数 ──────────────────────────────────────────────

  Future<MnWsAuthConfig> authConfig() async {
    final res = await _send(() => _client.get(
      Uri.parse('$_base/auth/oidc/config'),
      headers: const {'Accept': 'application/json'},
    ).timeout(MnWsConfig.httpTimeout));
    final json = _asJson(res);
    if (json == null) {
      throw const MnWsException(
        MnWsErrorKind.malformed,
        '认证参数不是合法 JSON',
      );
    }
    return MnWsAuthConfig.fromJson(json);
  }

  // ── ② 授权码 → mn-ws 自己的令牌（业务令牌端点）─────────────────────────

  /// 用授权码 + PKCE verifier 换**本服务**的令牌。
  ///
  /// ── 为什么换码在服务端，不在客户端 ───────────────────────────────────
  /// mn-ws 的服务端提供了 `/auth/oidc/callback`：它拿 **client 半的身份**
  /// （`mn-ws-client`）去认证中心换码，再签一枚**mn-ws 自己**的令牌回来。
  /// 认证中心那张 access_token / refresh_token **一次都不出服务端** ——
  /// 那两枚凭据指向的是整个平台的身份，一旦流经手机，截获即等于账号接管。
  ///
  /// 这与 mn-rt 是同一套形状：「统一登录的登录态 → 铸码 → 业务服务自己的
  /// 令牌端点 → 业务服务的令牌」。业务令牌天然归属业务方，客户端只认业务方。
  ///
  /// public client 没有 client_secret，PKCE 就是全部保护：verifier
  /// 只存在于本 App 内存里，从没经过浏览器。
  Future<MnWsGrant> exchangeCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
    String deviceName = '',
  }) async {
    final res = await _send(() => _client
        .post(
          Uri.parse('$_base${MnWsConfig.callbackPath}'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'code': code,
            'codeVerifier': codeVerifier,
            'redirectUri': redirectUri,
            // 手机端不登记成「一台桥」：不带 clientId，服务端因此签一枚
            // 不绑定设备的用户令牌 —— 它代表身份，不代表某台机器。
            if (deviceName.isNotEmpty) 'deviceName': deviceName,
          }),
        )
        .timeout(MnWsConfig.httpTimeout));
    final json = _asJson(res);
    if (res.statusCode >= 400 || json == null || json['ok'] != true) {
      throw MnWsException(
        MnWsErrorKind.rejected,
        '换业务令牌失败：${(json?['error'] ?? 'HTTP ${res.statusCode}')}',
        status: res.statusCode,
      );
    }
    final grant = MnWsGrant.fromJson(json);
    if (grant.token.isEmpty) {
      throw const MnWsException(
        MnWsErrorKind.rejected,
        '服务端未返回可用凭据',
      );
    }
    return grant;
  }

  // ── ③ 元信息目录 ───────────────────────────────────────────────────────

  /// 服务端支持哪些端口、应用名是什么 —— **按 PC 分组**。
  ///
  /// 多台 PC 同时接入时，`pcs[]` 给出「每台电脑 + 它上面的应用」；
  /// `apps[]` 是同一份内容的扁平形态（老服务端没有 pcs 时的回落）。
  Future<MnWsCatalog> catalog() async {
    final grant = await grantReader();
    if (grant == null) {
      throw const MnWsException(
        MnWsErrorKind.unauthorized,
        '还没有 mn-ws 的凭据，请先登录',
      );
    }
    final res = await _send(() => _client.get(
      Uri.parse('$_base/api/catalog'),
      headers: {
        'Accept': 'application/json',
        MnWsConfig.gateHeader: grant.token,
      },
    ).timeout(MnWsConfig.httpTimeout));
    final json = _asJson(res);
    if (res.statusCode >= 400 || json == null || json['ok'] != true) {
      throw MnWsException(
        MnWsErrorKind.rejected,
        '拉目录失败：${(json?['error'] ?? 'HTTP ${res.statusCode}')}',
        status: res.statusCode,
      );
    }
    return MnWsCatalog.fromJson(json);
  }

  // ── ④ 任意请求 ─────────────────────────────────────────────────────────

  /// 经桥发一个请求。
  ///
  /// [app] 非空时带 `X-Mn-Ws-App` 头 —— server 半据此决定「这个请求该去哪个
  /// 本地端口」。**不带这个头且路径里也没有应用前缀 → 400 app_required**。
  ///
  /// [pc] 是**目标 PC 的 bridgeId**（多台 PC 都跑同名应用时用）。
  /// 不带就按路由表走（撞名时后来者接管）。
  ///
  /// [path] 是**应用内部**的路径（如 `/api/repos`）。走应用前缀形式时，
  /// server 半会把前缀剥掉再转发，所以这里传的就是目标服务看到的路径。
  Future<MnWsResponse> request({
    required String method,
    required String path,
    String? app,
    String? pc,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final grant = await grantReader();
    if (grant == null) {
      throw const MnWsException(
        MnWsErrorKind.unauthorized,
        '还没有 mn-ws 的凭据，请先登录',
      );
    }
    final uri = Uri.parse('$_base${path.startsWith('/') ? path : '/$path'}');
    final allHeaders = <String, String>{
      'Accept': 'application/json',
      MnWsConfig.gateHeader: grant.token,
      if (app != null && app.isNotEmpty) MnWsConfig.appHeader: app,
      if (pc != null && pc.isNotEmpty) MnWsConfig.pcHeader: pc,
      ...headers,
    };

    final stopwatch = Stopwatch()..start();
    final res = await _send(() {
      final req = http.Request(method.toUpperCase(), uri)..headers.addAll(allHeaders);
      if (body != null && body.isNotEmpty) req.body = body;
      return _client.send(req).timeout(MnWsConfig.httpTimeout);
    });
    stopwatch.stop();

    final text = await res.stream.bytesToString();
    final flat = <String, String>{};
    // package:http 的响应头是 Map<String, String>（多值头已并成一个串）
    res.headers.forEach((k, v) => flat[k] = v);
    return MnWsResponse(
      status: res.statusCode,
      body: text,
      headers: flat,
      elapsed: stopwatch.elapsed,
    );
  }

  // ── 传输 ───────────────────────────────────────────────────────────────

  /// 统一处理超时与网络层失败。
  ///
  /// 泛型是因为有两种响应：普通调用拿到 [http.Response]，
  /// 要带 body 的调用走 [http.StreamedResponse]（读 body 前不能提前关连接）。
  Future<T> _send<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on TimeoutException {
      throw const MnWsException(MnWsErrorKind.unreachable, 'mn-ws 服务响应超时');
    } catch (e) {
      if (e is MnWsException) rethrow;
      throw MnWsException(
        MnWsErrorKind.unreachable,
        '连不上 mn-ws 服务：$e',
      );
    }
  }

  Map<String, dynamic>? _asJson(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
