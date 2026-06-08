import 'token_storage.dart';

/// Token / API Key 生命周期管理。
///
/// 当前后端 Auth 中间件为可选（无 token 时跳过），
/// 此管理器已接入但处于**待用**状态，未来启用后：
/// - 自动从内存/持久化读取 token
/// - 401 时自动尝试 refresh
class TokenManager {
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  final TokenStorage _storage;

  TokenManager({required TokenStorage storage}) : _storage = storage;

  Future<String?> get accessToken async {
    if (_accessToken != null && !_isExpired) return _accessToken;
    await _hydrate();
    return _accessToken;
  }

  bool get _isExpired =>
      _expiresAt != null && DateTime.now().isAfter(_expiresAt!);

  Future<void> setAccessToken(String token) async {
    _accessToken = token;
    await _storage.save(accessToken: token);
  }

  Future<void> setTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _expiresAt = expiresAt;
    await _storage.save(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
    );
  }

  Future<bool> tryRefresh() async {
    if (_refreshToken == null) return false;
    return false; // 由具体实现覆盖
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    await _storage.clear();
  }

  Future<void> _hydrate() async {
    _accessToken = await _storage.accessToken;
    _refreshToken = await _storage.refreshToken;
    _expiresAt = await _storage.expiresAt;
  }
}
