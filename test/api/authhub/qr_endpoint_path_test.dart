import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/api/authhub/authhub_qr_endpoint.dart';
import 'package:xiaodouzi_fr/api/authhub/idp_session_store.dart';

/// 钉住**请求路径**，而不是响应解析。
///
/// 为什么必须有这一份：上一版只测了 QrPreview.fromJson（喂理想 payload），
/// 于是 preview() 少写 `/preview` 后缀、打到 PC 侧轮询端点这件事完全没被发现 ——
/// 那个端点返回 200、结构合法、只是没有 pc 字段。
/// 解析层测得再细，URL 打错一样全空，而症状是"扫码不可用"却不报任何错。
/// 所以这里断言的是"每个方法到底请求了哪个 path"。
void main() {
  final requested = <String>[];
  // 手机侧四条端点现在自己从注入的登录态存储取凭据，
  // 所以测试必须给一个"有登录态"的存储，否则会先被 requireSession 拦下。
  final store = _StubSessionStore();
  final client = MockClient((req) async {
    requested.add('${req.method} ${req.url.path}');
    return http.Response(
      jsonEncode({
        'code': 0,
        'data': {
          'status': 'pending',
          'expires_in': 118,
          'pc': {'ua': 'Edge · Windows', 'ip': '10.0.0.5', 'geo': '内网'},
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  setUp(() => requested.clear());

  test('八个端点各自请求正确的路径', () async {
    final api = AuthHubQrEndpoint(
        client: client, issuer: 'http://idp.test', sessionStore: store);
    const t = 'qrt_abc123';

    await api.create();
    await api.poll(t);
    await api.claim(t);
    await api.cancel(t);
    await api.preview(t);
    await api.scan(t);
    await api.confirm(t);
    await api.refuse(t);

    expect(requested, [
      'POST /api/qr/sessions',
      'GET /api/qr/sessions/$t',
      'POST /api/qr/sessions/$t/claim',
      'POST /api/qr/sessions/$t/cancel',
      'GET /api/qr/sessions/$t/preview',
      'POST /api/qr/sessions/$t/scan',
      'POST /api/qr/sessions/$t/confirm',
      'POST /api/qr/sessions/$t/refuse',
    ]);
  });

  test('preview 必须走 /preview，否则会拿到没有 pc 字段的轮询响应', () async {
    final api = AuthHubQrEndpoint(
        client: client, issuer: 'http://idp.test', sessionStore: store);
    final p = await api.preview('qrt_abc123');
    // 画像有值是 /preview 才有的语义；轮询端点不返回 pc
    expect(p.pcUa, 'Edge · Windows');
    expect(p.hasMeaningfulDeviceInfo, isTrue);
  });
}


/// 有登录态的桩存储。
class _StubSessionStore extends IdpSessionStore {
  @override
  Future<String?> read() async => 'stub-idp-session';
}
