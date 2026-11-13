import 'dart:convert';

import '../mnws_app_client.dart';
import '../mnws_models.dart';
import '../mnws_endpoint.dart';
import 'nxnx_models.dart';

/// nx-nx（项目生成器）的**全套**接口客户端。
///
/// ## 分层
///
/// 这不是一个「只够演示」的客户端 —— nx-nx 的 21 条 HTTP 路由全覆盖，
/// 按它自己的模块分：system / template / skill / script。
/// 面板上的每个按钮都对应这里的一个方法，于是**每个按钮都有等价的 CLI 命令**。
///
/// ## 调用语义（与 nx-nx 自己的 typed-client 一致）
///
///   · **路径参数**（`/api/templates/:id` 里的 `:id`）→ 替换进路径并 URL 编码
///   · **其余参数** → GET 走 query string，POST/PUT/DELETE 走 JSON body
///
/// 这么做是因为 nx-nx 的 action 是「路径参数 + 开放 flag」混着的：
/// `template.preview` 的 body 里既有 `dir`（flag），也有模板选项
/// （`name`/`letters`/…）。扁平传参，模板加一个选项时页面不用改。
class NxNxApi extends MnWsAppClient {
  NxNxApi({super.pc}) : super(app: 'nx-nx');

  // ───────────────────────── system ─────────────────────────

  /// `GET /api/bootstrap` —— 一次取齐面板启动所需的全部上下文。
  Future<NxNxBootstrap> bootstrap(MnWsEndpoint endpoint) async =>
      NxNxBootstrap.fromJson(await _get(endpoint, '/api/bootstrap'));

