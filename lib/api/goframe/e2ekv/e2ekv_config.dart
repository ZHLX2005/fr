/// e2ekv 配置 + 协议常量（与后端约定，一字不能改）。
library;

/// 网络配置。
class E2EKVConfig {
  final String baseUrl;
  final Duration timeout;
  const E2EKVConfig({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 30),
  });
  factory E2EKVConfig.production() =>
      const E2EKVConfig(baseUrl: 'http://47.110.80.47:8988');
}

/// 协议常量 —— 与服务端 hack/migrations + docs/api/e2ekv.md 完全一致。
abstract final class E2EKVConst {
  /// KDF 算法名（kdf_meta.kdf.name）
  static const String kdfName = 'PBKDF2-SHA256';

  /// 对称算法名
  static const String cipherName = 'AES-256-GCM';

  /// PBKDF2 迭代次数 —— 服务端硬校验范围 100k–1000k
  static const int pbkdf2Iterations = 600000;

  /// HKDF 输出长度（256 bit）
  static const int hkdfBytes = 32;

  /// AES-GCM nonce 长度（96 bit，服务端硬校验）
  static const int nonceBytes = 12;

  /// AuthHash 长度（SHA-256 → 64 hex）
  static const int authHashHexLen = 64;

  /// 盐长度（服务端硬校验）
  static const int saltBytes = 16;

  /// kdf_meta 版本
  static const int kdfMetaVersion = 1;

  /// 单资源最大密文字节（服务端硬校验 1 MiB）
  static const int maxCiphertextBytes = 1 << 20;
}