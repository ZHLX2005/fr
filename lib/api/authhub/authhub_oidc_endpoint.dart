import 'dart:convert';

import 'package:http/http.dart' as http;

import 'authhub_config.dart';
import 'authhub_exception.dart';
import 'authhub_models.dart';

/// 认证中心的 OIDC 协议端点：发现文档、换 token、刷新、吊销、userinfo。
///
/// 自持 `http.Client`（规范 Rule 3）：认证中心的 baseUrl、错误语义、
/// 表单编码方式都与 goframe 业务后端不同，不套同一条拦截器链。
/// 尤其不能让 AuthInterceptor 往这里注业务后端的 token ——
/// 那会把业务凭据发给认证中心，是实打实的凭据错投。
class AuthHubOidcEndpoint {
  final http.Client _client;
  final String _issuer;

  /// 发现文档缓存。端点地址在进程内不会变，没必要每次授权都拉一遍。
  OidcEndpoints? _cached;

  AuthHubOidcEndpoint({http.Client? client, String? issuer})
      : _client = client ?? http.Client(),
        _issuer = (issuer ?? AuthHubConfig.issuer).replaceAll(RegExp(r'/+$'), '');

  /// 当前 issuer（供上层拼授权页地址、展示"连的是哪儿"）。
  String get issuer => _issuer;

  // ── 发现文档 ────────────────────────────────────────────────────────────

  Future<OidcEndpoints> discover({bool force = false}) async {
    final cached = _cached;
    if (cached != null && !force) return cached;

    final json = await _getJson('$_issuer${AuthHubConfig.discoveryPath}');
    final endpoints = OidcEndpoints.fromJson(json, _issuer);
    _cached = endpoints;
    return endpoints;
  }

  // ── 令牌端点 ────────────────────────────────────────────────────────────

  /// 用授权码 + code_verifier 换令牌集。
  ///
  /// `redirect_uri` 必须与授权请求里那一条**逐字一致**（含端口），
  /// 两边不一致认证中心直接拒绝 —— 所以它由调用方从发起授权的那份状态里传进来，
  /// 不能在这里重新生成一个端口。
  Future<AuthTokenSet> exchangeCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final e = await discover();
    return _postForm(e.tokenEndpoint, {
      'grant_type': 'authorization_code',
      'code': code,
      'client_id': AuthHubConfig.clientId,
      'redirect_uri': redirectUri,
      'code_verifier': codeVerifier,
    });
  }

  /// 用 refresh_token 续期。
  Future<AuthTokenSet> refresh(String refreshToken) async {
    final e = await discover();
    return _postForm(e.tokenEndpoint, {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': AuthHubConfig.clientId,
    });
  }

  /// 吊销 refresh_token（RFC 7009）。登出时调用。
  ///
  /// 认证中心对未知 token 也返回 200（否则这里就成了令牌有效性探测口），
  /// 所以**不能**用返回值判断"是否真的吊销成功"。
  Future<void> revoke(String token) async {
    // 直接按 issuer 拼，不从 tokenEndpoint 反推：
    // "把结尾的 /token 削掉再加 /revoke" 这种字符串戏法，
    // 端点命名一变就静默拼出一个 404，而 404 在这里被下面吞掉，没人知道。
    final url = '$_issuer${AuthHubConfig.revokePath}';
    try {
      await _client
          .post(Uri.parse(url), body: {
            'token': token,
            'client_id': AuthHubConfig.clientId,
          })
          .timeout(AuthHubConfig.httpTimeout);
    } on http.ClientException {
      // 吊销失败不阻断登出：本地已经清掉了凭据，远端多留一会儿可接受。
      // 反过来（因为吊销失败就不让用户登出）会把一次网络抖动变成界面卡死。
    }
  }

  // ── userinfo ────────────────────────────────────────────────────────────

  /// 用 access_token 取身份。
  ///
  /// 这是本 App 唯一的"我现在是谁"依据 —— 认证中心的 access_token 是不透明串，
  /// 本地解析不出任何东西，只能问。
  Future<IdpUser> userinfo(String accessToken) async {
    final e = await discover();
    final resp = await _client.get(
      Uri.parse(e.userinfoEndpoint),
      headers: {'Authorization': 'Bearer $accessToken'},
    ).timeout(AuthHubConfig.httpTimeout);

    if (resp.statusCode == 401) {
      throw const AuthHubException(
        error: 'invalid_token',
        message: 'access_token 已失效',
        statusCode: 401,
      );
    }
    return IdpUser.fromJson(_decodeJson(resp));
  }

  // ── 内部 ────────────────────────────────────────────────────────────────

  Future<AuthTokenSet> _postForm(String url, Map<String, String> fields) async {
    late final http.Response resp;
    try {
      resp = await _client
          .post(Uri.parse(url),
              headers: {'Content-Type': 'application/x-www-form-urlencoded'},
              body: fields)
          .timeout(AuthHubConfig.httpTimeout);
    } on http.ClientException catch (e) {
      throw AuthHubException(
        error: AuthHubException.errNetwork,
        message: '无法连接认证中心：${e.message}',
      );
    }

    final json = _decodeJson(resp);
    if (resp.statusCode >= 400 || json.containsKey('error')) {
      throw AuthHubException(
        error: json['error'] as String? ?? 'http_${resp.statusCode}',
        message: json['error_description'] as String? ?? '认证中心返回 ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    final set = AuthTokenSet.fromJson(json);
    if (set.isEmpty) {
      throw const AuthHubException(
        error: AuthHubException.errBadResponse,
        message: '令牌响应里没有 access_token',
      );
    }
    return set;
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    late final http.Response resp;
    try {
      resp = await _client.get(Uri.parse(url)).timeout(AuthHubConfig.httpTimeout);
    } on http.ClientException catch (e) {
      throw AuthHubException(
        error: AuthHubException.errDiscovery,
        message: '拉取发现文档失败：${e.message}',
      );
    }
    final json = _decodeJson(resp);
    if (resp.statusCode >= 400) {
      throw AuthHubException(
        error: AuthHubException.errDiscovery,
        message: '发现文档返回 ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    return json;
  }

  Map<String, dynamic> _decodeJson(http.Response resp) {
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      throw const FormatException('not a JSON object');
    } catch (_) {
      // 单独判一类：网关/代理返回 HTML 错误页时，如果按空 JSON 继续跑，
      // 症状是"缺少 access_token"这种离根因很远的报错。
      throw AuthHubException(
        error: AuthHubException.errBadResponse,
        message: '认证中心响应不是 JSON（HTTP ${resp.statusCode}）：'
            '${resp.body.length > 160 ? '${resp.body.substring(0, 160)}…' : resp.body}',
        statusCode: resp.statusCode,
      );
    }
  }

  void close() => _client.close();
}
