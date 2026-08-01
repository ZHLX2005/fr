/// e2ekv — 端到端加密 KV（零知识同步）。
///
/// 与 goframe 其他端点不同：鉴权用派生的 AuthHash（不是登录 token），
/// 响应是裸 JSON（非 {code,message,data} 信封），因此自持 http.Client
/// —— 走 github/notion 模式。
///
/// 关键约定：
///   * AuthHash = 唯一凭证，一定要保存（参考 E2EKVStorage）
///   * 客户端必做加密算法（参考 E2EKVCrypto）
///   * 端点（参考 E2EKVEndpoint）
///   * 高级用法（参考 E2EKVClient）
library;

export 'e2ekv_config.dart';
export 'e2ekv_exception.dart';
export 'e2ekv_models.dart';
export 'e2ekv_crypto.dart';
export 'e2ekv_storage.dart';
export 'e2ekv_endpoint.dart';
export 'e2ekv_client.dart';