import 'package:shared_preferences/shared_preferences.dart';

/// Token/API Key 持久化接口。
abstract class TokenStorage {
  Future<String?> get accessToken;
  Future<String?> get refreshToken;
  Future<DateTime?> get expiresAt;

  Future<void> save({
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  });

  Future<void> clear();
}

/// SharedPreferences 实现。
class SharedPrefsTokenStorage implements TokenStorage {
  static const _keyAccess = 'api_access_token';
  static const _keyRefresh = 'api_refresh_token';
  static const _keyExpires = 'api_token_expires';

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
  Future<void> save({
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccess, accessToken);
    if (refreshToken != null) {
      await prefs.setString(_keyRefresh, refreshToken);
    }
    if (expiresAt != null) {
      await prefs.setInt(_keyExpires, expiresAt.millisecondsSinceEpoch);
    }
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccess);
    await prefs.remove(_keyRefresh);
    await prefs.remove(_keyExpires);
  }
}
