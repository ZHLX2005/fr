/// mn-ws（HTTP ⇄ WebSocket 双向桥）的对外接口。
///
/// ## 这个域的形状
///
///     lib/api/mnws/            ← 生命周期 + 元数据
///       mnws_config            连接参数（URL / 头名 / 身份）
///       mnws_endpoint          与 server 半对话的四个调用
///       mnws_models            mn-ws 自己的响应形状（含**按 PC 分组**的目录 + 目标 MnWsAppTarget）
///       mnws_grant_store       业务令牌持久化
///       mnws_service           编排（登录态 → 业务令牌 → 目录 / 请求）
///       mnws_providers         DI 装配
///       mnws_app_client        被代理应用的接口客户端基类
///       <应用>/                ← 子目录：这个应用的**非 UI 全部**
///                                 · 接口客户端（nxkv_api / nxnx_api）
///                                 · 状态编排（nxkv_controller）
///                                 · 协议数据的解析（nxkv_md：正文的 frontmatter / 轮次）
///
///     lib/lab/demos/mnws/      ← 提供应用的 UI
///       mnws_home_page         首页：哪几台电脑接上来了，每台上跑着什么
///       mnws_app_views         **应用识别表**：标识 → 页面
///       mnws_request_page      通用请求台（不认得的应用也照样能调）
///       mnws_settings_page     模块设置页
///       <应用>/                ← 子目录：**只放界面**。这里出现 `ChangeNotifier`、
///                                 解析器、HTTP 字样，就是放错地方了
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
///
/// ## 为什么「非 UI 的一律进 api/<应用>/」
///
/// 一次踩过的坑：nx-kv 的 controller 原本长在 `lab/demos/mnws/nxkv/` 里，
/// 而它要用 `MnWsAppTarget`，那个类型当时定义在同层的 `mnws_app_views.dart`
/// （一个 import 了 material 的文件）—— 于是「数据入口」反向依赖了「界面」。
/// 想让 controller 单独测、或让命令行脚本复用它，都绕不开 UI。
///
/// 切分标准只有一条：**api 侧只依赖 `flutter/foundation`（`ChangeNotifier` 可以），
/// 不依赖 `flutter/material`**。某天某个文件为了拿类型去 import 视图文件，
/// 说明那个类型也该往 api 侧搬 —— `MnWsAppTarget` 就是这么搬进 mnws_models 的。
///
/// 体检方式是现成的：`tool/nxkv_smoke.dart` 是**不碰 flutter** 的纯 Dart 脚本，
/// 它还能 `dart run` 得动，就说明这条边界没被越过去。
library;

export 'mnws_app_client.dart';
export 'mnws_config.dart';
export 'mnws_endpoint.dart';
export 'mnws_grant_store.dart';
export 'mnws_models.dart';
export 'mnws_providers.dart';
export 'mnws_service.dart';
