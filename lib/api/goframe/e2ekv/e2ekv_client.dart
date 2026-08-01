import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'e2ekv_config.dart';
import 'e2ekv_crypto.dart';
import 'e2ekv_endpoint.dart';
import 'e2ekv_exception.dart';
import 'e2ekv_models.dart';
import 'e2ekv_storage.dart';

/// e2ekv 高级客户端 —— 持有派生状态（KEK/AuthHash），负责加密+同步。
///
/// **AuthHash 是唯一凭证** —— 调用 [setup] 后务必用 [E2EKVStorage]
/// 保存到本地（库内已自动保存）；**密码/KEK/AuthKey 仅在内存**，不落盘。
///
/// 典型流程：
///   final client = E2EKVClient(...);
///   await client.setup('strong-password');
///   await client.put('prompt:vip-call', utf8.encode('...'));
///   final pt = await client.get('prompt:vip-call');
///   // 换设备：await client.login('strong-password'); （用 storage 里的 salt/iter）
class E2EKVClient {
  final E2EKVEndpoint _endpoint;
  final E2EKVStorage _storage;

  SecretKey? _kek;
  String? _authHash;
  String? _saltB64;
  int _iter = E2EKVConst.pbkdf2Iterations;

  E2EKVClient({required E2EKVEndpoint endpoint, required E2EKVStorage storage})
      : _endpoint = endpoint,
        _storage = storage;

  String? get authHash => _authHash;
  bool get isReady => _authHash != null && _kek != null;

  // ── setup / login ──────────────────────────────────────

  /// 首次注册：生成随机 salt(16B) → 派生 KEK/AuthHash → 注册 → 保存凭证。
  /// 已注册时（409）视为幂等成功，**不抛异常**。
  Future<void> setup(String password) async {
    final salt = E2EKVCrypto.randomBytes(E2EKVConst.saltBytes);
    await _derive(password, salt);
    try {
      await _endpoint.setup(
        authHash: _requireAuth(),
        kdf: KdfParams(
          name: E2EKVConst.kdfName,
          iter: _iter,
          salt: base64Encode(salt),
        ),
      );
    } on E2EKVException catch (e) {
      if (e.statusCode != 409) rethrow;
      // 409 = 已注册；视为幂等，凭证已落库，下次 login 即可
    }
    await _storage.saveCredential(
      authHash: _requireAuth(),
      salt: base64Encode(salt),
      iter: _iter,
    );
  }

  /// 恢复登录：用保存的 salt/iter + 密码重新派生。
  Future<void> login(String password, {String? saltB64, int? iter}) async {
    final sB64 = saltB64 ?? await _storage.salt;
    final it = iter ?? await _storage.iter;
    if (sB64 == null) {
      throw StateError('没有保存的 salt —— 无法恢复；请先 setup 或显式传入 saltB64');
    }
    await _derive(password, base64Decode(sB64), iter: it);
  }

  Future<void> _derive(String password, List<int> salt, {int? iter}) async {
    _iter = iter ?? E2EKVConst.pbkdf2Iterations;
    _saltB64 = base64Encode(salt);
    _kek = await E2EKVCrypto.deriveKek(password, salt, iterations: _iter);
    _authHash = await E2EKVCrypto.authHash(_kek!);
  }

  // ── 同步操作（自动加密/解密）──────────────────────────

  Future<ListRes> list({int limit = 100, int offset = 0}) =>
      _endpoint.list(authHash: _requireAuth(), limit: limit, offset: offset);

  /// 拉取并解密（拿到明文）。
  Future<List<int>> get(String k) async {
    final res = await _endpoint.get(authHash: _requireAuth(), k: k);
    final dek = await E2EKVCrypto.deriveDek(_requireKek(), k);
    return E2EKVCrypto.decrypt(
      dek,
      base64Decode(res.nonce),
      base64Decode(res.ciphertext),
    );
  }

  /// 加密写入：先 GET 拿 version（首次=1），遇乐观锁 409 自动重拉重试（上限 3）。
  Future<PutRes> put(String k, List<int> plaintext) async {
    const maxRetries = 3;
    var attempt = 0;
    while (true) {
      attempt++;
      final ah = _requireAuth();
      final version = await _currentVersionOrOne(k);
      final dek = await E2EKVCrypto.deriveDek(_requireKek(), k);
      final (nonce, ct) = await E2EKVCrypto.encrypt(dek, plaintext);
      try {
        return await _endpoint.put(
          authHash: ah,
          k: k,
          version: version,
          nonce: base64Encode(nonce),
          ciphertext: base64Encode(ct),
          kdfMeta: KdfBlobMeta(
            v: E2EKVConst.kdfMetaVersion,
            kdf: KdfParams(
              name: E2EKVConst.kdfName,
              iter: _iter,
              salt: _requireSaltB64(),
            ),
            cipher: E2EKVConst.cipherName,
            dekInfo: k,
          ),
        );
      } on E2EKVException catch (e) {
        if (e.statusCode == 409 && attempt <= maxRetries) {
          // 乐观锁冲突：重拉 version 重试
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        rethrow;
      }
    }
  }

  Future<int> _currentVersionOrOne(String k) async {
    try {
      final cur = await _endpoint.get(authHash: _requireAuth(), k: k);
      return cur.version + 1;
    } on E2EKVException catch (e) {
      if (e.statusCode == 404) return 1;
      rethrow;
    }
  }

  Future<DeleteRes> delete(String k) =>
      _endpoint.delete(authHash: _requireAuth(), k: k);

  Future<bool> healthz() => _endpoint.healthz();

  // ── 内部 ──────────────────────────────────────────────
  String _requireAuth() {
    final ah = _authHash;
    if (ah == null) throw StateError('未 setup/login e2ekv —— AuthHash 为空');
    return ah;
  }

  SecretKey _requireKek() {
    final kek = _kek;
    if (kek == null) throw StateError('未派生 KEK —— 先 setup/login');
    return kek;
  }

  String _requireSaltB64() {
    final s = _saltB64;
    if (s == null) throw StateError('salt 未生成');
    return s;
  }
}