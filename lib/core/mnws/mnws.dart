/// mn-ws（HTTP ⇄ WebSocket 双向桥）的对外接口。
///
/// 分层：
///   · [mnws_config]   连接参数（URL / client_id / 头名）
///   · [mnws_models]   mn-ws 自己的响应形状
///   · [nxkv_models]   **被代理的** nx-kv 的响应形状（不是 mn-ws 的）
///   · [mnws_endpoint] 与 server 半对话的四个调用
///   · [mnws_grant_store] 设备令牌持久化
///   · [mnws_service]  编排（登录态 → 设备令牌 → 目录 / 请求）
///   · [mnws_page]     Lab 页面
///   · [mnws_providers] DI 装配
library;

export 'mnws_config.dart';
export 'mnws_endpoint.dart';
export 'mnws_grant_store.dart';
export 'mnws_models.dart';
export 'mnws_page.dart';
export 'mnws_providers.dart';
export 'mnws_service.dart';
export 'nxkv_models.dart';
