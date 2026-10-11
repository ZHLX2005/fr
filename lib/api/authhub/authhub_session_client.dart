import 'dart:convert';
import 'dart:io' show HttpClient, HttpClientResponse;

import 'package:http/http.dart' as http;

import 'authhub_config.dart';
import 'authhub_exception.dart';
import 'idp_session_store.dart';

/// 一次登录得到的身份（来自认证中心 `GET /api/me`）。
class IdpIdentity {
  final int id;
  final String username;
  final String nickname;
  final String email;

  const IdpIdentity({
    required this.id,
    required this.username,
    required this.nickname,
    required this.email,
  });

  factory IdpIdentity.fromJson(Map<String, dynamic> j) => IdpIdentity(
        id: (j['id'] as num?)?.toInt() ?? 0,
        username: j['username'] as String? ?? '',
        nickname: j['nickname'] as String? ?? '',
        email: j['email'] as String? ?? '',
      );

  String get displayName {
    final n = nickname.trim();
    if (n.isNotEmpty) return n;
    final u = username.trim();
    if (u.isNotEmpty) return u;
    return email;
  }
}

/// 为某个依赖方换到的一次性授权码。
///
/// 只带 code 与 state：code 是一次性的，state 由发起方自己校验。
/// **不带任何 token** —— 本 App 不是依赖方，它不消费授权码，
/// 只是把码转交给真正的依赖方（业务后端）去换。
class IssuedCode {
  final String code;
  final String state;
  const IssuedCode({required this.code, required this.state});
}

/// 统一登录平台的会话客户端。
///
/// 它做三件事：口令登录拿登录态、查"我是谁"、以及**用登录态为某个依赖方
/// 静默换一个授权码**。第三件是本 App 能"不重输密码就拿到业务后端 token"的关键。
///
/// ── 为什么第三件是"换 code"而不是"换 token" ──────────────────────────────
///
/// 授权码是给依赖方（业务后端）用的，业务后端拿它去认证中心换 token 时
/// 用的是**它自己的 client 身份和 PKCE verifier**，与本 App 无关。
/// 本 App 既不需要、也不应该持有那批 token —— 一旦持有，就又变成
/// "一枚凭据兼两个用途"的老问题。
///
/// 所以这里的分工是：App 负责"证明这台设备已登录"，业务后端负责"据此领自己的 token"。
class AuthHubSessionClient {
  final http.Client _client;
  final IdpSessionStore _store;
  final String _issuer;

  AuthHubSessionClient({
    required IdpSessionStore store,
    http.Client? client,
    String? issuer,
  })  : _store = store,
        _client = client ?? _NoRedirectClient(),
        _issuer = (issuer ?? AuthHubConfig.issuer).replaceAll(RegExp(r'/+$'), '');

  /// 口令登录，成功即把登录态持久化。
  ///
  /// 口令只在本次调用内存在：不写日志、不进异常消息、不缓存成字段。
  Future<IdpIdentity> signInWithPassword({
    required String username,
    required String password,
  }) async {
    final resp = await _send('POST', AuthHubConfig.loginPath, jsonBody: {
      'username': username,
      'password': password,
      'return_to': '',
    });
    final body = _decode(resp);
    _absorbSession(resp);

    if (resp.statusCode != 200 || (body['code'] ?? 0) != 0) {
      throw AuthHubException(
        // 后端区分 user_not_found / wrong_password，原样带出去：
        // 合成一句"登录失败"会让人对着密码框反复试。
        error: body['error'] as String? ?? 'login_failed',
        message: body['message'] as String? ?? '登录失败（HTTP ${resp.statusCode}）',
        statusCode: resp.statusCode,
      );
    }
    if ((await _store.read()).isNullOrEmpty) {
      // 200 却没拿到会话：后端多半改了 Cookie 名。继续往下走只会在
      // authorize 那步拿到一个看不出根因的失败，所以在这里就报明确。
      throw const AuthHubException(
        error: AuthHubException.errBadResponse,
        message: '登录成功但未获得会话凭据',
      );
    }
    // 登录接口本身不返回身份细节，用 /api/me 复核一次：
    // 它同时验证了"刚存下的登录态服务端认不认账"，比直接信登录响应可靠。
    final who = await me();
    return who ??
        IdpIdentity(id: 0, username: username, nickname: '', email: '');
  }

