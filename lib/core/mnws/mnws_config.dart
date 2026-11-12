/// mn-ws（HTTP ⇄ WebSocket 双向桥）的连接参数。
///
/// 按 `api-module-auth` 规范 Rule 1/Rule 3：子目录 = 后端名，且**不共享** baseUrl
/// 与拦截器链 —— mn-ws 的响应形状（自己的端点字段平铺、被代理的服务是
/// `{ok, data}` 信封）与其它后端都不同，套同一条链会让拦截器把别的 token 注进来。
///
/// URL 只能出现在这个文件里（规范检测项 5）。
library;

/// mn-ws 的连接配置。
class MnWsConfig {
  MnWsConfig._();

  /// mn-ws server 半的对外地址。
  ///
  /// 与 mn-ws 自己的 `MN_WS_*` 配置逐字一致；换部署就改这里一处。
  static const String baseUrl = 'http://1.94.101.189:7777';

  /// mn-ws 自己的**业务令牌端点**：拿授权码换一枚 mn-ws 的令牌。
  ///
  /// 与 mn-rt 的同名端点同一形状 —— 换码在**服务端**做，认证中心的
  /// access_token / refresh_token 一次都不出服务端。
  static const String callbackPath = '/auth/oidc/callback';

  /// 申请的 scope。
  static const List<String> scopes = ['openid', 'profile', 'email'];

  /// 授权回调地址。
  ///
  /// mn-ws-client 在认证中心的白名单是 `http://127.0.0.1:*/callback` —— 端口通配、
  /// 路径固定。本 App **不真的监听这个端口**：授权码是从认证中心的同意响应里
  /// 直接取走的（mintCodeForClient 返回），所以端口只需要「合法且每次不一样」。
  static const String redirectHost = '127.0.0.1';
  static const String redirectPath = '/callback';

  /// 名义上的回调端口。没有服务在听，但必须是数字（认证中心的白名单只放行数字端口）。
  static const int redirectPort = 39471;

  static String get redirectUri =>
      'http://$redirectHost:$redirectPort$redirectPath';

  /// L1 通道层凭据的头名 —— **与 Authorization 分开**。
  ///
  /// mn-ws server 剥掉 `X-Mn-Ws-Token` 再转发，`Authorization` 整个留给被代理的
  /// 服务（被代理的服务自己就读 `Authorization: Bearer`）。两层共用一个头会互相打架。
  static const String gateHeader = 'X-Mn-Ws-Token';

  /// 应用标识的头名 —— 告诉 server 半「这个请求该去哪个本地端口」。
  static const String appHeader = 'X-Mn-Ws-App';

  /// 超时。
  ///
  /// mn-ws 是登录链路上的依赖，超时必须短；240 秒那种量级会让用户以为 App 卡死。
  static const Duration httpTimeout = Duration(seconds: 15);
}
