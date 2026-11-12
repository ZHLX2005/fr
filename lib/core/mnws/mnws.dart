/// mn-ws（HTTP ⇄ WebSocket 双向桥）的对外接口。
///
/// 分层：
///   · [mnws_config]   连接参数（URL / 头名）
///   · [mnws_models]   mn-ws 自己的响应形状
///   · [nxkv_models]   **被代理的** nx-kv 的响应形状（不是 mn-ws 的）
///   · [mnws_endpoint] 与 server 半对话的四个调用
///   · [mnws_grant_store] 业务令牌持久化
///   · [mnws_service]  编排（登录态 → 业务令牌 → 目录 / 请求）
///   · [mnws_page]     Lab 页面
///   · [mnws_providers] DI 装配
///
/// ── 为什么 nx-kv 的模型单独一层 ───────────────────────────────────────────
/// mn-ws 本身是**通用 HTTP 桥**，它不认识 nx-kv。这里认得 nx-kv 的是 **fr**：
/// fr 拿目录里的应用标识认出「这个是 nx-kv」，于是用 nx-kv 的形状解析它的响应。
/// 桥负责把请求送到，fr 负责知道对面是什么 —— 职责分开，桥才不用背着
/// 任何具体服务的知识。
library;

export 'mnws_config.dart';
export 'mnws_endpoint.dart';
export 'mnws_grant_store.dart';
export 'mnws_models.dart';
export 'mnws_page.dart';
export 'mnws_providers.dart';
export 'mnws_service.dart';
export 'nxkv_models.dart';
