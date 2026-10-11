import 'package:shared_preferences/shared_preferences.dart';

/// 当前持有的这枚 access_token 是**谁签的**。
///
/// 为什么必须记这件事：不同签发方的"续期方式"完全不同，而从 token 字符串本身
/// 看不出来 —— 认证中心的 access_token 是不透明随机串，业务后端的 JWT 是三段
/// 点分 base64，长得像但含义毫无关系。靠"能不能 split('.')"去猜，
/// 是一条将来一定会被改错的隐式契约。
enum AuthTokenKind {
  /// 本地没有 token
  none,

  /// 统一认证中心签发（可刷新：拿 refresh_token 调认证中心的 token 端点）
  idp,

  /// 业务后端自己签发（邮箱密码登录的降级路径；无刷新端点，过期只能重新登录）
  legacyBackend,
}

/// Token/API Key 持久化接口。
abstract class TokenStorage {
  Future<String?> get accessToken;
  Future<String?> get refreshToken;
  Future<DateTime?> get expiresAt;
  Future<AuthTokenKind> get tokenKind;

  /// [kind] 留空表示"不改这一列"，与 [refreshToken]/[expiresAt] 的语义一致：
  /// 老代码只更新 accessToken 时，不该顺手把签发方抹成未知。
  Future<void> save({
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    AuthTokenKind? kind,
  });

  Future<void> clear();
}

/// SharedPreferences 实现。
class SharedPrefsTokenStorage implements TokenStorage {
  static const _keyAccess = 'api_access_token';
  static const _keyRefresh = 'api_refresh_token';
  static const _keyExpires = 'api_token_expires';
  static const _keyKind = 'api_token_kind';

  @override
  Future<String?> get accessToken async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccess);
  }

  @override
  Future<String?> get refreshToken async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRefresh);
  }

  @override
  Future<DateTime?> get expiresAt async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_keyExpires);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  @override
  Future<AuthTokenKind> get tokenKind async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyKind);
    return AuthTokenKind.values.firstWhere(
      (k) => k.name == raw,
      // 认不出就按 legacyBackend：这是引入该字段之前唯一存在的状态。
      // 老用户升级后不该突然变成"可刷新"，那会让他们对认证中心发出
      // 一个它从没签发过的 refresh 请求，报回来的是难以理解的 invalid_grant。
      orElse: () => AuthTokenKind.legacyBackend,
    );
  }

  @override
  Future<void> save({
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    AuthTokenKind? kind,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccess, accessToken);
    if (refreshToken != null) {
      await prefs.setString(_keyRefresh, refreshToken);
    }
    if (expiresAt != null) {
      await prefs.setInt(_keyExpires, expiresAt.millisecondsSinceEpoch);
    }
    if (kind != null) {
      await prefs.setString(_keyKind, kind.name);
    }
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccess);
    await prefs.remove(_keyRefresh);
    await prefs.remove(_keyExpires);
    await prefs.remove(_keyKind);
  }
}
