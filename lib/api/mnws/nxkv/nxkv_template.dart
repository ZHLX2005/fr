/// 任务模板 —— 「新建任务」时正文该长什么样，**真相在服务端**。
///
/// ## 为什么有这个文件（fr #23）
///
/// 反馈原话：「fr侧任务模板不对，应该和web对齐」。分叉的根因很具体：
/// 端侧硬编码的 `## 背景 / ## 验收 / ## 约束` 正是**面板的兜底骨架**
/// （`md-parse.js` 的 `NEW_TEMPLATE`）——面板只在 `/api/templates` 拉不到时用它，
/// 正常路径取的是 `defaultId` 指向的模板（#137 之后出厂即「ref 生成」的
/// 零知识 SOP 正文）。于是同一次「新建任务」，PC 上是 SOP、手机上是空骨架。
///
/// 三件事决定它必须收在模型层而不是界面：
///
///   1. **取哪一条** —— `defaultId` 指的那条；指到不存在的 id 就整体回落兜底；
///   2. **怎么渲染** —— `{{槽位名}}` → 槽位值，没值留空（面板 `renderTemplateBody`
///      同一条语义；把裸 `{{背景}}` 塞进任务正文是明令禁止的）；
///   3. **兜底是谁** —— 与面板**逐字同构**的 `NEW_TEMPLATE`，不是我们自己再编一套。
///
/// 这样「对齐」是结构性的：用户在面板「提示词 / 模板」里改了默认模板，手机端下次
/// 新建就是改后的正文；断网时才退回兜底，而兜底也和面板断网时一模一样。
library;

import 'dart:convert';

/// 兜底正文：与面板 `web/frontend/modules/md/md-parse.js` 的 `NEW_TEMPLATE` 逐字一致。
///
/// **不要在这里「优化」措辞** —— 它存在的意义就是「面板拉不到模板时给人看的东西」，
/// 改动它等于重新制造两端分叉。
const String nxKvNewTaskFallbackBody = '## 背景\n'
    '\n'
    '（一句话说清要改什么）\n'
    '\n'
    '## 验收\n'
    '- [ ] …\n'
    '\n'
    '## 约束\n'
    '- …\n'
    '\n'
    '## 附件\n';

/// 槽位默认值：与面板 `NEW_TEMPLATE_VALUES` 同构。
///
/// 只在模板正文里出现 `{{背景}}` 这类**老标记**时才用得上（#137 之前的库）；
/// 老模板渲染出来是骨架而不是一堆大括号 —— 面板对这条的行为完全一样。
const Map<String, String> nxKvTemplateDefaultValues = {
  '背景': '（一句话说清要改什么）',
  '验收': '…',
  '约束': '…',
  '附件': '',
};

/// 单条模板。
class NxKvTaskTemplate {
  const NxKvTaskTemplate({
    required this.id,
    required this.name,
    required this.body,
    this.values = const {},
  });

  final String id;
  final String name;

  /// 未渲染的正文（可能含 `{{槽位}}`）。
  final String body;

  /// 该模板自己的槽位值（服务端 `values`）。
  final Map<String, String> values;

  static NxKvTaskTemplate? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    return NxKvTaskTemplate(
      id: id,
      name: '${raw['name'] ?? ''}',
      body: '${raw['body'] ?? ''}',
      values: _stringMap(raw['values']),
    );
  }
}

/// 一次 `GET /api/templates` 的结果：默认模板 id + 可用模板清单。
class NxKvTemplateSet {
  const NxKvTemplateSet({required this.defaultId, required this.items});

  final String defaultId;
  final List<NxKvTaskTemplate> items;

  /// `defaultId` 指向的那条；指到不存在（被删/换库）或没带 id 时给 null。
  NxKvTaskTemplate? get active {
    if (defaultId.isEmpty) return null;
    for (final t in items) {
      if (t.id == defaultId) return t;
    }
    return null;
  }

  /// 兼容三种信封：`{ok,data:{defaultId,templates}}`、`{defaultId,templates}`、裸清单。
  /// 认不出来给 null（调用方退回兜底正文），不抛 —— 拉模板失败不该挡住派活。
  static NxKvTemplateSet? tryParse(Object? payload) {
    final json = payload is Map && payload['data'] is Map ? payload['data'] as Map : payload;
    if (json is! Map) return null;
    final raw = json['templates'];
    if (raw is! List) return null;
    final items = <NxKvTaskTemplate>[];
    for (final e in raw) {
      final t = NxKvTaskTemplate.tryParse(e);
      if (t != null) items.add(t);
    }
    return NxKvTemplateSet(defaultId: '${json['defaultId'] ?? ''}', items: items);
  }
}

/// `{{槽位名}}` → 槽位值；没值留空。与面板 `renderTemplateBody` 同一条正则语义：
/// 名字去掉首尾空白后查表，查不到给空串（**绝不把标记原样留在正文里**）。
String renderNxKvTemplate(String body, Map<String, String> values) {
  if (body.isEmpty) return body;
  return body.replaceAllMapped(
    RegExp(r'\{\{\s*([^}{\s][^{}]*?)\s*\}\}'),
    (m) => values[m.group(1)!.trim()] ?? '',
  );
}

/// 新建任务的起始正文。
///
/// [set] 为空 = 没取到模板（断网 / 旧服务端 / 解析失败）→ 面板同款兜底骨架。
/// 取到了但 `defaultId` 指向的条目不存在，也走兜底（面板 `defaultBody` 同样如此）。
String nxKvNewTaskBody(NxKvTemplateSet? set) {
  final t = set?.active;
  if (t == null || t.body.trim().isEmpty) return nxKvNewTaskFallbackBody;
  // 缺的键用内置默认值补；用户显式留空（''）仍是空 —— 与面板合并顺序一致
  return renderNxKvTemplate(t.body, {...nxKvTemplateDefaultValues, ...t.values});
}

Map<String, String> _stringMap(Object? raw) {
  if (raw is Map) {
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (v == null) return;
      out['$k'] = '$v';
    });
    return out;
  }
  // 服务端理论上给对象；真给了 JSON 串（老库）也认一下
  if (raw is String && raw.trim().startsWith('{')) {
    try {
      final v = jsonDecode(raw);
      if (v is Map) return _stringMap(v);
    } catch (_) {
      return const {};
    }
  }
  return const {};
}
