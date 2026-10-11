import 'dart:convert';

import 'package:http/http.dart' as http;

import 'authhub_config.dart';
import 'authhub_exception.dart';
import 'authhub_models.dart';
import 'idp_session_store.dart';

/// 扫码登录端点（认证中心 `/api/qr/sessions*`）。
///
/// 本 App 的正常角色是**批准端**（手机）：preview / scan / confirm / refuse。
/// 另外四条 PC 侧端点（create / poll / claim / cancel）也一并实现，
/// 只服务于 Lab 里的"本机自测"：没有第二台设备时，用同一个客户端先建票、
/// 再扫自己建的码、最后领取，从而在一台机器上跑完整闭环。
///
/// ── 为什么自测要复用同一个 client ────────────────────────────────────────
///
/// 不是图省事。PC 侧的领取凭据是 `qr_ctx` **Cookie**，
/// 而"必须由创建票据的那台浏览器领取"正是扫码登录防转发的全部机制。
/// 复用同一个 `http.Client` 就等于复用同一个 Cookie 容器 —— 与真机上
/// "PC 浏览器建码、PC 浏览器领码"是同构的。
/// 若在这里为每次请求 new 一个 client，qr_ctx 会丢，claim 必然失败，
/// 而这个失败会被误读成"功能坏了"。
///
/// ── 鉴权口径 ──────────────────────────────────────────────────────────────
///
/// 手机侧四条要求已有身份，本模块走 `Authorization: Bearer <access_token>`
/// （认证中心的 resolveIdentity 同时认 Cookie 与 Bearer，App 用后者）。
/// 未登录时后端回 401 + `error=unauthenticated`，调用方据此去登录，
/// **不要**在这里自动跳登录页：把 401 静默重试成一次登录，
/// 会让"我到底登没登录"这件事在界面上失去确定性。
class AuthHubQrEndpoint {
  final http.Client _client;
  final String _issuer;

  /// 登录态来源。
  ///
  /// 手机侧四条端点**不接收凭据参数**，一律从这里自己取。这不是省事，是堵漏洞：
  /// 之前它们是 `String accessToken` 形参，改成用登录态之后，调用方继续传
  /// 业务 token 一样能通过类型检查（都是 String），要等到运行时 401 才发现。
  /// 把凭据从签名里拿掉，就没有"传错哪一种"这种事了 ——
  /// 本项目已经栽在"一枚 String 兼两个用途"上过不止一次。
  ///
  /// 认证中心的手机侧端点同时接受 Bearer access_token 与 idp_session Cookie，
  /// 本 App 用后者：批准扫码是几秒钟的一次性动作，不值得为它维持一个
  /// token 生命周期。
  final IdpSessionStore? sessionStore;

  /// 极简 Cookie 容器。
  ///
  /// `package:http` 的 `Client` **不自动处理 Cookie**，而 PC 侧的领取凭据
  /// `qr_ctx` 恰恰就是一个 Cookie —— 不自己存，create 拿到的 qr_ctx 会丢，
  /// 随后的 claim 必然失败，且失败信息（qr_not_ready）完全指不到"Cookie 没带上"。
  /// 为这一个键去引 `http_cookie_jar` 不值得，所以在这里手搓最小实现：
  /// 只存 name=value，只回给同源的 /api/qr/* 请求。
  final Map<String, String> _cookies = {};

  AuthHubQrEndpoint({http.Client? client, String? issuer, this.sessionStore})
      : _client = client ?? http.Client(),
        _issuer = (issuer ?? AuthHubConfig.issuer).replaceAll(RegExp(r'/+$'), '');

  // ── 手机侧（批准端）──────────────────────────────────────────────────────

  /// 取"要被登录的那台机器"的画像，供确认页展示。
  ///
  /// 注意路径是 `{ticket}/preview` 而**不是** `{ticket}`：后者是 PC 侧的轮询
  /// 端点，返回 `{status, expires_in}`，没有 `pc` 字段，而且对没有 qr_ctx 的
  /// 调用方一律回 `pending`。少写这一段不会报错、HTTP 200 一切正常，
  /// 只是画像全空 —— 于是确认页判定"无法核对"而禁掉确认按钮，
  /// 症状是"扫码登录完全不可用"，但没有任何一处报错指向真正的原因。
  Future<QrPreview> preview(String ticket) async {
    final data = await _call('GET', '${_path(ticket)}/preview',
        requireSession: true);
    return QrPreview.fromJson(data);
  }

  /// 上报"已扫码"，让 PC 端进入等待确认的中间态。
  ///
  /// 这一步不是装饰：没有它，用户在手机上慢慢读设备信息的那几秒里，
  /// PC 那边始终是一张静止的二维码，他会以为没扫上，于是重复扫码。
  Future<QrStatus> scan(String ticket) async {
    final data =
        await _call('POST', '${_path(ticket)}/scan', requireSession: true);
    return QrStatus.parse(data['status'] as String?);
  }

  /// 批准这次登录 —— 整个流程里唯一的授权动作。
  ///
  /// 无请求体：批准者是谁只认服务端从 access_token 解析出的身份。
  /// 一旦允许 body 里带"我替谁批准"，授权面就从"手机持有者"转移到了
  /// "任何会发请求的人"。
  Future<QrStatus> confirm(String ticket) async {
    final data = await _call('POST', '${_path(ticket)}/confirm',
        requireSession: true);
    return QrStatus.parse(data['status'] as String?);
  }

  /// 「不是我操作」：作废这张票据。
  Future<void> refuse(String ticket) =>
      _call('POST', '${_path(ticket)}/refuse', requireSession: true);

  // ── PC 侧（仅 Lab 自测使用）─────────────────────────────────────────────

