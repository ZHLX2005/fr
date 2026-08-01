import 'package:shared_preferences/shared_preferences.dart';

import 'e2ekv_config.dart';

/// e2ekv 本地凭证存储 —— **AuthHash 是唯一凭证，一定要保存**。
///
/// 默认用 SharedPreferences（应用沙盒）。生产场景建议改用
/// `flutter_secure_storage` / Android Keystore（更难被取走），
/// 但与项目其他 Token（token_storage）一致先用 SharedPreferences。
class E2EKVStorage {
  static const _kAuthHash = 'e2ekv.auth_hash';
  static const _kSalt = 'e2ekv.salt';
  static const _kIter = 'e2ekv.iter';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<String?> get authHash async => (await _prefs()).getString(_kAuthHash);
  Future<String?> get salt async => (await _prefs()).getString(_kSalt);
  Future<int> get iter async =>
      (await _prefs()).getInt(_kIter) ?? E2EKVConst.pbkdf2Iterations;

  Future<bool> get hasCredential async =>
      (await authHash) != null && (await salt) != null;

  Future<void> saveCredential({
    required String authHash,
    required String salt,
    required int iter,
  }) async {
    final prefs = await _prefs();
    await prefs.setString(_kAuthHash, authHash);
    await prefs.setString(_kSalt, salt);
    await prefs.setInt(_kIter, iter);
  }

  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(_kAuthHash);
    await prefs.remove(_kSalt);
    await prefs.remove(_kIter);
  }
}