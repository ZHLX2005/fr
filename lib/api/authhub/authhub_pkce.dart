import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE(RFC 7636) + state + nonce 生成器。
///
/// 为什么必须有 PKCE：本 App 是**公共客户端**，编译进 APK 的任何密钥都能被
/// 反编译拿走，所以它不能有 client_secret。没有 PKCE 的公共客户端，
/// 授权码在浏览器历史、日志、或恶意 App 注册的自定义 scheme 里泄露后，
/// 捡到的人可以直接去换 token。PKCE 让"没有发起这次授权的人换不出 token"，
/// 因为 code_verifier 只存在于 App 内存里，从没经过浏览器。
///
/// 认证中心对 `pkce_required=true` 的客户端强制校验，缺 verifier 直接拒。
class AuthPkce {
  /// 只有本 App 知道的那一串（发给 token 端点，不进浏览器）
  final String codeVerifier;

  /// 进授权 URL 的那一串：BASE64URL(SHA256(verifier))
  final String codeChallenge;

  /// 固定为 S256。**不发 plain**：plain 等于把 verifier 明文写进授权 URL，
  /// PKCE 的保护作用直接归零。认证中心虽然同时接受两者，
  /// 但那是给老客户端的兼容路径，新代码没有理由走。
  final String codeChallengeMethod;

  /// 防 CSRF：回调时必须与发起时一致。
  final String state;

  /// 绑给 id_token 的一次性随机值，防 id_token 重放。
  final String nonce;

  const AuthPkce._({
    required this.codeVerifier,
    required this.codeChallenge,
    required this.codeChallengeMethod,
    required this.state,
    required this.nonce,
  });

  /// 生成一整套一次性授权参数。每次授权都必须新建，不可复用。
  factory AuthPkce.generate() {
    final verifier = _randomUrlSafe(32);
    final digest = sha256.convert(utf8.encode(verifier));
    return AuthPkce._(
      codeVerifier: verifier,
      codeChallenge: _base64UrlNoPad(digest.bytes),
      codeChallengeMethod: 'S256',
      state: _randomUrlSafe(24),
      nonce: _randomUrlSafe(24),
    );
  }

  /// 授权请求里要带的 PKCE 参数对。
  Map<String, String> get challengeParams => {
        'code_challenge': codeChallenge,
        'code_challenge_method': codeChallengeMethod,
      };
}

// ── 随机源 ──────────────────────────────────────────────────────────────────

/// 密码学安全随机源。
///
/// 刻意用 `Random.secure()` 而不是 `List.generate(..., Random())`：
/// state / nonce / code_verifier 都是安全参数，用可预测的伪随机生成，
/// 攻击者能算出下一次的值，PKCE 与 CSRF 防护同时失效 ——
/// 而这种写法在功能测试里**完全看不出来**，一切都能跑通。
final Random _secureRandom = Random.secure();

String _randomUrlSafe(int bytes) {
  final data = List<int>.generate(bytes, (_) => _secureRandom.nextInt(256));
  return _base64UrlNoPad(data);
}

/// base64url 且去掉尾部 `=`。
///
/// 去填充是 OAuth 参数的通行写法（RFC 7636 §4.1 要求 code_challenge 用
/// unreserved 字符集）；留着 `=` 在某些 URL 编码实现里会变成 `%3D`，
/// 认证中心按字面比对就会算作不匹配。
String _base64UrlNoPad(List<int> data) =>
    base64Url.encode(data).replaceAll('=', '');
