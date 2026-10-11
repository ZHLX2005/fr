import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'remotetype_config.dart';
import 'remotetype_exception.dart';
import 'remotetype_models.dart';

/// 远程输入桥（mn-rt）端点。
///
/// ── 为什么自持 http.Client ────────────────────────────────────────────────
/// 它是独立后端：裸 JSON 响应（没有 goframe 那层 `code/data` 信封）、
/// 独立凭据（本服务自签的设备令牌）。套进统一拦截器链会让 AuthInterceptor
/// 把业务后端的 JWT 注进它的请求里（或反过来），那类 bug 表现为"莫名其妙 401"。
///
/// ── 为什么受保护的调用不接收 token 形参 ────────────────────────────────────
/// 同 authhub 那侧的教训：凭据一旦出现在方法签名里，调用方传错哪一种字符串
/// 都能通过类型检查，要等到运行时才炸。所以凭据从注入的读取器里取，
/// [myComputers] 签名里没有 token 这个参数 —— 也就没有"传错 token"这种事。
class RemoteTypeEndpoint {
  final http.Client _client;
  final String _base;

  /// 当前有效凭据的来源。返回 null = 还没登录，需要授权的调用会直接报错。
  final Future<RtGrant?> Function() grantReader;

  RemoteTypeEndpoint({
    http.Client? client,
    String? baseUrl,
    required this.grantReader,
  })  : _client = client ?? http.Client(),
        _base = (baseUrl ?? RemoteTypeConfig.serverBaseUrl)
            .replaceAll(RegExp(r'/+$'), '');

  Uri get _authConfigUri => Uri.parse('$_base${RemoteTypeConfig.authConfigPath}');

  /// 服务端支持统一登录吗？连的到底是哪个认证中心？
  ///
  /// 这一步失败要能区分"服务器压根不可达"和"可达但没开统一登录"，
  /// 因为对应的动作完全不同：前者是重试/换地址，后者是退回手工配对 key。
  Future<RtAuthConfig> authConfig() async {
    final res = await _send(() => _client.get(
          _authConfigUri,
          headers: const {'Accept': 'application/json'},
        ).timeout(RemoteTypeConfig.httpTimeout));
    final json = _asJson(res);
    final cfg = RtAuthConfig.fromJson(json);
    if (cfg.enabled && !cfg.idpAvailable) {
      throw RemoteTypeException(
        RemoteTypeErrorKind.idpUnavailable,
        '远程输入服务连不上统一认证中心，暂时无法用统一登录',
        detail: cfg.issuer,
      );
    }
    return cfg;
  }

  /// 用授权码 + PKCE verifier 换本服务的凭据。
  ///
  /// 授权码由调用方从认证中心拿到（见 RemoteTypeService）：谁持有 verifier，
  /// 谁就该是拿去换 token 的那个人，这是 PKCE 唯一有意义的位置。
  Future<RtGrant> exchangeCode({
    required String code,
    required String codeVerifier,
    required String redirectUri,
    String deviceName = '',
  }) async {
    final res = await _send(() => _client
        .post(
          Uri.parse('$_base${RemoteTypeConfig.callbackPath}'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'code': code,
            'codeVerifier': codeVerifier,
            'redirectUri': redirectUri,
            // 手机端不登记成"一台可被连接的电脑"：不带 clientId，
            // 服务端因此签一枚不绑定设备的用户令牌。
            if (deviceName.isNotEmpty) 'deviceName': deviceName,
          }),
        )
        .timeout(RemoteTypeConfig.httpTimeout));
    final json = _asJson(res);
    if (res.statusCode >= 400 || (json['ok'] != true) || json['token'] == null) {
      throw _classify(res.statusCode, json, _bodyText(res));
    }
    final grant = RtGrant.fromJson(json);
    if (grant.token.isEmpty) {
      throw const RemoteTypeException(
        RemoteTypeErrorKind.unauthorized,
        '服务端未返回可用凭据',
      );
    }
    return grant;
  }

  /// 我名下的电脑（含每台的会话密钥）。
  ///
  /// 服务端按令牌里的 sub 过滤，所以这个列表**天然不含别人的设备**；
  /// 跨用户可见性由服务端保证，客户端不做二次过滤——那样只会掩盖服务端的 bug。
  Future<List<RtComputer>> myComputers() async {
    final grant = await grantReader();
    if (grant == null || grant.token.isEmpty) {
      throw const RemoteTypeException(
        RemoteTypeErrorKind.unauthorized,
        '还没有远程输入服务的凭据，请先用统一登录',
      );
    }
    final res = await _send(() => _client.get(
          Uri.parse('$_base${RemoteTypeConfig.myDevicesPath}'),
          headers: {'Authorization': 'Bearer ${grant.token}'},
        ).timeout(RemoteTypeConfig.httpTimeout));
    final json = _asJson(res);
    if (res.statusCode == 401) {
      throw const RemoteTypeException(
        RemoteTypeErrorKind.unauthorized,
        '远程输入服务的凭据已失效，请重新用统一登录',
      );
    }
    if (res.statusCode >= 400 || json['ok'] != true) {
      throw _classify(res.statusCode, json, _bodyText(res));
    }
    final list = (json['devices'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => RtComputer.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  // ── 内部 ────────────────────────────────────────────────────────────────

  RemoteTypeException _classify(
      int status, Map<String, dynamic> json, String raw) {
    final err = (json['error'] ?? '') as String;
    if (err == 'device_owned_by_other') {
      // 服务端明确拒绝改绑：这台电脑登记在别人名下。绝不静默当成"我的"。
      return RemoteTypeException(
        RemoteTypeErrorKind.ownedByOther,
        '这台电脑已绑定到其他账号，服务端拒绝了改绑',
        detail: (json['clientId'] ?? '') as String,
      );
    }
    if (err == 'auth_required' || status == 401 || status == 403) {
      return RemoteTypeException(
        RemoteTypeErrorKind.unauthorized,
        (json['message'] ?? '需要统一登录') as String,
        detail: err,
      );
    }
    return RemoteTypeException(
      RemoteTypeErrorKind.unreachable,
      '远程输入服务返回异常（HTTP $status）',
      detail: raw.isEmpty ? null : raw.substring(0, raw.length > 160 ? 160 : raw.length),
    );
  }

  Future<http.Response> _send(
      Future<http.Response> Function() action) async {
    try {
      return await action();
    } on TimeoutException {
      throw const RemoteTypeException(
        RemoteTypeErrorKind.unreachable,
        '远程输入服务响应超时',
      );
    } catch (e) {
      if (e is RemoteTypeException) rethrow;
      throw RemoteTypeException(
        RemoteTypeErrorKind.unreachable,
        '连不上远程输入服务',
        detail: e.toString(),
      );
    }
  }

  static String _bodyText(http.Response res) => utf8.decode(
        res.bodyBytes,
        allowMalformed: true,
      );

  /// 响应不是 JSON 时必须单独成类。
  ///
  /// 网关错误页、地址写错指到别的服务，返回的都是 HTML；
  /// 让它落到"认证失败"那一类，排查方向会整个错掉。
  static Map<String, dynamic> _asJson(http.Response res) {
    final text = _bodyText(res);
    if (text.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'ok': false, 'error': 'unexpected_shape', 'raw': text};
    } catch (_) {
      throw RemoteTypeException(
        RemoteTypeErrorKind.unreachable,
        '远程输入服务返回的不是 JSON（HTTP ${res.statusCode}）',
        detail: text.substring(0, text.length > 160 ? 160 : text.length),
      );
    }
  }

  void close() => _client.close();
}
