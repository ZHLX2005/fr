import 'dart:convert';

import '../mnws_app_client.dart';
import '../mnws_models.dart';
import '../mnws_service.dart';
import 'nxnx_models.dart';

/// nx-nx（项目生成器）的接口客户端。
///
/// 它**不知道**自己被桥着 —— 所有请求都经 [MnWsAppClient.call] 走 mn-ws，
/// 于是业务令牌、目标 PC、应用标识这三样由基类统一带上。
///
/// 「我为什么只代理它的 API、自己在 App 里画界面」：为了**原生 UI 的性能**。
/// 桥把数据搬过来，界面是 App 自己的 Widget —— 不必在手机上再开一个
/// WebView 去渲染它自己的前端。
class NxNxApi extends MnWsAppClient {
  NxNxApi({super.pc}) : super(app: 'nx-nx');

  /// 列出所有可用模板。
  ///
  /// 最简单的一个接口 —— 正好用来验证「多 PC + 分组 + 经桥取数据」这条链。
  Future<NxNxTemplateList> templates(MnWsService service) async {
    final res = await call(service, method: 'GET', path: '/api/templates');
    return NxNxTemplateList.fromJson(_jsonOf(res));
  }

  /// 某个模板的说明与可选项。
  Future<Map<String, dynamic>> describe(MnWsService service, String id) async {
    final res = await call(
      service,
      method: 'GET',
      path: '/api/templates/$id',
    );
    return _jsonOf(res);
  }

  /// 预览「按这个模板会生成哪些文件」（不写盘）。
  Future<Map<String, dynamic>> preview(
    MnWsService service,
    String id, {
    Map<String, dynamic> vars = const {},
  }) async {
    final res = await call(
      service,
      method: 'POST',
      path: '/api/templates/$id/preview',
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'vars': vars}),
    );
    return _jsonOf(res);
  }

  /// 自检（模板目录可读、有几个模板）。
  Future<Map<String, dynamic>> health(MnWsService service) async {
    final res = await call(service, method: 'GET', path: '/api/health');
    return _jsonOf(res);
  }

  /// 响应体按 JSON 解，并**剥掉 goframe 的信封**（`{ok, data}` → `data`）。
  ///
  /// 剥不剥得看对面：有的后端回裸对象，有的套一层信封。这里两种都吃 ——
  /// 有 `data` 就解一层，没有就当它本来就是平的。解不了就原样塞进一张
  /// 单键表（不猜结构）。
  static Map<String, dynamic> _jsonOf(MnWsResponse res) {
    final j = res.json;
    if (j is! Map<String, dynamic>) return {'raw': res.body};
    final d = j['data'];
    if (d is Map<String, dynamic>) return d;
    return j;
  }
}
