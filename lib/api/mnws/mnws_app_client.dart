import 'mnws_endpoint.dart';
import 'mnws_models.dart';

/// 被代理应用的**接口客户端**基类。
///
/// 公共能力只有一件：**经桥发请求**。各应用再在上面加自己的方法
/// （nx-nx 的「列模板」「读脚本」……）。
///
/// 为什么要基类：每个应用的请求都要带三样东西 —— 路由标识、目标 PC、
/// 业务令牌。这三样都在 [MnWsEndpoint] 里，应用自己重复一遍只会写出
/// 「忘了带令牌」的 bug。
///
/// 依赖的是**端点**而不是编排层：端点才是「怎么发一次请求」的地方，
/// 编排层管的是「凭据没了怎么办」—— 那与应用无关。
///
/// 「这个标识是什么应用、该给它什么界面」是 **fr 侧**的知识，
/// 登记在 ui 层（`lab/demos/mnws/mnws_app_views.dart`），不在这里。
abstract class MnWsAppClient {
  /// 路由标识（对应目录里的 `app`）。
  final String app;

  /// **目标 PC** 的 bridgeId。
  ///
  /// 多台 PC 都跑这个应用时要指明打哪台（目录里能看到每台的 bridgeId）；
  /// null = 走路由表（撞名时后来者接管）。
  final String? pc;

  MnWsAppClient({required this.app, this.pc});

  /// 经桥发一个请求。
  Future<MnWsResponse> call(
    MnWsEndpoint endpoint, {
    required String method,
    required String path,
    Map<String, String> headers = const {},
    String? body,
  }) =>
      endpoint.request(
        method: method,
        path: path,
        app: app,
        pc: pc,
        headers: headers,
        body: body,
      );
}
