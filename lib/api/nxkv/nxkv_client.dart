import 'dart:convert';

import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../mnws/mnws_app_client.dart';
import '../mnws/mnws_endpoint.dart';
import '../mnws/mnws_models.dart';

/// nx-kv 的端侧客户端 —— 接口**不是手写的**，是服务端契约生成出来的。
///
/// 生成物（`package:nx_kv_client`，来自 nx-kv 仓库的 `contract/dart`）只有三样：
/// 强类型模型、`NxKvClientApi` 的一票方法、一个 `NxKvTransport` 函数签名。
/// 它不知道 nx-kv 挂在哪、也不该知道 —— 「怎么发一次请求」留给这里：
/// 应用标识、设备令牌、桥的基址全在 [MnWsEndpoint] 里。
///
/// 于是「加一条接口」在 fr 侧是**零改动**：nx-kv 那边 `@action` 补上 `output`，
/// 重新生成、bump `pubspec.yaml` 里的 ref，这边 `flutter pub get` 完就能调用。
///
/// 唯一的裂缝：pubspec 锁的是 sha，nx-kv 加字段时端侧不会自己知道。
/// 兜底是 [contractDrift] —— 拿服务端 `GET /api/contract` 的指纹跟生成物里的
/// `contractHash` 比，对不上就在界面上说「端侧跑在旧契约上」。
class NxKvApi extends MnWsAppClient {
  NxKvApi({super.pc}) : super(app: 'nx-kv');

  /// 生成物里的契约指纹（编译期就定死了）。
  String get contractHash => kv.contractHash;

  /// 生成物对应的服务端版本。
  String get contractVersion => kv.contractVersion;

  /// 绑定一台 PC 之后的**契约客户端**。
  ///
  /// 每次调用新建一个（代价只是一个闭包）：端点可以换（多台 PC 跑同一个应用），
  /// 客户端不该把端点存成字段 —— 那正是「打了 A 机却显示 B 机数据」的来源。
  kv.NxKvClientApi bind(MnWsEndpoint endpoint) => kv.NxKvClientApi(
        (method, path, query, body) => _send(endpoint, method, path, query, body),
      );

  /// 契约对账：null = 端侧与服务端一致；否则一句人话。
  ///
  /// 只在「打开 nx-kv 页面」这种低频时机调，不放进请求链路 ——
  /// 它是**诊断**，不是前置条件（拉不到契约也不该让整页打不开）。
  Future<String?> contractDrift(MnWsEndpoint endpoint) async {
    final remote = await bind(endpoint).systemContract();
    if (remote.hash == kv.contractHash) return null;
    return '端侧契约 ${kv.contractHash} 与服务端 ${remote.hash} 不一致'
        '（nx-kv ${remote.version}）：bump fr pubspec.yaml 里 nx_kv_client 的 ref';
  }

  // ───────────────────────── 传输 ─────────────────────────

  /// [kv.NxKvTransport] 的实现：四样东西 → 一次经桥的请求。
  ///
  /// **不在这里拆信封**：`{ok, data}` 的拆解由生成物统一做（唯一一份），
  /// 这里只负责把「回的不是 JSON」变成说得清的错误 —— 桥在应用掉线时回的是
  /// 一段 HTML/纯文本，直接丢给生成物只会得到「data 不是对象」这种废话。
  Future<dynamic> _send(
    MnWsEndpoint endpoint,
    String method,
    String path,
    Map<String, String> query,
    Object? body,
  ) async {
    final full = query.isEmpty ? path : '$path?${Uri(queryParameters: query).query}';
    final res = await call(
      endpoint,
      method: method,
      path: full,
      headers: body == null ? const {} : const {'Content-Type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    );
    final json = res.json;
    if (json == null) {
      throw MnWsException(
        MnWsErrorKind.malformed,
        'nx-kv $method $path 返回的不是 JSON（HTTP ${res.status}）',
        status: res.status,
      );
    }
    return json;
  }
}
