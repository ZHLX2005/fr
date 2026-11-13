import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/api/mnws/mnws.dart';
import 'package:xiaodouzi_fr/api/mnws/nxnx/nxnx_models.dart';
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

      final cat = await endpoint.catalog();

      expect(requested, ['GET /api/catalog']);
      expect(gate, 'device-token');
      expect(auth, isNull, reason: 'Authorization 整个留给被代理的 nx 服务');
      expect(cat.apps, hasLength(1));
      expect(cat.apps.first.app, 'nx-kv');
      expect(cat.apps.first.title, 'KV 清单中枢');
      expect(cat.apps.first.port, 7877);
    });

    test('catalog 按 PC 分组：每台电脑一组，组里是它的应用', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'ok': true,
              'count': 3,
              'pcCount': 2,
              'apps': [
                {
                  'app': 'nx-kv',
                  'title': 'KV 清单中枢',
                  'port': 7877,
                  'bridgeId': 'pc-a',
                  'pcName': '办公室台式机',
                  'pcNameMissing': true,
                },
                {
                  'app': 'nx-kv',
                  'title': 'KV 清单中枢',
                  'port': 7877,
                  'bridgeId': 'pc-b',
                  'pcName': '家里笔记本',
                },
                {
                  'app': 'other-api',
                  'title': '另一个服务',
                  'port': 9999,
                  'bridgeId': 'pc-b',
                  'pcName': '家里笔记本',
                },
              ],
              'pcs': [
                {
                  'bridgeId': 'pc-a',
                  'name': '办公室台式机',
                  'userId': '5',
                  'connectedAt': '2026-11-13T00:00:00.000Z',
                  'apps': [
                    {
                      'app': 'nx-kv',
                      'title': 'KV 清单中枢',
                      'port': 7877,
                      'base': 'http://127.0.0.1:7877',
                      'bridgeId': 'pc-a',
                      'active': false,
                    },
                  ],
                },
                {
                  'bridgeId': 'pc-b',
                  'name': '家里笔记本',
                  'userId': '5',
                  'connectedAt': '2026-11-13T00:00:01.000Z',
                  'apps': [
                    {
                      'app': 'nx-kv',
                      'title': 'KV 清单中枢',
                      'port': 7877,
                      'base': 'http://127.0.0.1:7877',
                      'bridgeId': 'pc-b',
                      'active': true,
                    },
                    {
                      'app': 'other-api',
                      'title': '另一个服务',
                      'port': 9999,
                      'base': 'http://127.0.0.1:9999',
                      'bridgeId': 'pc-b',
                      'active': true,
                    },
                  ],
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ));

      final endpoint = MnWsEndpoint(
        client: client,
        baseUrl: 'http://mws.test',
        grantReader: () async => _grant('device-token'),
      );

      final cat = await endpoint.catalog();

      expect(cat.pcs, hasLength(2));
      expect(cat.pcs.map((g) => g.name), ['办公室台式机', '家里笔记本']);

      // 组里是这台电脑自己的应用
      expect(cat.pcs.first.apps.map((a) => a.app), ['nx-kv']);
      expect(cat.pcs.last.apps.map((a) => a.app), ['nx-kv', 'other-api']);

      // 撞名的那个：路由归后来者，另一台要标出来
      expect(cat.pcs.first.apps.first.active, isFalse);
      expect(cat.pcs.last.apps.first.active, isTrue);

      // 扁平列表里也带得上电脑名
      expect(cat.apps, hasLength(3));
      expect(cat.apps.where((a) => a.pcNameMissing), hasLength(1));
      expect(cat.count, 3);
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

    test('request 带 X-Mn-Ws-Pc 头时打指定的那台 PC', () async {
      String? pcHeader;
      String? appHeader;

      final client = MockClient((req) async {
        pcHeader = req.headers['X-Mn-Ws-Pc'];
        appHeader = req.headers['X-Mn-Ws-App'];
        return http.Response('{"ok":true}', 200);
      });

      final endpoint = MnWsEndpoint(
        client: client,
        baseUrl: 'http://mws.test',
        grantReader: () async => _grant('device-token'),
      );

      await endpoint.request(
        method: 'GET',
        path: '/api/templates',
        app: 'nx-nx',
        pc: 'pc-a',
      );

      // 两台 PC 都跑 nx-nx 时，必须说清打的是哪一台
      expect(appHeader, 'nx-nx');
      expect(pcHeader, 'pc-a');
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

    test('nx-nx 模板：连同选项一起解析', () {
      final list = NxNxTemplate.fromJson({
        'id': 't1',
        'name': '单仓模板',
        'description': 'GoFrame 单仓',
        'nextSteps': ['cd x'],
        'options': [
          {'name': 'name', 'type': 'string', 'label': '项目名', 'required': true},
          {'name': 'lang', 'type': 'enum', 'label': '语言', 'required': false,
           'values': ['ts', 'go']},
        ],
      });
      expect(list.id, 't1');
      expect(list.name, '单仓模板');
      expect(list.nextSteps, ['cd x']);
      expect(list.options, hasLength(2));
      expect(list.options.first.required, isTrue);
      expect(list.options.first.label, '项目名');
      expect(list.options.last.values, ['ts', 'go']);
    });

    test('nx-nx bootstrap：应用信息 + 模板 + 不合法模板', () {
      final b = NxNxBootstrap.fromJson({
        'app': {'name': 'nx-nx', 'title': 'nx-nx', 'version': '0.8.6'},
        'storePath': 'C:/store.json',
        'templatesDir': 'D:/templates',
        'templates': [
          {'id': 't1', 'name': '单仓模板'},
        ],
        'templateErrors': [
          {'id': 'bad', 'message': '缺少 meta.json'},
        ],
      });
      expect(b.app.name, 'nx-nx');
      expect(b.app.version, '0.8.6');
      expect(b.templates, hasLength(1));
      // 不合法的模板也要说出来 —— 静默吞掉会让人以为「没有模板」
      expect(b.templateErrors, hasLength(1));
      expect(b.templateErrors.first.id, 'bad');
      expect(b.templateErrors.first.message, contains('meta.json'));
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
