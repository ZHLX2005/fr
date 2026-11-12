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
///   ② verify       拿认证中心的 access_token 换一枚 mn-ws 设备令牌
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

  // ── ② 用认证中心的 access_token 换 mn-ws 设备令牌 ────────────────────────

  /// 用授权码 + verifier 换认证中心的 **access_token**。
  ///
  /// ── 为什么这一步在客户端而不在服务端 ───────────────────────────────────
  /// mn-ws 的 `/auth/verify` 收的是**认证中心的 access_token**（不是授权码）：
  /// 它自己拿这枚令牌去问认证中心「这是谁」（userinfo），再签一枚自己的
  /// 设备令牌。所以换码这一步发生在这个 App 里。
  /// mn-rt 恰好相反 —— 它的服务端收 code，换码在服务端做。两边不能混。
  ///
  /// public client 没有 client_secret，PKCE 就是全部保护：verifier
  /// 只存在于本 App 内存里，从没经过浏览器。
  Future<String> exchangeIdpToken({
    required String code,
    required String codeVerifier,
    required String redirectUri,
    required String clientId,
    required String tokenEndpoint,
  }) async {
    final res = await _send(() => _client
        .post(
          Uri.parse(tokenEndpoint),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          // 用 `.query` 而不是 `.toString()`：后者会带上一个前导 "?"，
          // 请求体就成了 "?grant_type=..." —— 认证中心解不出参数，
          // 症状是「换 token 失败」但看不出是哪一步坏了。
          body: Uri(queryParameters: {
            'grant_type': 'authorization_code',
            'code': code,
            'client_id': clientId,
            'redirect_uri': redirectUri,
            'code_verifier': codeVerifier,
          }).query,
        )
        .timeout(MnWsConfig.tokenTimeout));
    final json = _asJson(res);
    final token = json?['access_token'];
    if (res.statusCode >= 400 || token is! String || token.isEmpty) {
      throw MnWsException(
        MnWsErrorKind.rejected,
        '换 access_token 失败：${(json?['error'] ?? 'HTTP ${res.statusCode}')}',
        status: res.statusCode,
      );
    }
    return token;
  }

  /// 拿 access_token 去 server 半换设备令牌。
  ///
  /// 注意这里传的是**认证中心的 access_token**（Bearer），不是授权码 ——
  /// mn-ws 的 `/auth/verify` 只认令牌：它自己用这枚令牌去问认证中心
  /// 「这是谁」（userinfo），再签一枚自己的设备令牌给本机。
  Future<MnWsGrant> verify({
    required String accessToken,
    required String clientId,
    required String deviceName,
  }) async {
    final res = await _send(() => _client
        .post(
          Uri.parse('$_base/auth/verify'),
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({'clientId': clientId, 'deviceName': deviceName}),
        )
        .timeout(MnWsConfig.httpTimeout));
    final json = _asJson(res);
    if (res.statusCode >= 400 || json == null || json['ok'] != true) {
      throw MnWsException(
        MnWsErrorKind.rejected,
        '换设备令牌失败：${(json?['error'] ?? 'HTTP ${res.statusCode}')}',
        status: res.statusCode,
      );
    }
    return MnWsGrant.fromJson(json);
  }

  // ── ③ 元信息目录 ───────────────────────────────────────────────────────

  /// 服务端支持哪些端口、应用名是什么。
  Future<List<MnWsApp>> catalog() async {
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
    final raw = json['apps'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(MnWsApp.fromJson)
        .where((a) => a.app.isNotEmpty)
        .toList();
  }

  // ── ④ 任意请求 ─────────────────────────────────────────────────────────

  /// 经桥发一个请求。
  ///
  /// [app] 非空时带 `X-Nx-App` 头 —— server 半据此决定「这个请求该去哪个
  /// 本地端口」。**不带这个头且路径里也没有应用前缀 → 400 app_required**。
  ///
  /// [path] 是**应用内部**的路径（如 `/api/repos`）。走应用前缀形式时，
  /// server 半会把前缀剥掉再转发，所以这里传的就是目标服务看到的路径。
  Future<MnWsResponse> request({
    required String method,
    required String path,
    String? app,
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
