import 'dart:convert';
import 'dart:io' show HttpClient, HttpClientResponse;

import 'package:http/http.dart' as http;

import 'authhub_config.dart';
import 'authhub_exception.dart';
import 'authhub_models.dart';
import 'authhub_pkce.dart';

/// 原生表单登录：不打开任何浏览器/WebView，用 HTTP 客户端把 OIDC 流程走完。
///
/// ── 为什么可以做，以及代价 ──────────────────────────────────────────────
///
/// 标准 OIDC 让移动客户端跳浏览器，是为了让 App 永远看不到口令。
/// 这里选择"原生表单"，就是明确放弃那条性质，换取纯原生的界面与体验。
/// 已知的代价，写在这里而不是藏在某次提交里：
///   1. 口令会经过 App 的内存与日志边界（下面刻意做了约束，见"口令的处理"）；
///   2. 当前认证中心是 http 明文部署，口令在公网这一段是裸传的。
/// 将来若上 HTTPS，第 2 条消失；第 1 条是"原生表单"这个选择本身的固有代价。
///
/// ── 为什么不新增一个"一步换 token"的服务端端点 ──────────────────────────
///
/// 那看起来更简单，但要在认证中心里新写一条绕过授权确认页的路径，
/// 等于把 client/redirect_uri/PKCE 那套校验重新实现一遍 —— 而它是整个
/// OIDC 实现里最不能出错的部分。这里复用已审计过的真实端点，
/// App 只是扮演了一个"没有界面的浏览器"。
///
/// ── 流程 ───────────────────────────────────────────────────────────────
///
///   ① POST /api/login        → 拿到 idp_session Cookie
///   ② GET  /oauth2/auth?...  → 302 到 /consent?<原始授权参数>
///   ③ POST /api/consent      → {redirect_to}，里面带 code
///   ④ POST /oauth2/token     → code + code_verifier 换令牌
///
/// ② ③ 都不自动跟随重定向：要的就是那个 Location / redirect_to，
/// 而 ④ 之前的任何一步都不该真的把 code 送到 redirect_uri 上去。
class AuthHubNativeLoginFlow {
  final http.Client _client;
  final String _issuer;

  /// 本流程专用的 Cookie 容器（只装 idp_session）。
  final Map<String, String> _cookies = {};

  AuthHubNativeLoginFlow({http.Client? client, String? issuer})
    : _client = client ?? _noRedirectClient(),
      _issuer = (issuer ?? AuthHubConfig.issuer).replaceAll(RegExp(r'/+$'), '');

  /// 一个**不自动跟随重定向**的 HTTP 客户端。
  ///
  /// 这不是可选优化，而是这条流程能否成立的前提：`http.Client()` 默认自己跟 302，
  /// 于是 ② 拿回来的是 /consent 页面的 200 HTML，Location 里的授权参数被吞掉，
  /// 流程连"要确认什么"都读不到。实测症状就是
  /// `authorize_unexpected_status: http 200` —— 一个看不出根因的报错。
  ///
  /// 也不用 IOClient 包一层：`followRedirects` 挂在 **HttpClientRequest** 上而不是
  /// HttpClient 上，package:http 不暴露那个对象。所以这里直接用 dart:io，
  /// 自己实现 http.Client 需要的 send()，换取对重定向的完全控制。
  static http.Client _noRedirectClient() => _NoRedirectClient();

  /// 一次原生登录得到的令牌集。
  Future<AuthTokenSet> signInWithPassword({
    required String username,
    required String password,
  }) async {
    final pkce = AuthPkce.generate();
    final port = 30000 + (DateTime.now().microsecondsSinceEpoch % 20000);
    final redirectUri = AuthHubConfig.redirectUriFor(port);

    await _login(pkce, username, password);
    final consentQuery = await _authorize(pkce, redirectUri);
    final code = await _consent(pkce, redirectUri, consentQuery);
    return _exchange(pkce, redirectUri, code);
  }

  // ── ① 口令 ────────────────────────────────────────────────────────────

  Future<void> _login(AuthPkce pkce, String username, String password) async {
    final resp = await _send(
      'POST',
      AuthHubConfig.loginPath,
      jsonBody: {'username': username, 'password': password, 'return_to': ''},
    );
    final body = _decode(resp);
    _absorbCookies(resp);

    if (resp.statusCode != 200 || (body['code'] ?? 0) != 0) {
      // 把后端的可分支原因原样带出去：账号不存在 / 口令错误 / 参数问题，
      // 界面上必须是三句不同的话。合成一句"登录失败"会让人反复试错。
      throw AuthHubException(
        error: body['error'] as String? ?? 'login_failed',
        message: body['message'] as String? ?? '登录失败（HTTP ${resp.statusCode}）',
        statusCode: resp.statusCode,
      );
    }
    if ((_cookies[AuthHubConfig.sessionCookieName] ?? '').isEmpty) {
      // 200 但没发会话 Cookie：说明后端行为变了（比如改成了别的 Cookie 名），
      // 继续往下走只会在 authorize 那步拿到一个莫名的 302 到登录页。
      throw const AuthHubException(
        error: AuthHubException.errBadResponse,
        message: '登录成功但未获得会话凭据',
      );
    }
  }