  /// 当前登录态对应的身份；未登录返回 null。
  Future<IdpIdentity?> me() async {
    final session = await _store.read();
    if (session.isNullOrEmpty) return null;
    try {
      final resp = await _send('GET', AuthHubConfig.mePath, session: session);
      final body = _decode(resp);
      if ((body['code'] ?? 0) != 0) return null;
      final data = body['data'];
      // 未登录时后端返回 code=0 且 data=null —— 这是正常态，不是错误
      if (data is! Map<String, dynamic> || data.isEmpty) return null;
      return IdpIdentity.fromJson(data);
    } on AuthHubException {
      return null;
    }
  }

  /// 用当前登录态为某个依赖方换一个授权码。
  ///
  /// [client] / [redirectUri] / [scopes] 来自依赖方自己暴露的公开配置
  /// （业务后端是 `GET /user/oidc/config`），**不在本 App 里硬编码** ——
  /// 否则依赖方换 client_id 或回调地址时，要改的是 App 而不是它自己。
  ///
  /// [codeChallenge] 由调用方生成并保管 verifier：谁拿去换 token，谁就该持有
  /// verifier。这里是依赖方去换，所以 verifier 也归调用方（最终交给业务后端）。
  Future<IssuedCode> mintCodeForClient({
    required String client,
    required String redirectUri,
    required List<String> scopes,
    required String state,
    required String nonce,
    required String codeChallenge,
  }) async {
    final session = await _store.read();
    if (session.isNullOrEmpty) {
      throw const AuthHubException(
        error: 'unauthenticated',
        message: '还没有统一登录平台的登录态',
      );
    }

    // ① authorize —— 这一步必须不跟随重定向，否则 Location 里的
    //    /consent?<原始参数> 会被吞掉，后面无从提交决定。
    final authz = Uri.parse('$_issuer${AuthHubConfig.authPath}').replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': client,
        'redirect_uri': redirectUri,
        'scope': scopes.join(' '),
        'state': state,
        'nonce': nonce,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );
    final r1 = await _raw('GET', authz, session: session);
    if (!_isRedirect(r1.statusCode)) {
      if (_looksLikeLogin(r1)) {
        // 登录态失效（过期、或已在别处登出）。这是需要用户重新输口令的信号，
        // 不能和"网络抖动"混成一类去重试。
        throw const AuthHubException(
          error: 'session_expired',
          message: '统一登录平台的登录态已失效，请重新登录',
        );
      }
      throw AuthHubException(
        error: 'authorize_unexpected_status',
        message: '授权端点返回 HTTP ${r1.statusCode}，未跳转到确认页',
        statusCode: r1.statusCode,
      );
    }
    final consentQuery = _queryOf(r1.headers['location'] ?? '');

    // ② consent —— 参数原样回填。认证中心会重新校验 client 与 redirect_uri，
    //    所以这里照抄 authorize 的返回值而不是复用入参：
    //    万一后端做了规范化（比如补斜杠），复用入参会被判定不一致。
    final r2 = await _send('POST', AuthHubConfig.consentPath, session: session, jsonBody: {
      'client_id': consentQuery['client_id'] ?? client,
      'redirect_uri': consentQuery['redirect_uri'] ?? redirectUri,
      'scope': consentQuery['scope'] ?? scopes.join(' '),
      'state': consentQuery['state'] ?? state,
      'nonce': consentQuery['nonce'] ?? nonce,
      'code_challenge': consentQuery['code_challenge'] ?? codeChallenge,
      'code_challenge_method': consentQuery['code_challenge_method'] ?? 'S256',
      'decision': 'allow',
    });
    // /api/consent 返回**裸对象**（没有 code 字段），不能按信封解析
    final body = _decode(r2);
    if (r2.statusCode != 200) {
      throw AuthHubException(
        error: body['error'] as String? ?? 'consent_failed',
        message: body['error_description'] as String? ??
            body['message'] as String? ?? '授权确认失败（HTTP ${r2.statusCode}）',
        statusCode: r2.statusCode,
      );
    }