  /// 建一张待扫码票据。响应里的 `Set-Cookie: qr_ctx` 由 [_client] 的
  /// Cookie 容器自动持有，后续 [claim] 必须用同一个实例才领得到。
  Future<QrSession> create() async {
    final data = await _call('POST', AuthHubConfig.qrBasePath);
    return QrSession.fromJson(data);
  }

  /// 轮询状态（只读、无副作用）。
  Future<QrStatus> poll(String ticket) async {
    final data = await _call('GET', _path(ticket));
    return QrStatus.parse(data['status'] as String?);
  }

  /// 领取登录态。**唯一**会下发 idp_session 的扫码端点。
  Future<Map<String, dynamic>> claim(String ticket) =>
      _call('POST', '${_path(ticket)}/claim');

  /// 作废自己建的票（换一张新码之前）。
  Future<void> cancel(String ticket) => _call('POST', '${_path(ticket)}/cancel');

  // ── 内部 ────────────────────────────────────────────────────────────────

  String _path(String ticket) =>
      '${AuthHubConfig.qrBasePath}/${Uri.encodeComponent(ticket)}';

  /// 发一次请求并按认证中心的 `{code,data,error,message}` 信封拆包。
  ///
  /// 4xx 必须先解析响应体再决定失败类型：认证中心的 401/409/410 带的是
  /// **业务失败信封**，`error` 字段是调用方分支的依据。若按 HTTP 状态先判失败，
  /// "服务端明确拒绝了这次批准"与"服务压根没应答"就会报成同一个错，
  /// 而这两种情况的正确处置完全相反（前者清 token 重新登录，后者原样重试）。
  /// [requireSession] 为真时，没有登录态就直接抛错，而不是发一个不带 Cookie 的请求。
  ///
  /// 之所以宁可抛错也不"照发让服务端去拒"：那会让一个明显的调用错误
  /// 变成一次网络往返加一个 401，报错信息（"需要先登录手机端账号"）
  /// 离真正的根因（调用方压根没传凭据）更远。
  Future<Map<String, dynamic>> _call(String method, String path,
      {bool requireSession = false}) async {
    final url = '$_issuer$path';
    final headers = <String, String>{'Accept': 'application/json'};
    final sess = await sessionStore?.read();
    if ((sess ?? '').isEmpty && requireSession) {
      throw const AuthHubException(
        error: 'unauthenticated',
        message: '调用统一登录平台的手机侧端点需要登录态，当前没有',
      );
    }
    if ((sess ?? '').isNotEmpty) {
      headers['Cookie'] = '${AuthHubConfig.sessionCookieName}=$sess';
    }
    // POST 一律带空对象：认证中心这些端点不读 body，但某些中间层会把
    // 完全没有 body 也没有 Content-Type 的 POST 判成畸形请求。
    if (method == 'POST') headers['Content-Type'] = 'application/json';
    if (_cookies.isNotEmpty) {
      headers['Cookie'] = _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }

    late final http.Response resp;
    try {
      final request = http.Request(method, Uri.parse(url))..headers.addAll(headers);
      if (method == 'POST') request.body = '{}';
      // send() 给的是 StreamedResponse，必须显式物化成 Response 才能读 body ——
      // 直接赋值编译期就报，但更阴的是若有人改成 `await for` 半读，
      // headers 已可读而 body 为空，错误会被判成"响应不是 JSON"。
      final streamed = await _client.send(request).timeout(AuthHubConfig.httpTimeout);
      resp = await http.Response.fromStream(streamed);
    } on http.ClientException catch (e) {
      throw AuthHubException(
        error: AuthHubException.errNetwork,
        message: '无法连接认证中心：${e.message}',
      );
    }

    _captureCookies(resp);
    Map<String, dynamic>? body;
    if (resp.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        body = null;
      }
    }

    if (resp.statusCode >= 400) {
      final error = body?['error'] as String? ?? 'http_${resp.statusCode}';
      throw AuthHubException(
        error: error,
        message: body?['message'] as String? ?? '认证中心返回 ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    }
    if (body == null) {
      throw AuthHubException(
        error: AuthHubException.errBadResponse,
        message: '响应不是 JSON（HTTP ${resp.statusCode}）',
        statusCode: resp.statusCode,
      );
    }
    if (body['code'] != null && body['code'] != 0) {
      throw AuthHubException(
        error: body['error'] as String? ?? 'unknown',
        message: body['message'] as String? ?? '请求失败',
        statusCode: resp.statusCode,
      );
    }
    final data = body['data'];
    return data is Map<String, dynamic> ? data : const {};
  }

  /// 从响应里摘出 Cookie 的 name=value。
  ///
  /// 只取值不实现属性语义（Path/HttpOnly/Expires 一概忽略）：
  /// 本客户端只跟 `$_issuer/api/qr/*` 这一族地址说话，作用域天然收敛，
  /// 而完整实现一个 Cookie Jar 会是几十行永远写对的边界情况（域后缀匹配、
  /// path 前缀匹配、Secure 与 http 的交互……）。
  /// 这里刻意选"够用且可读"，并在注释里把省掉的东西写明白，
  /// 免得将来有人以为它是个真 Jar 而在别的域名下复用它。
  void _captureCookies(http.Response resp) {
    final raw = resp.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    // package:http 会把多条 Set-Cookie 用换行拼在一个值里
    for (final line in raw.split('\n')) {
      final pair = line.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq).trim();
      final value = pair.substring(eq + 1).trim();
      if (value.isEmpty) {
        _cookies.remove(name); // 空值 = 服务端在清除
      } else {
        _cookies[name] = value;
      }
    }
  }

  /// 清空本地 Cookie 容器（自测结束后调用，避免下一次建码沿用上一次的 qr_ctx）。
  void clearCookies() => _cookies.clear();

  void close() => _client.close();
}