  // ── ② 授权请求 ────────────────────────────────────────────────────────

  /// 返回 302 指向的 /consent 查询串（即原始授权参数）。
  Future<Map<String, String>> _authorize(
    AuthPkce pkce,
    String redirectUri,
  ) async {
    final query = <String, String>{
      'response_type': 'code',
      'client_id': AuthHubConfig.clientId,
      'redirect_uri': redirectUri,
      'scope': AuthHubConfig.scopes.join(' '),
      'state': pkce.state,
      'nonce': pkce.nonce,
      ...pkce.challengeParams,
    };
    final uri = Uri.parse(
      '$_issuer${AuthHubConfig.authPath}',
    ).replace(queryParameters: query);

    final resp = await _getRaw(uri);
    if (resp.statusCode != 302 && resp.statusCode != 303) {
      throw AuthHubException(
        error: 'authorize_unexpected_status',
        message:
            '授权端点返回 HTTP ${resp.statusCode}，未跳转'
            '（多半是会话未被识别，或 client/redirect_uri 不在白名单）',
        statusCode: resp.statusCode,
      );
    }
    final loc = resp.headers['location'] ?? '';
    if (!loc.contains('/consent')) {
      // 被送回 /login 意味着 ① 拿到的会话没被认出来
      throw AuthHubException(
        error: 'session_not_recognized',
        message: loc.contains('/login')
            ? '认证中心未识别本次登录会话，请重试'
            : '授权跳转指向了意外的地址：$loc',
      );
    }
    final q = loc.contains('?') ? loc.substring(loc.indexOf('?') + 1) : '';
    return Uri.splitQueryString(q);
  }

  // ── ③ 授权确认 ────────────────────────────────────────────────────────

  /// 把 ② 拿到的参数原样回填，提交 decision=allow，取回带 code 的 redirect_to。
  Future<String> _consent(
    AuthPkce pkce,
    String redirectUri,
    Map<String, String> fromAuthorize,
  ) async {
    final resp = await _send(
      'POST',
      AuthHubConfig.consentPath,
      jsonBody: {
        'client_id': fromAuthorize['client_id'] ?? AuthHubConfig.clientId,
        'redirect_uri': fromAuthorize['redirect_uri'] ?? redirectUri,
        'scope': fromAuthorize['scope'] ?? AuthHubConfig.scopes.join(' '),
        'state': fromAuthorize['state'] ?? pkce.state,
        'nonce': fromAuthorize['nonce'] ?? pkce.nonce,
        'code_challenge': fromAuthorize['code_challenge'] ?? pkce.codeChallenge,
        'code_challenge_method':
            fromAuthorize['code_challenge_method'] ?? 'S256',
        'decision': 'allow',
      },
    );
    // /api/consent 返回的是**裸对象**（没有 code 字段），不能按信封解析
    final body = _decode(resp);
    if (resp.statusCode != 200) {
      throw AuthHubException(
        error: body['error'] as String? ?? 'consent_failed',
        message:
            body['error_description'] as String? ??
            body['message'] as String? ??
            '授权确认失败（HTTP ${resp.statusCode}）',
        statusCode: resp.statusCode,
      );
    }
    final redirectTo = body['redirect_to'] as String? ?? '';
    if (redirectTo.isEmpty) {
      throw const AuthHubException(
        error: AuthHubException.errNoCode,
        message: '授权确认未返回回调地址',
      );
    }
    // 刻意不请求 redirect_to：那是 http://127.0.0.1:<随机端口>/callback，
    // 本机并没有服务在听。要的东西全在这串 URL 里。
    final params = Uri.parse(redirectTo).queryParameters;
    if ((params['state'] ?? '') != pkce.state) {
      throw const AuthHubException(
        error: AuthHubException.errStateMismatch,
        message: '回调 state 与发起时不一致，已中止',
      );
    }
    final code = params['code'] ?? '';
    if (code.isEmpty) {
      throw AuthHubException(
        error: params['error'] ?? AuthHubException.errNoCode,
        message: '回调未携带 code：$redirectTo',
      );
    }
    return code;
  }

  // ── ④ 换令牌 ──────────────────────────────────────────────────────────

  Future<AuthTokenSet> _exchange(
    AuthPkce pkce,
    String redirectUri,
    String code,
  ) async {
    final resp = await _postForm('$_issuer${AuthHubConfig.tokenPath}', {
      'grant_type': 'authorization_code',
      'code': code,
      'client_id': AuthHubConfig.clientId,
      'redirect_uri': redirectUri,
      'code_verifier': pkce.codeVerifier,
    });
    final body = _decode(resp);
    if (resp.statusCode >= 400 || body.containsKey('error')) {
      throw AuthHubException(
        error: body['error'] as String? ?? 'http_${resp.statusCode}',
        message: body['error_description'] as String? ?? '换取令牌失败',
        statusCode: resp.statusCode,
      );
    }
    final set = AuthTokenSet.fromJson(body);
    if (set.isEmpty) {
      throw const AuthHubException(
        error: AuthHubException.errBadResponse,
        message: '令牌响应里没有 access_token',
      );
    }
    return set;
  }