    // ③ 从 redirect_to 里取 code。**刻意不请求那个地址**：它是依赖方的回调页，
    //    本 App 去 GET 它只会拿到一个 HTML，而且 code 已经在 URL 里了。
    final redirectTo = body['redirect_to'] as String? ?? '';
    if (redirectTo.isEmpty) {
      throw const AuthHubException(
        error: AuthHubException.errNoCode,
        message: '授权确认未返回回调地址',
      );
    }
    final params = Uri.parse(redirectTo).queryParameters;
    if ((params['state'] ?? '') != state) {
      // 不匹配只有两种可能：回调被串了，或有人伪造一次授权完成。都必须中止。
      throw const AuthHubException(
        error: AuthHubException.errStateMismatch,
        message: '授权回调的 state 与发起时不一致，已中止',
      );
    }
    final code = params['code'] ?? '';
    if (code.isEmpty) {
      throw AuthHubException(
        error: params['error'] ?? AuthHubException.errNoCode,
        message: '回调未携带 code',
      );
    }
    return IssuedCode(code: code, state: params['state'] ?? state);
  }

  /// 退出登录：清本地登录态。
  ///
  /// 刻意**不**调认证中心的 RP-Initiated Logout —— 那个端点会销毁全局会话并
  /// 连带吊销该用户全部 refresh_token，等于把浏览器里其它已登录的业务系统
  /// 一起踢下线。"从这个 App 登出"和"从统一登录平台登出"是两件事。
  Future<void> signOut() => _store.clear();

  // ── 传输 ──────────────────────────────────────────────────────────────

  Future<http.Response> _send(String method, String path,
      {Map<String, dynamic>? jsonBody, String? session}) {
    return _raw(method, Uri.parse('$_issuer$path'),
        jsonBody: jsonBody, session: session);
  }

  Future<http.Response> _raw(String method, Uri url,
      {Map<String, dynamic>? jsonBody, String? session}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (jsonBody != null) headers['Content-Type'] = 'application/json';
    final cookie = session ?? await _store.read();
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = '${AuthHubConfig.sessionCookieName}=$cookie';
    }

    final req = http.Request(method, url)..headers.addAll(headers);
    if (jsonBody != null) req.body = jsonEncode(jsonBody);

    final streamed =
        await _client.send(req).timeout(AuthHubConfig.httpTimeout);
    return http.Response.fromStream(streamed);
  }

  /// 从响应里摘出登录态 Cookie 并持久化。
  void _absorbSession(http.Response resp) {
    final raw = resp.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    for (final line in raw.split('\n')) {
      final pair = line.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      if (pair.substring(0, eq).trim() != AuthHubConfig.sessionCookieName) {
        continue;
      }
      final value = pair.substring(eq + 1).trim();
      if (value.isEmpty) {
        _store.clear();
      } else {
        _store.save(value);
      }
      return;
    }
  }

  Map<String, dynamic> _decode(http.Response resp) {
    try {
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      if (d is Map<String, dynamic>) return d;
      throw const FormatException('not an object');
    } catch (_) {
      throw AuthHubException(
        error: AuthHubException.errBadResponse,
        message: '认证中心响应不是 JSON（HTTP ${resp.statusCode}）',
        statusCode: resp.statusCode,
      );
    }
  }

  static bool _isRedirect(int status) =>
      status == 301 || status == 302 || status == 303 || status == 307 || status == 308;

  static bool _looksLikeLogin(http.Response resp) {
    final loc = resp.headers['location'] ?? '';
    return loc.contains('/login');
  }

  static Map<String, String> _queryOf(String url) {
    final i = url.indexOf('?');
    if (i < 0) return const {};
    return Uri.splitQueryString(url.substring(i + 1));
  }

  void close() => _client.close();
}

extension on String? {
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}

/// 只做一件事：把请求发出去，**不跟重定向**，把 3xx 原样交回。
///
/// `http.Client` 默认自己跟 302，那样 authorize 拿回来的是最终页面的 200，
/// Location 里的授权参数被整个吞掉。而 `followRedirects` 挂在
/// **HttpClientRequest** 上、package:http 不暴露那个对象，
/// 所以只能自己实现 send()。
class _NoRedirectClient extends http.BaseClient {
  final HttpClient _inner = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = await _inner.openUrl(request.method, request.url);
    req.followRedirects = false;
    request.headers.forEach((k, v) => req.headers.set(k, v));
    if (request is http.Request && request.body.isNotEmpty) {
      req.write(request.body);
    }
    final resp = await req.close();
    return http.StreamedResponse(
      resp,
      resp.statusCode,
      // chunked 响应时 dart:io 给的是 -1，而 http.BaseResponse 拒绝负数；
      // 长度未知就该传 null。
      contentLength: resp.contentLength >= 0 ? resp.contentLength : null,
      request: request,
      headers: _flattenHeaders(resp),
      reasonPhrase: resp.reasonPhrase,
      isRedirect: resp.isRedirect,
    );
  }

  /// 多条 set-cookie 必须用换行拼接，与 [_absorbSession] 的按行拆分配对。
  /// 拼成 "; " 或只取第一条，会漏掉登录态那条，症状是"登录成功但未获得会话凭据"。
  static Map<String, String> _flattenHeaders(HttpClientResponse resp) {
    final out = <String, String>{};
    resp.headers.forEach((name, values) {
      out[name] = name == 'set-cookie' ? values.join('\n') : values.join(', ');
    });
    return out;
  }

  @override
  void close() => _inner.close(force: true);
}
