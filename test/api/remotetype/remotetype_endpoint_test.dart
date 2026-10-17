import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/api/remotetype/remotetype.dart';

/// 钉住远程输入桥端点的**请求路径、凭据来源与错误分类**。
///
/// 为什么照抄 qr_endpoint_path_test 的写法：那一版只测了响应解析，
/// 于是 preview() 少写一个后缀、打到另一个端点拿到"200 + 结构合法 + 没有 pc 字段"
/// 这件事整整两轮验证都没发现，症状却是"扫码登录不可用"。
/// 这里每一条都断言"到底请求了哪个 path、带了什么头、错成了哪一类"。
void main() {
  final requested = <String>[];
  final authHeaders = <String?>[];
  RtGrant? grant;

  /// 每个用例可以指定这一次返回什么
  http.Response Function(http.Request req) responder = (_) =>
      http.Response('{}', 200);

  final client = MockClient((req) async {
    requested.add('${req.method} ${req.url.path}');
    authHeaders.add(req.headers['Authorization']);
    return responder(req);
  });

  setUp(() {
    requested.clear();
    authHeaders.clear();
    grant = RtGrant(
      token: 'GRANT-TOKEN',
      userId: 'sub-1',
      expiresAtMs: DateTime.now().add(const Duration(days: 20)).millisecondsSinceEpoch,
    );
    responder = (_) => http.Response(jsonEncode({'ok': true}), 200,
        headers: {'content-type': 'application/json'});
  });

  RemoteTypeEndpoint api() => RemoteTypeEndpoint(
        client: client,
        baseUrl: 'http://rt.test',
        grantReader: () async => grant,
      );

  group('路径', () {
    test('四个端点各自请求正确的 path', () async {
      responder = (_) => http.Response(
          jsonEncode({
            'ok': true,
            'enabled': false,
            'idpAvailable': false,
            'clientId': 'mn-rt',
            'redirectUri': 'http://127.0.0.1:8790/callback',
          }),
          200,
          headers: {'content-type': 'application/json'});
      await api().authConfig();
      responder = (_) => http.Response(
          jsonEncode({'ok': true, 'token': 'T', 'userId': 's'}), 200,
          headers: {'content-type': 'application/json'});
      await api().exchangeCode(
          code: 'c', codeVerifier: 'v', redirectUri: 'http://127.0.0.1:8790/callback');
      responder = (_) => http.Response(
          jsonEncode({'ok': true, 'devices': []}), 200,
          headers: {'content-type': 'application/json'});
      await api().myComputers();

      expect(requested, [
        'GET /auth/oidc/config',
        'POST /auth/oidc/callback',
        'GET /my/devices',
      ]);
    });

    test('authConfig 不能打到 /auth/oidc/callback（少写后缀会打到别的端点上）', () async {
      responder = (_) => http.Response(
          jsonEncode({'ok': true, 'enabled': false}), 200,
          headers: {'content-type': 'application/json'});
      await api().authConfig();
      expect(requested.single, 'GET /auth/oidc/config');
    });
  });

  group('凭据来源', () {
    test('myComputers 带的是注入的凭据，且方法签名里根本没有 token 参数', () async {
      responder = (_) => http.Response(
          jsonEncode({'ok': true, 'devices': []}), 200,
          headers: {'content-type': 'application/json'});
      await api().myComputers();
      expect(authHeaders.single, 'Bearer GRANT-TOKEN');
    });

    test('没有凭据时当场拒绝，不发那个必然 401 的请求', () async {
      grant = null;
      await expectLater(
        api().myComputers(),
        throwsA(isA<RemoteTypeException>().having(
            (e) => e.kind, 'kind', RemoteTypeErrorKind.unauthorized)),
      );
      expect(requested, isEmpty, reason: '一次请求都不该发出去');
    });
  });

  group('错误分类：同一句"失败"要能指到不同动作', () {
    test('服务端 enabled=false 是正常态，不是错误', () async {
      responder = (_) => http.Response(
          jsonEncode({'ok': true, 'enabled': false, 'idpAvailable': false}), 200,
          headers: {'content-type': 'application/json'});
      final cfg = await api().authConfig();
      expect(cfg.enabled, isFalse);
      expect(cfg.idpAvailable, isFalse);
    });

    test('enabled=true 但 idpAvailable=false → 归到 idpUnavailable（是服务端的网络问题）', () async {
      responder = (_) => http.Response(
          jsonEncode({
            'ok': true,
            'enabled': true,
            'idpAvailable': false,
            'issuer': 'http://idp.wrong:9999'
          }),
          200,
          headers: {'content-type': 'application/json'});
      await expectLater(
        api().authConfig(),
        throwsA(isA<RemoteTypeException>()
            .having((e) => e.kind, 'kind', RemoteTypeErrorKind.idpUnavailable)
            .having((e) => e.detail, 'detail', 'http://idp.wrong:9999')),
      );
    });

    test('换绑被拒 → ownedByOther，不能混进"未授权"里被静默重试', () async {
      responder = (_) => http.Response(
          jsonEncode({
            'ok': false,
            'error': 'device_owned_by_other',
            'clientId': 'pc-victim'
          }),
          403,
          headers: {'content-type': 'application/json'});
      await expectLater(
        api().exchangeCode(
            code: 'c', codeVerifier: 'v', redirectUri: 'http://127.0.0.1:8790/callback'),
        throwsA(isA<RemoteTypeException>()
            .having((e) => e.kind, 'kind', RemoteTypeErrorKind.ownedByOther)),
      );
    });

    test('凭据失效 → unauthorized（调用方据此重铸一次）', () async {
      responder = (_) => http.Response(
          jsonEncode({'ok': false, 'error': 'unauthorized'}), 401,
          headers: {'content-type': 'application/json'});
      await expectLater(
        api().myComputers(),
        throwsA(isA<RemoteTypeException>()
            .having((e) => e.kind, 'kind', RemoteTypeErrorKind.unauthorized)),
      );
    });

    test('返回 HTML 时归为 unreachable，不能被当成"认证失败"', () async {
      // 网关错误页 / 地址写错指到别的服务，都是这种形态。
      // 判成 unauthorized 会让上层去"重新登录"，方向完全错。
      responder = (_) => http.Response('<html>502 Bad Gateway</html>', 502);
      await expectLater(
        api().authConfig(),
        throwsA(isA<RemoteTypeException>()
            .having((e) => e.kind, 'kind', RemoteTypeErrorKind.unreachable)),
      );
    });
  });

  group('凭据边界', () {
    test('exchangeCode 成功后不请求那个回调地址（code 已在响应里）', () async {
      responder = (_) => http.Response(
          jsonEncode({'ok': true, 'token': 'T', 'userId': 's'}), 200,
          headers: {'content-type': 'application/json'});
      await api().exchangeCode(
          code: 'c', codeVerifier: 'v', redirectUri: 'http://127.0.0.1:8790/callback');
      expect(requested, ['POST /auth/oidc/callback']);
    });

    test('请求体不带任何认证中心 token，也不带 client_secret', () async {
      String? body;
      responder = (req) {
        body = req.body;
        return http.Response(jsonEncode({'ok': true, 'token': 'T', 'userId': 's'}), 200,
            headers: {'content-type': 'application/json'});
      };
      await api().exchangeCode(
          code: 'c', codeVerifier: 'v', redirectUri: 'http://127.0.0.1:8790/callback');
      final map = jsonDecode(body!) as Map<String, dynamic>;
      expect(map['code'], 'c');
      expect(map['codeVerifier'], 'v');
      expect(map.containsKey('accessToken'), isFalse,
          reason: '手机端走 code 路径，不该顺手把认证中心 token 也交出去');
      expect(body, isNot(contains('client_secret')));
      // 手机端不登记成一台电脑：不带 clientId，服务端因此签不绑设备的用户令牌
      expect(map.containsKey('clientId'), isFalse);
    });

    test('RtGrant 里没有任何 refresh_token 的位置', () async {
      responder = (_) => http.Response(
          jsonEncode({
            'ok': true,
            'token': 'T',
            'userId': 's',
            'refresh_token': 'SHOULD-NOT-PERSIST',
            'accessToken': 'ALSO-NOT-PERSIST',
          }),
          200,
          headers: {'content-type': 'application/json'});
      final g = await api().exchangeCode(
          code: 'c', codeVerifier: 'v', redirectUri: 'http://127.0.0.1:8790/callback');
      expect(jsonEncode(g.toJson()), isNot(contains('SHOULD-NOT-PERSIST')));
      expect(jsonEncode(g.toJson()), isNot(contains('ALSO-NOT-PERSIST')));
      expect(g.token, 'T');
    });
  });

  test('设备列表按在线状态可判定（点了不在线的电脑要有解释，不是静默失败）', () async {
    responder = (_) => http.Response(
        jsonEncode({
          'ok': true,
          'userId': 'sub-1',
          'devices': [
            {
              'clientId': 'pc-on',
              'deviceName': '书房',
              'sessionKey': 'aa' * 32,
              'online': true
            },
            {
              'clientId': 'pc-off',
              'deviceName': '',
              'sessionKey': 'bb' * 32,
              'online': false
            },
          ]
        }),
        200,
        headers: {'content-type': 'application/json'});
    final list = await api().myComputers();
    expect(list.length, 2);
    expect(list.first.online, isTrue);
    expect(list.first.label, '书房');
    expect(list[1].label, 'pc-off', reason: '没名字时退回 clientId，列表里不能出现空行');
  });
}