  /// `GET /api/routes` —— CLI 命令与 HTTP 路由的对照表。
  Future<List<NxNxRoute>> routes(MnWsEndpoint endpoint) async {
    final json = await _get(endpoint, '/api/routes');
    final raw = json['routes'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(NxNxRoute.fromJson).toList();
  }

  /// `GET /api/health` —— 自检：模板目录是否可读、有几个模板。
  Future<NxNxHealth> health(MnWsEndpoint endpoint) async =>
      NxNxHealth.fromJson(await _get(endpoint, '/api/health'));

  /// `GET /api/store` —— 存储路径。
  Future<NxNxStore> store(MnWsEndpoint endpoint) async =>
      NxNxStore.fromJson(await _get(endpoint, '/api/store'));

  /// `POST /api/open` —— 用默认浏览器打开本机服务。
  ///
  /// ⚠️ 这一条会**在目标机器上拉起浏览器** —— 经桥之后，它开的是那台电脑的
  /// 浏览器，不是手机的。所以界面上不给按钮，只留接口。
  Future<void> open(MnWsEndpoint endpoint, {String target = ''}) async {
    await _send(endpoint, 'POST', '/api/open', {'target': target});
  }

  // ───────────────────────── template ─────────────────────────

  /// `GET /api/templates` —— 列出所有可用模板。
  Future<List<NxNxTemplate>> templates(MnWsEndpoint endpoint) async {
    final json = await _get(endpoint, '/api/templates');
    final raw = json['templates'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(NxNxTemplate.fromJson).toList();
  }

  /// `GET /api/templates/:id` —— 某个模板的说明与可选项。
  Future<NxNxTemplateDetail> describe(MnWsEndpoint endpoint, String id) async =>
      NxNxTemplateDetail.fromJson(
        await _get(endpoint, '/api/templates/${Uri.encodeComponent(id)}'),
      );

  /// `POST /api/templates/:id/preview` —— 预览将生成的文件清单（不写盘）。
  ///
  /// [values] 是**模板选项**（`name`/`letters`/…），扁平传 —— 与 nx-nx 的
  /// action 语义一致：模板加一个选项，页面不用改。
  Future<NxNxPreview> preview(
    MnWsEndpoint endpoint,
    String id, {
    required Map<String, dynamic> values,
    String? dir,
  }) async {
    final body = <String, dynamic>{...values};
    if (dir != null && dir.isNotEmpty) body['dir'] = dir;
    return NxNxPreview.fromJson(
      await _send(endpoint, 'POST', '/api/templates/${Uri.encodeComponent(id)}/preview', body),
    );
  }

  /// `POST /api/templates/:id/create` —— 按模板生成项目。
  Future<NxNxCreateResult> create(
    MnWsEndpoint endpoint,
    String id, {
    required Map<String, dynamic> values,
    String? dir,
  }) async {
    final body = <String, dynamic>{...values};
    if (dir != null && dir.isNotEmpty) body['dir'] = dir;
    return NxNxCreateResult.fromJson(
      await _send(endpoint, 'POST', '/api/templates/${Uri.encodeComponent(id)}/create', body),
    );
  }

  /// `GET /api/ports` —— 探测可用的本机端口（供 serve / vite 使用）。
  Future<List<int>> ports(MnWsEndpoint endpoint, {int? start, int? count}) async {
    final json = await _get(endpoint, '/api/ports', {
      if (start != null) 'start': start,
      if (count != null) 'count': count,
    });
    final raw = json['ports'];
    if (raw is! List) return const [];
    return raw
        .map((e) => e is num ? e.toInt() : (int.tryParse('$e') ?? 0))
        .where((e) => e > 0)
        .toList();
  }

  /// `POST /api/check-dir` —— 检查目标目录能不能用（存在且非空则不可用）。
  Future<NxNxDirCheck> checkDir(MnWsEndpoint endpoint, String dir) async =>
      NxNxDirCheck.fromJson(await _send(endpoint, 'POST', '/api/check-dir', {'dir': dir}));

  // ───────────────────────── skill ─────────────────────────

  /// `GET /api/skills` —— 列出可装的 skill 与 group。
  Future<NxNxSkillList> skills(MnWsEndpoint endpoint) async =>
      NxNxSkillList.fromJson(await _get(endpoint, '/api/skills'));

  /// `GET /api/skill-groups` —— 每个 group 含哪些 skill。
  Future<NxNxSkillGroups> skillGroups(MnWsEndpoint endpoint) async =>
      NxNxSkillGroups.fromJson(await _get(endpoint, '/api/skill-groups'));

  /// `GET /api/skill-content` —— 导出 skill 文档（并幂等安装）。
  Future<NxNxSkillContent> skillContent(MnWsEndpoint endpoint, {String? name}) async =>
      NxNxSkillContent.fromJson(
        await _get(endpoint, '/api/skill-content', {if (name != null) 'name': name}),
      );

  /// `POST /api/skill-install` —— 安装 skill、整组 skill 或全部 skill。
  Future<void> installSkill(
    MnWsEndpoint endpoint, {
    String? name,
    String? group,
    bool? all,
  }) async {
    await _send(endpoint, 'POST', '/api/skill-install', {
      if (name != null) 'name': name,
      if (group != null) 'group': group,
      if (all != null) 'all': all,
    });
  }

  // ───────────────────────── script ─────────────────────────

  /// `GET /api/scripts` —— 列出随包分发的脚本与用法。
  Future<List<NxNxScript>> scripts(MnWsEndpoint endpoint) async {
    final json = await _get(endpoint, '/api/scripts');
    final raw = json['scripts'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(NxNxScript.fromJson).toList();
  }

  /// `GET /api/script-aliases` —— 脚本里可直接调用的内置全局函数（别名模块）。
  Future<List<NxNxAlias>> scriptAliases(MnWsEndpoint endpoint) async {
    final json = await _get(endpoint, '/api/script-aliases');
    final raw = json['aliases'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(NxNxAlias.fromJson).toList();
  }

  /// `GET /api/scripts/:name/content` —— 读取脚本源码。
  Future<String> scriptContent(MnWsEndpoint endpoint, String name) async {
    final json = await _get(
      endpoint,
      '/api/scripts/${Uri.encodeComponent(name)}/content',
    );
    return '${json['content'] ?? ''}';
  }

  /// `PUT /api/scripts/:name/content` —— 保存脚本源码（先写临时文件再改名）。
  Future<void> saveScript(MnWsEndpoint endpoint, String name, String content) async {
    await _send(
      endpoint,
      'PUT',
      '/api/scripts/${Uri.encodeComponent(name)}/content',
      {'content': content},
    );
  }

  /// `POST /api/scripts` —— 新建脚本并登记到 manifest。
  Future<String> createScript(MnWsEndpoint endpoint, String name, String content) async {
    final json = await _send(endpoint, 'POST', '/api/scripts', {
      'name': name,
      'content': content,
    });
    return '${json['name'] ?? name}';
  }

  /// `DELETE /api/scripts/:name` —— 删除脚本并从 manifest 移除。
  Future<void> deleteScript(MnWsEndpoint endpoint, String name) async {
    await _send(endpoint, 'DELETE', '/api/scripts/${Uri.encodeComponent(name)}', const {});
  }

  /// `POST /api/script-run` —— 运行内置脚本或任意 .mjs 脚本。
  Future<NxNxRunResult> runScript(
    MnWsEndpoint endpoint,
    String name, {
    List<String> args = const [],
  }) async {
    return NxNxRunResult.fromJson(
      await _send(endpoint, 'POST', '/api/script-run', {
        'name': name,
        'args': args,
      }),
    );
  }

  // ───────────────────────── 传输 ─────────────────────────

  /// GET + query。
  Future<Map<String, dynamic>> _get(
    MnWsEndpoint endpoint,
    String path, [
    Map<String, dynamic> query = const {},
  ]) async {
    var full = path;
    if (query.isNotEmpty) {
      final q = Uri(queryParameters: query.map((k, v) => MapEntry(k, '$v')));
      full = '$path?${q.query}';
    }
    return _unwrap(await call(endpoint, method: 'GET', path: full));
  }

  /// 非 GET：body 走 JSON。
  Future<Map<String, dynamic>> _send(
    MnWsEndpoint endpoint,
    String method,
    String path,
    Map<String, dynamic> body,
  ) async {
    return _unwrap(
      await call(
        endpoint,
        method: method,
        path: path,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
  }

  /// 剥掉 nx-nx 的 `{ok, data}` 信封。
  ///
  /// 信封统一是一层（所有路由都是），但万一某个接口回的是裸对象，也照样能用 ——
  /// 不因为「形状不对」就把整页打不开。
  static Map<String, dynamic> _unwrap(MnWsResponse res) {
    final j = res.json;
    if (j is! Map<String, dynamic>) return const {};
    if (res.status >= 400) {
      final msg = '${j['message'] ?? j['error'] ?? 'HTTP ${res.status}'}';
      throw MnWsException(MnWsErrorKind.rejected, 'nx-nx 调用失败：$msg');
    }
    final d = j['data'];
    if (d is Map<String, dynamic>) return d;
    return j;
  }
}
