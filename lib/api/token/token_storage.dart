import 'package:shared_preferences/shared_preferences.dart';

/// 业务后端（dev_ctr_hello / 8988）会话凭据的持久化接口。
///
/// 这里**只放一枚 token**：业务后端自己签发的 JWT。
/// 统一登录平台的登录态在 `lib/api/authhub/idp_session_store.dart` ——
/// 两者回答的问题不同、生命周期不同、吊销路径也不同，所以不共用一个槽位。
///
/// 之前的 refreshToken / expiresAt / AuthTokenKind 三个字段已随
/// "App 直连认证中心取 token"那条设计一起退场。
abstract class TokenStorage {
  Future<String?> get accessToken;

  Future<void> save({required String accessToken});

  Future<void> clear();
}

/// SharedPreferences 实现。
class SharedPrefsTokenStorage implements TokenStorage {
  static const _keyAccess = 'api_access_token';

  /// 升级前遗留的键：**只删不写**。
  ///
  /// 必须在 save() 里一起清掉，而不是只在 clear() 里删 ——
  /// 装过旧版本的设备若用户从不主动登出，磁盘上那枚 refresh_token
  /// 就会一直留着。"它不该存在于客户端"是个结论，
  /// 不该依赖用户去做某个动作才成立。
  static const _legacyKeys = [
    'api_refresh_token',
    'api_token_expires',
    'api_token_kind',
    'idp_session', // 登录态有自己的存储，别留两份
  ];

  @override
  Future<String?> get accessToken async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccess);
  }

  @override
  Future<void> save({required String accessToken}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccess, accessToken);
    for (final k in _legacyKeys) {
      if (prefs.containsKey(k)) await prefs.remove(k);
    }
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccess);
    for (final k in _legacyKeys) {
      await prefs.remove(k);
    }
  }
}
