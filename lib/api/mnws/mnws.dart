/// mn-ws（HTTP ⇄ WebSocket 双向桥）的对外接口。
///
/// ## 这个域的形状
///
///     lib/api/mnws/            ← 生命周期 + 元数据
///       mnws_config            连接参数（URL / 头名 / 身份）
///       mnws_endpoint          与 server 半对话的四个调用
///       mnws_models            mn-ws 自己的响应形状（含**按 PC 分组**的目录）
///       mnws_grant_store       业务令牌持久化
///       mnws_service           编排（登录态 → 业务令牌 → 目录 / 请求）
///       mnws_providers         DI 装配
///       mnws_app_client        被代理应用的接口客户端基类
///       <应用>/                ← 子目录：永远放应用（接口客户端）
///
///     lib/lab/demos/mnws/      ← 提供应用的 UI
///       mnws_home_page         首页：哪几台电脑接上来了，每台上跑着什么
///       mnws_app_views         **应用识别表**：标识 → 页面
///       mnws_request_page      通用请求台（不认得的应用也照样能调）
///       mnws_settings_page     模块设置页
///       <应用>/                ← 子目录：每个应用的界面
///
/// ## 为什么「谁认识这个应用」是 fr 的事
///
/// mn-ws 是**通用 HTTP 桥**，它只按标识路由，不认识 nx-nx 是什么、
/// 也不知道该给它什么界面。认得哪些标识、认得之后给什么页面，是 **fr** 的知识：
/// 应用识别表在 ui 层（`mnws_app_views.dart`），各应用的接口客户端在
/// `lib/api/mnws/<应用>/`。
///
/// 桥负责把请求送到，fr 负责知道对面是什么 —— 职责分开，桥才不用背着
/// 任何具体服务的知识。
library;

export 'mnws_app_client.dart';
export 'mnws_config.dart';
export 'mnws_endpoint.dart';
export 'mnws_grant_store.dart';
export 'mnws_models.dart';
export 'mnws_providers.dart';
export 'mnws_service.dart';
