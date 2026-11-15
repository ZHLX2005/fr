import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/api/mnws/mnws.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_api.dart';

/// 契约之外的那两次读：**组清单**与**附件字节**。
///
/// 这一层最容易错在两处，用例就钉这两处：
///   1. 请求确实带了应用标识头（`X-Mn-Ws-App`）—— 不带的话 server 半不知道
///      该把它转给哪个本地服务，回的是 400 app_required；
///   2. 附件是**原始字节**，不能经 UTF-8 解码再编码 —— PNG 的开头 0x89 就不是
///      合法 UTF-8，走 String 那条路回来的图必然画不出来。
void main() {
  MnWsEndpoint endpointWith(MockClient client) => MnWsEndpoint(
        client: client,
        baseUrl: 'http://mws.test',
        grantReader: () async => _grant('device-token'),
      );

  test('组清单：走 /api/boards，带应用标识，解析出组名与成员', () async {
    String? app;
    String? path;
    final endpoint = endpointWith(MockClient((req) async {
      app = req.headers['X-Mn-Ws-App'];
      path = req.url.path;
      return http.Response(
        jsonEncode({
          'ok': true,
          'data': {
            'boards': [
              {
                'id': 'b1',
                'name': 'mobile',
                'key': 'group/mobile',
                'repos': [
                  {'key': 'github.com/zhlx2005/fr', 'id': 'r1'},
                ],
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }));

    final boards = await NxKvApi(pc: 'pc-1').boards(endpoint);

    expect(path, '/api/boards');
    expect(app, 'nx-kv');
    expect(boards.single.name, 'mobile');
    expect(boards.single.repoKeys, ['github.com/zhlx2005/fr']);
  });

  test('组清单读不到时返回空列表（装饰而已，不该抛）', () async {
    final endpoint = endpointWith(MockClient((req) async => http.Response('<html>502</html>', 502)));
    expect(await NxKvApi(pc: 'pc-1').boards(endpoint), isEmpty);
  });

  test('附件字节：GET /api/file/content/<id>，字节原样返回（不解码成 String）', () async {
    // 故意用 PNG 魔数开头：0x89 不是合法 UTF-8，走 String 那条路会被换成 U+FFFD
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0xFF]);
    String? path;
    String? accept;
    final endpoint = endpointWith(MockClient((req) async {
      path = req.url.path;
      accept = req.headers['Accept'];
      return http.Response.bytes(png, 200, headers: {'content-type': 'image/png'});
    }));

    final bytes = await NxKvApi(pc: 'pc-1')
        .attachmentBytes(endpoint, 'a123729ded0766277b9e91500b2a98a3');

    expect(path, '/api/file/content/a123729ded0766277b9e91500b2a98a3');
    // 二进制不要 Accept: application/json
    expect(accept, '*/*');
    expect(bytes, png);
  });

  test('附件不存在（404）时抛得出来，且带上服务端原话', () async {
    // 用 bytes 构造：http.Response(String) 默认按 latin1 编码，中文会直接抛
    final endpoint = endpointWith(
      MockClient((req) async => http.Response.bytes(utf8.encode('附件不存在: xxx'), 404)),
    );

    await expectLater(
      NxKvApi(pc: 'pc-1').attachmentBytes(endpoint, 'deadbeef'),
      throwsA(isA<MnWsException>()
          .having((e) => e.kind, 'kind', MnWsErrorKind.rejected)
          .having((e) => e.message, 'message', contains('HTTP 404'))),
    );
  });

  test('空 id 直接拒绝：不去请求一个 /api/file/content/ 的空路径', () async {
    var called = false;
    final endpoint = endpointWith(MockClient((req) async {
      called = true;
      return http.Response('', 200);
    }));

    await expectLater(
      NxKvApi(pc: 'pc-1').attachmentBytes(endpoint, '  '),
      throwsA(isA<MnWsException>()),
    );
    expect(called, isFalse);
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
