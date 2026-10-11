// lib/api/remotetype/remotetype_config.dart
//
// 远程输入桥（mn-rt）连接配置。按 api-module-auth 规范 Rule 1：
// 子目录 = 后端名，与 goframe/ github/ authhub/ 同级。
//
// 地址只出现在本文件（检测项 5）。

/// mn-rt 服务端地址。
///
/// 与 rt_constants 里那个常量是同一个值，但**刻意不 import 过去**：
/// lib/api/ 是后端层，lib/lab/ 是演示页。让 demo 目录反过来成为 API 层的
/// 依赖源，等于把"哪个是真地址"变成两处都要猜。这里以 api 层为准，
/// demo 侧引用本常量。
class RemoteTypeConfig {
  RemoteTypeConfig._();

  static const String serverBaseUrl = 'http://1.94.101.189:8790';

  /// mn-rt 与认证中心同处一个生态，但它是**独立后端**：自己的响应形状
  /// （裸对象，没有 goframe 那层 `code/data` 信封）、自己的凭据（本服务签发的
  /// 设备令牌），所以自持 http.Client，不套统一拦截器链（规范 Rule 3）。
  static const String authConfigPath = '/auth/oidc/config';
  static const String callbackPath = '/auth/oidc/callback';
  static const String verifyPath = '/auth/verify';
  static const String myDevicesPath = '/my/devices';

  /// 登录链路上的依赖，超时必须短；拿 240 秒等一个鉴权端点只会像卡死。
  static const Duration httpTimeout = Duration(seconds: 12);

  /// 设备令牌提前多久就视为要重新换。
  ///
  /// 服务端签的是 365 天，这里只防"边界上过期"的竞态，不做任何主动续期：
  /// 到期就重新走一次授权，不做静默续期（那会让用户再也不回到认证中心）。
  static const Duration expirySkew = Duration(minutes: 5);
}
