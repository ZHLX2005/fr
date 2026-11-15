import 'dart:convert';
import 'dart:typed_data';

import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../mnws_app_client.dart';
import '../mnws_endpoint.dart';
import '../mnws_models.dart';
import 'nxkv_boards.dart';

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

  // ───────────────────────── 契约外的两件事 ─────────────────────────
  //
  // 契约只声明「端侧要调的 action」，不是服务端能力的全集。侧边栏的**组名**
  // 与附件**本体**都不在那 10 条里 —— 这两件是手机端独有的需求（PC 上组名由
  // 面板自己接口给，附件本体就在本机盘上）。所以这里各留一个刻意的手写读，
  // 路径固定、解析失败就退化，绝不把「装饰」做成「前置」：
  //
  //   1. GET /api/boards       → 组名 + 成员仓库（树的第一层）
  //   2. GET /api/file/content/:fileId → 附件字节（图片要在手机屏幕上画出来）
  //
  // nx-kv 哪天把 board.list / file.content 写进契约，这两个方法整个可以删掉。

  /// 项目组（看板）清单。读不到就返回空列表 —— 界面退化成「全在未分组下」。
  Future<List<NxKvBoard>> boards(MnWsEndpoint endpoint) async {
    final res = await call(endpoint, method: 'GET', path: '/api/boards');
    final json = res.json;
    if (json == null) return const [];
    return NxKvBoard.parse(json);
  }

  /// 附件本体（原始字节）。
  ///
  /// 失败时抛 [MnWsException]：这条链路没有「部分成功」，画不出图就是画不出。
  Future<Uint8List> attachmentBytes(MnWsEndpoint endpoint, String fileId) async {
    final id = fileId.trim();
    if (id.isEmpty) {
      throw const MnWsException(MnWsErrorKind.malformed, '附件没有 id，取不到本体');
    }
    final res = await endpoint.requestBytes(
      path: '/api/file/content/$id',
      app: app,
      pc: pc,
    );
    if (!res.ok) {
      throw MnWsException(
        res.status == 404 ? MnWsErrorKind.rejected : MnWsErrorKind.malformed,
        '附件取不回来（HTTP ${res.status}）${res.errorText.isEmpty ? '' : '：${res.errorText}'}',
        status: res.status,
      );
    }
    return res.bytes;
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
