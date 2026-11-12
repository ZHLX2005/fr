import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/mnws/mnws.dart';

/// 钉住 mn-ws 端点的**请求路径、凭据来源与错误分类**。
///
/// ── 为什么每条都断言"请求头" ──────────────────────────────────────────────
/// mn-ws 有两层凭据，混淆的后果都是"看起来能连、实际上 401"：
///   · L1 通道层：X-Mn-Ws-Token（mn-ws 自己的领域令牌）
///   · L3 应用层：Authorization（被代理的服务自己的会话）
/// 所以「哪个头带在哪、什么时候带」必须逐条钉住。
///
/// ── 另一条钉死的线：认证中心的凭据不流经手机 ────────────────────────────
/// 换码在 mn-ws 服务端做（服务端拿 client 半的身份去认证中心换），
/// 手机只把**授权码**交过去。所以请求里不该出现 Bearer，
/// 更不该出现 access_token / refresh_token —— 那两张票指向整个平台的身份。
void main() {
  group('mn-ws 端点', () {
    test('catalog 用 X-Mn-Ws-Token 头带凭据（不用 Authorization）', () async {
      final requested = <String>[];
      String? gate;
      String? auth;

      final client = MockClient((req) async {
        requested.add('${req.method} ${req.url.path}');
        gate = req.headers['X-Mn-Ws-Token'];
        auth = req.headers['Authorization'];
        return http.Response(
          jsonEncode({
            'ok': true,
            'count': 1,
            'apps': [
              {'app': 'nx-kv', 'title': 'KV 清单中枢', 'port': 7877},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final endpoint = MnWsEndpoint(
        client: client,
        baseUrl: 'http://mws.test',
        grantReader: () async => _grant('device-token'),
      );

      final apps = await endpoint.catalog();

      expect(requested, ['GET /api/catalog']);
      expect(gate, 'device-token');
      expect(auth, isNull, reason: 'Authorization 整个留给被代理的 nx 服务');
      expect(apps, hasLength(1));
      expect(apps.first.app, 'nx-kv');
      expect(apps.first.title, 'KV 清单中枢');
      expect(apps.first.port, 7877);
    });

    test('request 带 X-Mn-Ws-App 头（应用标识）', () async {
      String? appHeader;
      String? gate;
      String? method;
      String? path;

      final client = MockClient((req) async {
        method = req.method;
        path = req.url.path;
        appHeader = req.headers['X-Mn-Ws-App'];
        gate = req.headers['X-Mn-Ws-Token'];
        return http.Response('{"ok":true,"data":[]}', 200);
      });

      final endpoint = MnWsEndpoint(
        client: client,
        baseUrl: 'http://mws.test',
        grantReader: () async => _grant('device-token'),
      );

      final res = await endpoint.request(
        method: 'post',
        path: '/api/repos',
        app: 'nx-kv',
        headers: const {'Content-Type': 'application/json'},
        body: '{"path":"/tmp/x"}',
      );

      expect(method, 'POST');
      expect(path, '/api/repos');
      expect(appHeader, 'nx-kv');
      expect(gate, 'device-token');
      expect(res.status, 200);
      expect(res.json, isA<Map<String, dynamic>>());
    });

    test('exchangeCode 把授权码交给 mn-ws 自己的端点换业务令牌', () async {
      String? auth;
      String? contentType;
      String? path;
      String? body;

      final client = MockClient((req) async {
        auth = req.headers['Authorization'];
        contentType = req.headers['Content-Type'];
        path = req.url.path;
        body = req.body;
        return http.Response(
          jsonEncode({
            'ok': true,
            'userId': '5',
            'nickname': '管理员',
            'token': 'mn-ws-business-token',
            'tokenExpiresAt': 99999999999999,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final endpoint = MnWsEndpoint(
        client: client,
        baseUrl: 'http://mws.test',
        grantReader: () async => null,
      );

      final grant = await endpoint.exchangeCode(
        code: 'the-code',
        codeVerifier: 'the-verifier',
        redirectUri: 'http://127.0.0.1:39471/callback',
      );

      expect(path, '/auth/oidc/callback');
      expect(contentType, contains('application/json'));
      final sent = jsonDecode(body!) as Map<String, dynamic>;
      expect(sent['code'], 'the-code');
      expect(sent['codeVerifier'], 'the-verifier');
      expect(sent['redirectUri'], 'http://127.0.0.1:39471/callback');

      // 关键隐私断言：认证中心的令牌**不流经手机**。
      // 换码在 mn-ws 服务端做，所以这里既没有 Bearer，也不该有 access_token。
      expect(auth, isNull, reason: '认证中心的凭据不该出现在手机的请求里');
      expect(body, isNot(contains('access_token')));
      expect(body, isNot(contains('refresh_token')));

      expect(grant.token, 'mn-ws-business-token');
      expect(grant.userId, '5');
      expect(grant.isExpired, isFalse);
    });

    test('exchangeCode 不带 clientId —— 手机端不登记成一台桥', () async {
      String? body;
      final client = MockClient((req) async {
        body = req.body;
        return http.Response(
          jsonEncode({'ok': true, 'userId': '5', 'token': 't'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final endpoint = MnWsEndpoint(
        client: client,
        baseUrl: 'http://mws.test',
        grantReader: () async => null,
      );

      await endpoint.exchangeCode(
        code: 'c',
        codeVerifier: 'v',
        redirectUri: 'http://127.0.0.1:39471/callback',
      );

      final sent = jsonDecode(body!) as Map<String, dynamic>;
      expect(sent.containsKey('clientId'), isFalse);
    });

    test('服务端拒了 → 归类成 rejected 而不是 unreachable', () async {
      final client = MockClient((req) async =>
          http.Response(jsonEncode({'error': 'invalid_token'}), 401));

      final endpoint = MnWsEndpoint(
        client: client,
        baseUrl: 'http://mws.test',
        grantReader: () async => _grant('device-token'),
      );

      await expectLater(
        endpoint.catalog(),
        throwsA(isA<MnWsException>()
            .having((e) => e.kind, 'kind', MnWsErrorKind.rejected)),
      );
    });

    test('没有凭据就不发请求（直接说没登录）', () async {
      var called = false;
      final client = MockClient((req) async {
        called = true;
        return http.Response('{}', 200);
      });

      final endpoint = MnWsEndpoint(
        client: client,
        baseUrl: 'http://mws.test',
        grantReader: () async => null,
      );

      await expectLater(
        endpoint.catalog(),
        throwsA(isA<MnWsException>()
            .having((e) => e.kind, 'kind', MnWsErrorKind.unauthorized)),
      );
      expect(called, isFalse);
    });
  });

  group('模型解析', () {
    test('authConfig：loginClientId 优先，回落 clientId', () {
      final cfg = MnWsAuthConfig.fromJson({
        'enabled': true,
        'issuer': 'http://idp.test',
        'clientId': 'mn-ws-server',
        'loginClientId': 'mn-ws-client',
        'scopes': ['openid', 'profile'],
        'idpAvailable': true,
      });
      expect(cfg.clientId, 'mn-ws-server');
      expect(cfg.loginClientId, 'mn-ws-client');
      expect(cfg.scopes, ['openid', 'profile']);
      expect(cfg.idpAvailable, isTrue);

      // 老服务端只有 clientId → 两端同一个身份
      final old = MnWsAuthConfig.fromJson({
        'enabled': true,
        'clientId': 'mn-ws',
      });
      expect(old.loginClientId, 'mn-ws');
    });

    test('MnWsApp：标题缺失时回落应用名', () {
      final app = MnWsApp.fromJson({'app': 'my-api', 'port': 9999});
      expect(app.title, 'my-api');
      expect(app.port, 9999);
      expect(app.base, isNull);
    });

    test('MnWsGrant：过期的令牌认得出来', () {
      final expired = MnWsGrant.fromJson({
        'token': 't',
        'tokenExpiresAt': 1000,
      });
      expect(expired.isExpired, isTrue);

      final alive = MnWsGrant.fromJson({
        'token': 't',
        'tokenExpiresAt': 99999999999999,
      });
      expect(alive.isExpired, isFalse);
    });

    test('nx-kv 仓库：连同所属看板一起解析', () {
      final repo = NxKvRepo.fromJson({
        'id': 'r_1',
        'name': 'demo',
        'path': '/tmp/demo',
        'desc': '描述',
        'boards': [
          {'id': 'b1', 'name': '求职', 'desc': '', 'note': ''},
        ],
      });
      expect(repo.id, 'r_1');
      expect(repo.name, 'demo');
      expect(repo.path, '/tmp/demo');
      expect(repo.boards, hasLength(1));
      expect(repo.boards.first.name, '求职');
    });
  });
}

MnWsGrant _grant(String token) => MnWsGrant(
      token: token,
      userId: '5',
      email: '',
      nickname: '管理员',
      clientId: 'fr-mn-ws',
      deviceName: 'FR',
      tokenExpiresAt: 99999999999999,
    );
