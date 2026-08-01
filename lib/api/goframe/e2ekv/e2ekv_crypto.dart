import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto_pkg show Hmac, sha256;

import 'e2ekv_config.dart';

/// e2ekv 客户端加密原语 —— 严格按 RFC / WebCrypto 协议实现：
///
///   KEK       = PBKDF2-SHA256(password, salt=16B, iter=600000, dkLen=32)
///   AuthKey   = HKDF-SHA256(KEK, salt=空, info="auth", L=32)
///   AuthHash  = hex(SHA256(AuthKey))               ← 唯一凭证/令牌（64 hex）
///   DEK_k     = HKDF-SHA256(KEK, salt=空, info=utf8(k), L=32)
///   ciphertext = AES-256-GCM(DEK_k, nonce=12B 随机, tag 追尾)
///
/// PBKDF2 / AES-GCM 用 `cryptography` 包（成熟稳定）。
/// HKDF 用 `crypto` 包手工 RFC 5869 实现 —— 避免依赖第三方 Hkdf API 命名歧义，
/// 确保 salt=空 与 WebCrypto 字节级一致。
class E2EKVCrypto {
  static final Random _rng = Random.secure();
  static final Pbkdf2 _pbkdf2 =
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: E2EKVConst.pbkdf2Iterations, bits: E2EKVConst.hkdfBytes * 8);
  static final AesGcm _aesGcm = AesGcm.with256bits();

  // ── KEK ──────────────────────────────────────────────
  static Future<SecretKey> deriveKek(
    String password,
    List<int> salt, {
    int? iterations,
  }) async {
    final algo = iterations == null
        ? _pbkdf2
        : Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: E2EKVConst.hkdfBytes * 8);
    return algo.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  // ── AuthKey / AuthHash ────────────────────────────────
  static Future<List<int>> deriveAuthKey(SecretKey kek) =>
      _hkdfSha256(ikmBytes: await kek.extractBytes(), info: utf8.encode('auth'));

  /// 64 位小写 hex；唯一凭证/令牌，一定要保存。
  static Future<String> authHash(SecretKey kek) async {
    final ak = await deriveAuthKey(kek);
    return _toHex(crypto_pkg.sha256.convert(ak).bytes);
  }

  // ── DEK ──────────────────────────────────────────────
  static Future<SecretKey> deriveDek(SecretKey kek, String k) async {
    final dk = await _hkdfSha256(ikmBytes: await kek.extractBytes(), info: utf8.encode(k));
    return SecretKey(dk);
  }

  // ── AES-GCM ─────────────────────────────────────────
  /// 返回 (nonce, ciphertext+tag)。nonce 用 Random.secure 生成。
  static Future<(List<int>, List<int>)> encrypt(SecretKey dek, List<int> plaintext) async {
    final nonce = _randomBytes(E2EKVConst.nonceBytes);
    final box = await _aesGcm.encrypt(plaintext, secretKey: dek, nonce: nonce);
    return (box.nonce, [...box.cipherText, ...box.mac]);
  }

  static Future<List<int>> decrypt(SecretKey dek, List<int> nonce, List<int> ciphertextWithTag) async {
    const macLen = 16;
    final ct = ciphertextWithTag.sublist(0, ciphertextWithTag.length - macLen);
    final mac = ciphertextWithTag.sublist(ciphertextWithTag.length - macLen);
    return _aesGcm.decrypt(SecretBox(ct, nonce: nonce, mac: mac), secretKey: dek);
  }

  // ── 工具 ─────────────────────────────────────────────
  static List<int> randomBytes(int n) => List<int>.generate(n, (_) => _rng.nextInt(256));

  // ── HKDF-SHA256 (RFC 5869) ───────────────────────────
  /// Empty salt: RFC 5869 默认是 HashLen 个零字节 —— 与 WebCrypto `new Uint8Array()` 字节级一致。
  static Future<List<int>> _hkdfSha256({
    required List<int> ikmBytes,
    required List<int> info,
    int length = E2EKVConst.hkdfBytes,
  }) async {
    // Extract: PRK = HMAC-SHA256(salt, IKM); salt 默认 32 个 0x00
    final salt = List<int>.filled(32, 0);
    final prk = crypto_pkg.Hmac(crypto_pkg.sha256, salt).convert(ikmBytes).bytes;

    // Expand: T(i) = HMAC-SHA256(PRK, T(i-1) || info || i), L<=hashlen 只需一轮
    final t = crypto_pkg.Hmac(crypto_pkg.sha256, prk)
        .convert([...<int>[], ...info, 1])
        .bytes;
    return t.sublist(0, length);
  }

  static List<int> _randomBytes(int n) => List<int>.generate(n, (_) => _rng.nextInt(256));
  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}