  // ── 传输 ──────────────────────────────────────────────────────────────

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? jsonBody,
  }) {
    final uri = Uri.parse('$_issuer$path');
    final req = http.Request(method, uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (_cookies.isNotEmpty)
          'Cookie': _cookies.entries
              .map((e) => '${e.key}=${e.value}')
              .join('; '),
      });
    if (jsonBody != null) req.body = jsonEncode(jsonBody);
    return _dispatch(req);
  }

  Future<http.Response> _getRaw(Uri uri) {
    final req = http.Request('GET', uri)
      ..headers.addAll({
        if (_cookies.isNotEmpty)
          'Cookie': _cookies.entries
              .map((e) => '${e.key}=${e.value}')
              .join('; '),
      });
    return _dispatch(req);
  }

  Future<http.Response> _postForm(String url, Map<String, String> fields) {
    final req = http.Request('POST', Uri.parse(url))
      ..headers.addAll({'Content-Type': 'application/x-www-form-urlencoded'})
      ..bodyFields = fields;
    return _dispatch(req);
  }

  /// 关键：**不跟随重定向**。
  ///
  /// http.Client 默认会跟 302，而 ② 那一步要的恰恰是 Location 本身。
  /// 跟下去会变成"请求 /consent 页面"，拿不到授权参数，流程直接断。
  Future<http.Response> _dispatch(http.Request req) async {
    final streamed = await _client.send(req).timeout(AuthHubConfig.httpTimeout);
    return http.Response.fromStream(streamed);
  }

  Map<String, dynamic> _decode(http.Response resp) {
    try {
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      if (d is Map<String, dynamic>) return d;
      throw const FormatException('not an object');
    } catch (_) {
      throw AuthHubException(
        error: AuthHubException.errBadResponse,
        message: '响应不是 JSON（HTTP ${resp.statusCode}）',
        statusCode: resp.statusCode,
      );
    }
  }

  void _absorbCookies(http.Response resp) {
    final raw = resp.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    for (final line in raw.split('\n')) {
      final pair = line.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      _cookies[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
    }
  }

  void close() {
    _cookies.clear();
    // IOClient.close() 会一并 release 底层 HttpClient；换成裸 http.Client 时
    // 它也只是关掉自己。不关的话每次登录泄漏一个连接池。
    _client.close();
  }
}

/// 只做一件事：把请求发出去，**不跟重定向**，把 3xx 原样交回。
class _NoRedirectClient extends http.BaseClient {
  final HttpClient _inner = HttpClient()
    // 认证中心当前是 http 明文，无需任何证书相关配置；
    // 连接超时给 10 秒，与 AuthHubConfig.httpTimeout 同一量级。
    ..connectionTimeout = const Duration(seconds: 10);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = await _inner.openUrl(request.method, request.url);
    // 关键的一行：关掉自动跟随，302 才会作为响应回到我们手里
    req.followRedirects = false;
    request.headers.forEach((k, v) => req.headers.set(k, v));
    if (request is http.Request && request.body.isNotEmpty) {
      req.write(request.body);
    }
    final resp = await req.close();
    return http.StreamedResponse(
      resp,
      resp.statusCode,
      // chunked 响应时 dart:io 给的是 -1，而 http.BaseResponse 明确拒绝负数
      // （"Invalid content length -1"）。长度未知就该传 null，不是 -1。
      contentLength: resp.contentLength >= 0 ? resp.contentLength : null,
      request: request,
      headers: _flattenHeaders(resp),
      reasonPhrase: resp.reasonPhrase,
      isRedirect: resp.isRedirect,
    );
  }

  @override
  void close() => _inner.close(force: true);

  /// 把 dart:io 的 HttpHeaders 摊平成 package:http 期望的字符串键值对。
  ///
  /// set-cookie 必须特殊处理：一个响应可以有多条（本流程就会同时收到
  /// idp_session 与其它 Cookie），而 HttpHeaders.forEach 会把它们给成
  /// 一个 List。这里用换行拼接，与 _absorbCookies 的按行拆分是配对的 ——
  /// 若改成 "; " 或直接取第一条，就会只认到一个 Cookie，
  /// 症状是「登录成功但未获得会话凭据」，看不出根因。
  Map<String, String> _flattenHeaders(HttpClientResponse resp) {
    final out = <String, String>{};
    resp.headers.forEach((name, values) {
      out[name] = name == 'set-cookie' ? values.join('\n') : values.join(', ');
    });
    return out;
  }
}
