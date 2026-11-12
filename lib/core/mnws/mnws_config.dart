/// mn-ws（HTTP ⇄ WebSocket 双向桥）的连接参数。
///
/// 按 `api-module-auth` 规范 Rule 1/Rule 3：子目录 = 后端名，且**不共享** baseUrl
/// 与拦截器链 —— mn-ws 的响应形状（自己的端点字段平铺、被代理的 nx 响应是
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

  /// 认证中心地址。与 auth-hub 的 IDP_ISSUER 逐字一致。
  ///
  /// 刻意**不从 mn-ws 的 /auth/oidc/config 反推**：那个接口是给"没有认证中心
  /// 概念的调用方"用的兜底，而这里已知认证中心是谁 —— 两处各写一份的坏处是
  /// 改了一处忘了另一处，好处是断网时也不必先问一次服务器才知道该连哪。
  static const String issuer = 'http://47.110.80.47:8082';

  /// 认证中心的 token 端点（认证中心用非标准名，不是 /oauth2/token 之外的别名）。
  static const String tokenPath = '/oauth2/token';

  /// 本 App 在 mn-ws 侧的身份。
  ///
  /// 填 **mn-ws-client**（client 半的身份），不是 server 半的那个：
  /// mn-ws 两端在认证中心各有各的 client_id，client_id 是审计与吊销的单元，
  /// 共用一个就分不清「哪个平台在发 token」。服务端自己那一半是 mn-ws-server，
  /// 由 mn-ws server 半持有，本 App 不需要。
  static const String clientId = 'mn-ws-client';

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
  /// nx 服务（nx-kv 自己就读 `Authorization: Bearer`）。两层共用一个头会互相打架。
  /// 本 App 在 mn-ws 侧的**设备标识**（不是 OIDC 的 client_id）。
  ///
  /// mn-ws server 用它把「这台设备」绑到「这个用户」：一个标识只能属一个用户，
  /// 换绑会被拒（device_owned_by_other）。所以它必须**稳定** ——
  /// 每次启动都换一台「设备」，等于每次都换属主。
  static const String deviceId = 'fr-mn-ws';

  /// 设备显示名（server 侧的设备清单里显示）。
  static const String deviceName = 'FR（小豆子）';

  static const String gateHeader = 'X-Mn-Ws-Token';

  /// 应用标识的头名 —— 告诉 server 半「这个请求该去哪个本地端口」。
  static const String appHeader = 'X-Nx-App';

  /// 超时。
  ///
  /// mn-ws 是登录链路上的依赖，超时必须短；240 秒那种量级会让用户以为 App 卡死。
  static const Duration httpTimeout = Duration(seconds: 15);

  /// 换 token 时认证中心的超时（比普通请求短一点：它在内网链路上）。
  static const Duration tokenTimeout = Duration(seconds: 10);
}
