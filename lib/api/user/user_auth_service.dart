import 'dart:convert';
import 'package:http/http.dart' as http;
import '../token/token_storage.dart';

/// 认证接口调用结果。
///
/// 对齐 dev_ctr_hello 后端的 `{ code, message, data }` 信封：
/// **业务错误（code=50/51）HTTP 状态仍是 200**，判断成败必须看 [code]。
class AuthResult {
  /// 0=成功；50=业务错误；51=参数校验错误；401=未登录；-1=网络/解析错误
  final int code;
  final String message;
  final Map<String, dynamic>? data;

  const AuthResult({required this.code, required this.message, this.data});

  bool get isSuccess => code == 0;
}

/// 用户认证服务 —— 对接 dev_ctr_hello 后端（与 GoFrame 同址 47.110.80.47:8988）。
///
/// 无状态服务，注册为 GetIt 单例，供登录/注册卡片调用。
/// 登录成功后 token 写入 [SharedPrefsTokenStorage]（key 与 AuthInterceptor
/// 读取的一致），下次任意走 ApiClient 的请求自动带 Bearer。
class UserAuthService {
  /// 后端 base，user 接口前缀 /api/v1
  static const _baseUrl = 'http://47.110.80.47:8988/api/v1';

  final TokenStorage _storage = SharedPrefsTokenStorage();
  final http.Client _client = http.Client();

  Future<AuthResult> _post(String path, Map<String, dynamic> body) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return AuthResult(
        code: (json['code'] as num?)?.toInt() ?? -1,
        message: json['message'] as String? ?? '',
        data: json['data'] as Map<String, dynamic>?,
      );
    } catch (e) {
      return AuthResult(code: -1, message: '网络错误: $e');
    }
  }

  /// 发送验证码（60s 冷却、10min 有效，由后端控制）
  Future<AuthResult> sendCode(String email, {String purpose = 'register'}) =>
      _post('/user/send-code', {'email': email, 'purpose': purpose});

  /// 注册（invitationCode 必填）
  Future<AuthResult> register({
    required String email,
    required String password,
    required String code,
    required String invitationCode,
    String? nickname,
  }) =>
      _post('/user/register', {
        'email': email,
        'password': password,
        'code': code,
        'invitationCode': invitationCode,
        if (nickname != null && nickname.isNotEmpty) 'nickname': nickname,
      });

  /// 登录 → 成功写 token 到 SharedPreferences
  Future<AuthResult> login(String email, String password) async {
    final r = await _post('/user/login', {'email': email, 'password': password});
    if (r.isSuccess && r.data != null) {
      final token = r.data!['token'] as String?;
      if (token != null && token.isNotEmpty) {
        await _storage.save(accessToken: token);
      }
    }
    return r;
  }
}
