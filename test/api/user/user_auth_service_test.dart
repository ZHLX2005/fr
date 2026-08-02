import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/api/user/user_auth_service.dart';

void main() {
  // MockClient 内部访问 ServicesBinding.instance —— 必须在任何 mock 构造之前初始化。
  TestWidgetsFlutterBinding.ensureInitialized();
  // _storage.accessToken 走 SharedPreferences.getInstance()；测试无 platform channel，
  // 用空初始值 mock 掉。token=null，Authorization 头不会被加。
  SharedPreferences.setMockInitialValues({});

  test('userInfo parses envelope and returns AuthResult', () async {
    final mock = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.path, endsWith('/api/v1/user/info'));
      return http.Response(
        jsonEncode({
          'code': 0,
          'message': 'OK',
          'data': {
            'id': 1,
            'email': 'a@b.c',
            'username': '',
            'nickname': 'nick',
            'invitationCode': 'ABC12345',
          },
        }),
        200,
        headers: {'Content-Type': 'application/json'},
      );
    });

    final r = await http.runWithClient(
      () => UserAuthService().userInfo(),
      () => mock,
    );
    expect(r.code, 0, reason: 'got code=${r.code} msg=${r.message}');
    expect(r.data?['email'], 'a@b.c');
    expect(r.data?['nickname'], 'nick');
    expect(r.data?['invitationCode'], 'ABC12345');
  });

  test('userInfo surfaces HTTP 401 envelope', () async {
    final mock = MockClient((req) async {
      return http.Response(
        jsonEncode({'code': 401, 'message': 'unauthorized'}),
        401,
        headers: {'Content-Type': 'application/json'},
      );
    });

    final r = await http.runWithClient(
      () => UserAuthService().userInfo(),
      () => mock,
    );
    expect(r.isSuccess, false);
    expect(r.code, 401);
  });
}
