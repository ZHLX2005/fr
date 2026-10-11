import 'package:shared_preferences/shared_preferences.dart';

/// 当前持有的这枚 access_token 是**谁签的**。
///
/// 为什么必须记这件事：两种 token 的**用途和有效期**完全不同，而从字符串本身
/// 看不出来 —— 认证中心的 access_token 是不透明随机串，业务后端的 JWT 是三段
/// 点分 base64，长得像但含义毫无关系。靠"能不能 split('.')"去猜，
/// 是一条将来一定会被改错的隐式契约。
enum AuthTokenKind {
  /// 本地没有 token
  none,

  /// 统一认证中心签发。短命（access_token 10 分钟），过期只能重新走一次授权 ——
  /// 客户端刻意不持有 refresh_token，详见 TokenManager 的说明。
  idp,

  /// 业务后端自己签发（邮箱密码登录的降级路径；无刷新端点，过期只能重新登录）
  legacyBackend,
}

/// Token/API Key 持久化接口。
abstract class TokenStorage {
  Future<String?> get accessToken;
  Future<DateTime?> get expiresAt;
  Future<AuthTokenKind> get tokenKind;

  Future<void> save({
    required String accessToken,
    DateTime? expiresAt,
    AuthTokenKind? kind,
  });

  Future<void> clear();
}

/// SharedPreferences 实现。
class SharedPrefsTokenStorage implements TokenStorage {
  static const _keyAccess = 'api_access_token';

  /// 旧版本写过这个键。**只删不写** —— 保留键名是为了把已经落盘的凭据清掉；
  /// 没有这一步，升级之后那个文件里的 refresh_token 会一直躺在磁盘上。
  static const _legacyKeyRefresh = 'api_refresh_token';
  static const _keyExpires = 'api_token_expires';
  static const _keyKind = 'api_token_kind';

  @override
  Future<String?> get accessToken async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccess);
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
    DateTime? expiresAt,
    AuthTokenKind? kind,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccess, accessToken);
    // 自愈式清除遗留键：只在 clear() 里删的话，已经装着旧版的设备要等到
    // 用户主动登出才会把磁盘上那枚 refresh_token 抹掉 —— 而"升级即清理"
    // 才符合"它不该存在于客户端"这个结论。
    if (prefs.containsKey(_legacyKeyRefresh)) {
      await prefs.remove(_legacyKeyRefresh);
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
    await prefs.remove(_legacyKeyRefresh);
    await prefs.remove(_keyExpires);
    await prefs.remove(_keyKind);
  }
}
