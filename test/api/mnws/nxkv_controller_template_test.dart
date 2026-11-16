/// 新建任务正文的**接线**（fr #23）：controller 取服务端默认模板，取不到就兜底。
///
/// 规则本身在 `nxkv_template_test.dart` 里钉；这里只验「真的打了那一枪、
/// 失败真的没抛」—— 派活是主路径，模板取不回来只是正文朴素一点，不能变成派不出去。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/api/mnws/mnws.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_controller.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_template.dart';

const _sop = '## 本轮问题\n\n（把你要问这个仓库的问题写在这里）\n';

MnWsGrant _grant(String token) => MnWsGrant(
      token: token,
      userId: '5',
      email: '',
      nickname: '管理员',
      clientId: 'fr-mn-ws',
      deviceName: 'FR',
      tokenExpiresAt: 99999999999999,
    );

NxKvController _controller(MockClient client) => NxKvController(
      target: const MnWsAppTarget(
        pc: MnWsPcGroup(
          bridgeId: 'laptop-test',
          name: 'test-pc',
          userId: 'u1',
          connectedAt: '',
          apps: [],
        ),
        pcApp: MnWsPcApp(
          app: 'nx-kv',
          title: 'nx-kv',
          port: null,
          base: null,
          bridgeId: 'laptop-test',
          alive: true,
        ),
      ),
      endpoint: MnWsEndpoint(
        client: client,
        baseUrl: 'http://mws.test',
        grantReader: () async => _grant('device-token'),
      ),
    );

void main() {
  test('newTaskBody：取 defaultId 指向的模板正文', () async {
    String? path;
    final c = _controller(MockClient((req) async {
      path = req.url.path;
      return http.Response(
        jsonEncode({
          'ok': true,
          'data': {
            'defaultId': 'newtask.ref',
            'templates': [
              {'id': 'newtask.ref', 'name': 'ref 生成', 'body': _sop},
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }));

    final body = await c.newTaskBody();
    expect(path, '/api/templates');
    expect(body, _sop);
  });

  test('newTaskBody：拉不到就是兜底正文，不抛', () async {
    final c = _controller(MockClient((req) async => http.Response('<html>502</html>', 502)));
    final body = await c.newTaskBody();
    expect(body, nxKvNewTaskFallbackBody, reason: '断网也要能派活，只是正文朴素');
  });
}
