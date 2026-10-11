/// 认证中心（go-ah auth-hub）后端 —— 统一登录与扫码登录。
///
/// 目录即后端名（规范 Rule 1）。看代码前先读 [AuthHubConfig] 的注释：
/// 为什么这个后端不能套 goframe 那条拦截器链。
library;

export 'authhub_config.dart';
export 'authhub_exception.dart';
export 'authhub_models.dart';
export 'authhub_pkce.dart';
export 'authhub_oidc_endpoint.dart';
export 'authhub_qr_endpoint.dart';
