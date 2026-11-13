import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/api/authhub/authhub_qr_endpoint.dart';
import 'package:xiaodouzi_fr/api/authhub/idp_session_store.dart';

/// 钉住 **Cookie 头里同时带着登录态与 qr_ctx**。
///
/// 背景：PC 侧 create() 会从响应里收下 `qr_ctx` Cookie（它是"必须由创建
/// 这张票据的那台浏览器领取"的凭据）。而手机侧四条端点靠 `idp_session`
/// 认身份。两枚 Cookie 服务端都要。
///
/// 之前的实现把 headers['Cookie'] **整体覆盖**成 _cookies 的内容，
/// 于是 create() 之后本地容器非空，此后每次调用的 Cookie 头里就只剩
/// qr_ctx、没有 idp_session —— 手机侧端点一律 401。
/// 线上日志里的现场正是：create → claim 409 → preview 401。
/// 有登录态的桩存储。
class _StubSessionStore extends IdpSessionStore {
  @override
  Future<String?> read() async => 'stub-idp-session';
}

void main() {
  test('本地 Cookie 容器非空时，登录态与 qr_ctx 必须同时出现在 Cookie 头里', () async {
    final seen = <String?>[];
    final client = MockClient((req) async {
      seen.add(req.headers['Cookie']);
      // create() 回一个 qr_ctx，模拟 PC 侧建票后本地容器非空
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {
            'ticket': 'qrt_abc123',
            'expires_in': 120,
            'qr_ctx': 'ctx-value',
          },
        }),
        201,
        headers: {
          'content-type': 'application/json',
          'set-cookie': 'qr_ctx=ctx-value; Path=/api/qr',
        },
      );
    });

    final api = AuthHubQrEndpoint(
      client: client,
      issuer: 'http://idp.test',
      sessionStore: _StubSessionStore(),
    );

    // ① 建票：响应带 qr_ctx，本地容器从此非空
    await api.create();
    expect(seen.last, contains('idp_session=stub-idp-session'),
        reason: '前置：建票请求应带着登录态');

    // ② 之后任一调用：Cookie 头里两枚 cookie 都要在
    await api.preview('qrt_abc123');

    final cookie = seen.last ?? '';
    expect(cookie, contains('idp_session=stub-idp-session'),
        reason: '本地 Cookie 容器非空时，不得把登录态从 Cookie 头里挤掉：'
            '服务端靠它认身份，挤掉就是一律 401');
    expect(cookie, contains('qr_ctx=ctx-value'),
        reason: 'qr_ctx 同样不能丢：它是"只有创建者能领"的凭据');
  });

  test('本地 Cookie 容器为空时，Cookie 头里仍只有登录态（不被 qr_ctx 污染）', () async {
    final seen = <String?>[];
    final client = MockClient((req) async {
      seen.add(req.headers['Cookie']);
      return http.Response(
        jsonEncode({
          'code': 0,
          'data': {'status': 'pending', 'expires_in': 118, 'pc': {}},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = AuthHubQrEndpoint(
      client: client,
      issuer: 'http://idp.test',
      sessionStore: _StubSessionStore(),
    );

    await api.preview('qrt_abc123');
    expect(seen.last, 'idp_session=stub-idp-session');
  });
}
