import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/api/mnws/mnws.dart';
import 'package:xiaodouzi_fr/api/mnws/nxnx/nxnx_api.dart';

/// nx-nx 接口客户端的**调用契约**。
///
/// 钉的是三件事：
///   1. 路径参数替换进路径、其余参数进 query 或 body（与 nx-nx 自己的
///      typed-client 一个语义）
///   2. `{ok, data}` 信封被剥掉
///   3. 出错时归类成 MnWsException（而不是把原始 body 糊到界面上）
void main() {
  /// 造一个记录请求的 MockClient。
  MockClient recorder(
    void Function(http.Request req) onRequest, {
    Object? body,
    int status = 200,
  }) {
    return MockClient((req) async {
      onRequest(req);
      return http.Response(
        body is String ? body : jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }

  MnWsEndpoint endpointWith(http.Client client) => MnWsEndpoint(
        client: client,
        baseUrl: 'http://mws.test',
        grantReader: () async => MnWsGrant(
          token: 'business-token',
          userId: '5',
          email: '',
          nickname: '',
          clientId: 'fr-mn-ws',
          deviceName: 'FR',
          tokenExpiresAt: 99999999999999,
        ),
      );

  group('nx-nx API 客户端', () {
    test('路径参数替换进路径，其余走 query', () async {
      String? path;
      String? query;
      final client = recorder((req) {
        path = req.url.path;
        query = req.url.query;
      }, body: {
        'ok': true,
        'data': {'status': 'ok', 'templates': []}
      });

      await NxNxApi(pc: 'pc-a').templates(endpointWith(client));
      expect(path, '/api/templates');
      expect(query, isEmpty);

      await NxNxApi(pc: 'pc-a').describe(endpointWith(client), 'mono gf');
      expect(path, '/api/templates/mono%20gf');
    });

    test('POST 的参数走 body，且是扁平的（模板选项不嵌套）', () async {
      String? body;
      final client = recorder((req) {
        body = req.body;
      }, body: {
        'ok': true,
        'data': {'count': 2, 'files': ['a', 'b']}
      });

      final r = await NxNxApi(pc: 'pc-a').preview(
        endpointWith(client),
        'mono-gf',
        values: {'name': 'demo'},
        dir: 'out',
      );
      expect(r.count, 2);
      final sent = jsonDecode(body!) as Map<String, dynamic>;
      // 扁平：name 与 dir 平级，不塞进 vars
      expect(sent['name'], 'demo');
      expect(sent['dir'], 'out');
      expect(sent.containsKey('vars'), isFalse);
    });

    test('信封被剥掉：拿到的就是 data 那一层', () async {
      final client = recorder((_) {}, body: {
        'ok': true,
        'data': {
          'app': {'name': 'nx-nx', 'version': '0.8.6'},
          'templates': [
            {'id': 't1', 'name': '单仓模板'}
          ],
          'templateErrors': <Object>[],
        }
      });

      final b = await NxNxApi(pc: 'pc-a').bootstrap(endpointWith(client));
      expect(b.app.name, 'nx-nx');
      expect(b.app.version, '0.8.6');
      expect(b.templates, hasLength(1));
    });

    test('目标 PC 跟着请求走（两台机器都跑 nx-nx 时不能打错）', () async {
      String? pcHeader;
      String? appHeader;
      final client = recorder((req) {
        pcHeader = req.headers['X-Mn-Ws-Pc'];
        appHeader = req.headers['X-Mn-Ws-App'];
      }, body: {
        'ok': true,
        'data': {'status': 'ok', 'templates': []}
      });

      await NxNxApi(pc: 'pc-b').templates(endpointWith(client));
      expect(appHeader, 'nx-nx');
      expect(pcHeader, 'pc-b');
    });

    test('服务端报错 → 归类成 rejected，不把原始 body 糊出去', () async {
      final client = recorder((_) {}, body: {
        'ok': false,
        'message': '模板不存在',
      }, status: 400);

      await expectLater(
        NxNxApi(pc: 'pc-a').describe(endpointWith(client), 'nope'),
        throwsA(isA<MnWsException>()
            .having((e) => e.kind, 'kind', MnWsErrorKind.rejected)
            .having((e) => e.message, 'message', contains('模板不存在'))),
      );
    });
  });
}
