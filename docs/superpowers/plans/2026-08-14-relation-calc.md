# fr 通用关系计算器（relation-calc）Implementation Plan

> **For agentic workers:** 按本计划逐 Task 实现。Steps 使用 checkbox（`- [ ]`）语法跟踪。

**Goal:** 新增 Lab demo `relation-calc` —— 通用关系计算器（变量系统模型：`A 的 B = C`，链式无限嵌套），内置亲戚关系预设，支持实体/关系词/规则完整 CRUD，SharedPreferences 简单存储，zen 主题 + 边框强调。

**Architecture:** 引擎（lab/demos/relation_calc/ 下，方案 A，通用不感知领域）+ 预设（内置亲戚数据）+ UI（demo 计算界面 + CRUD 管理界面 + 预设入口）。引擎用图结构（Entity 节点、Term 有向边标签、Rule 边），`resolve(startId, termIds)` 逐步查边，单步无解即失败可回退。**不建 core 模块（用户拍板：方案 A，全部落在 `lib/lab/demos/relation_calc/`）。**

**Tech Stack:** Flutter (Dart), SharedPreferences（JSON 整库序列化）, zen 主题组件库（ZenColors/ZenText/zenCard/zenButton/ZenSection/ZenIconButton/zenPageScaffold）。

## Global Constraints

- 完成后 `flutter analyze` 必须 **0 新增 issue**（基线：当前 master 干净）。
- analyze 干净后立即 `git add/commit/push`（flutter-work-flow 规范：只 add 自己变更的文件，禁止 `add .`；提交前 `git status` 逐条确认）。
- **test/ 被 .gitignore**：新增测试文件一律 `git add -f test/...`。
- 完成后 `kvcli todo done 20 --result "..."` 回填。
- 引擎必须通用：**不写死亲戚逻辑**，亲戚只是 `kinship_preset.dart` 里的数据。
- 常量收口 `const_relation_calc.dart`（demo 层）与 core 内 const（引擎层）。
- 不新增 package；不用 Hive；UI 只用 zen 组件库 + Material 基础组件。
- demo 主文件 <400 行，UI 拆分到子文件（方案 a）。
- Flutter 命令在仓库根 `D:\code\a_dart\prj\fr` 执行。

---

# Part 1 — 通用引擎 `lib/lab/demos/relation_calc/`（方案 A，不建 core）

## Task 1.1: 数据模型 `relation_calc_models.dart`

**Files:**
- Create: `lib/lab/demos/relation_calc/relation_calc_models.dart`

- [ ] **Step 1: 定义三个模型 + 手写 toMap/fromMap**

```dart
/// 实体（图的节点）：如「我」「爸爸」「爷爷」「组长」。
class RelationEntity {
  final String id;        // 稳定 id（如 'e_me' / 时间戳）
  String name;            // 显示名（可改）
  String note;            // 可选描述
  RelationEntity({required this.id, required this.name, this.note = ''});
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'note': note};
  static RelationEntity fromMap(Map m) => RelationEntity(
    id: (m['id'] ?? '') as String,
    name: (m['name'] ?? '') as String,
    note: (m['note'] ?? '') as String,
  );
}

/// 关系词（有向边标签）：如「爸爸」「妈妈」「上级」。
class RelationTerm {
  final String id;
  String name;
  RelationTerm({required this.id, required this.name});
  Map<String, dynamic> toMap() => {'id': id, 'name': name};
  static RelationTerm fromMap(Map m) => RelationTerm(
    id: (m['id'] ?? '') as String,
    name: (m['name'] ?? '') as String,
  );
}

/// 规则（有向边）：EntityA 的 Term = EntityB。
class RelationRule {
  final String id;
  String fromId;   // 起点实体 id
  String termId;   // 关系词 id
  String toId;     // 终点实体 id
  RelationRule({required this.id, required this.fromId, required this.termId, required this.toId});
  Map<String, dynamic> toMap() => {'id': id, 'from': fromId, 'term': termId, 'to': toId};
  static RelationRule fromMap(Map m) => RelationRule(
    id: (m['id'] ?? '') as String,
    fromId: (m['from'] ?? '') as String,
    termId: (m['term'] ?? '') as String,
    toId: (m['to'] ?? '') as String,
  );
}
```

- [ ] **Step 2: 定义整库快照 `RelationGraphData`（一次序列化给 store）**

```dart
/// 整库快照：entities + terms + rules。SharedPreferences 一次 JSON 读写。
class RelationGraphData {
  final List<RelationEntity> entities;
  final List<RelationTerm> terms;
  final List<RelationRule> rules;
  const RelationGraphData({this.entities = const [], this.terms = const [], this.rules = const []});
  Map<String, dynamic> toMap() => {
    'entities': entities.map((e) => e.toMap()).toList(),
    'terms': terms.map((e) => e.toMap()).toList(),
    'rules': rules.map((e) => e.toMap()).toList(),
  };
  static RelationGraphData fromMap(Map m) => RelationGraphData(
    entities: (m['entities'] as List? ?? []).whereType<Map>().map(RelationEntity.fromMap).toList(),
    terms: (m['terms'] as List? ?? []).whereType<Map>().map(RelationTerm.fromMap).toList(),
    rules: (m['rules'] as List? ?? []).whereType<Map>().map(RelationRule.fromMap).toList(),
  );
}
```

## Task 1.2: 计算引擎 `relation_engine.dart`

**Files:**
- Create: `lib/lab/demos/relation_calc/relation_engine.dart`

- [ ] **Step 1: 图结构 + 单步查找**

```dart
/// 通用关系计算引擎 —— 不感知领域，任何「X 的 Y = Z」都能算。
class RelationEngine {
  final List<RelationEntity> entities;
  final List<RelationTerm> terms;
  final List<RelationRule> rules;

  RelationEngine({required this.entities, required this.terms, required this.rules});

  Map<String, List<RelationEntity>> get entityById => {for (final e in entities) e.id: e};
  Map<String, List<RelationTerm>> get termById => {for (final t in terms) t.id: t};

  /// 单步：fromId 的 termId → 目标实体；无规则返回 null。
  RelationEntity? step(String fromId, String termId) {
    for (final r in rules) {
      if (r.fromId == fromId && r.termId == termId) {
        return entityById[r.toId];
      }
    }
    return null;
  }
}
```

- [ ] **Step 2: 链式计算 resolve（返回逐步结果，失败点可回溯）**

```dart
/// 链式计算结果：steps 是每步命中的 (起点, 关系词, 终点)；
/// success=false 时 failedIndex 指向失败步骤，steps 只含成功的前缀。
class RelationCalcResult {
  final List<RelationStep> steps;
  final bool success;
  final int? failedIndex;
  const RelationCalcResult({required this.steps, required this.success, this.failedIndex});
  RelationEntity? get finalEntity => steps.isEmpty ? null : steps.last.to;
}

class RelationStep {
  final RelationEntity from;
  final RelationTerm term;
  final RelationEntity to;
  const RelationStep({required this.from, required this.term, required this.to});
}

RelationCalcResult resolveChain(
  RelationEngine engine,
  String startId,
  List<String> termIds,
) {
  final steps = <RelationStep>[];
  var current = engine.entityById[startId];
  if (current == null) {
    return RelationCalcResult(steps: steps, success: false, failedIndex: 0);
  }
  for (var i = 0; i < termIds.length; i++) {
    final to = engine.step(current.id, termIds[i]);
    if (to == null) {
      return RelationCalcResult(steps: steps, success: false, failedIndex: i);
    }
    steps.add(RelationStep(from: current, term: engine.termById[termIds[i]]!, to: to));
    current = to;
  }
  return RelationCalcResult(steps: steps, success: true);
}
```

> 注：`resolveChain` 写成顶层纯函数（engine 传入），便于单测；引擎也可挂在 store 之上。

## Task 1.3: 持久化 store `relation_calc_store.dart`

**Files:**
- Create: `lib/lab/demos/relation_calc/relation_calc_store.dart`

- [ ] **Step 1: SharedPreferences 整库 JSON 读写 + CRUD 语义方法**

```dart
/// 关系库持久化 —— SharedPreferences 简单存储（不用 Hive）。
/// 整库快照 JSON 一次读写（数据量小：几十个实体/关系词/规则）。
class RelationCalcStore {
  RelationCalcStore._();
  static final RelationCalcStore instance = RelationCalcStore._();

  static const String _key = 'relation_calc.graph.v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// 读整库；无数据返回空快照。
  Future<RelationGraphData> load() async {
    final p = await _prefs;
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return const RelationGraphData();
    try {
      return RelationGraphData.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const RelationGraphData();
    }
  }

  /// 写整库。
  Future<void> save(RelationGraphData data) async {
    final p = await _prefs;
    await p.setString(_key, jsonEncode(data.toMap()));
  }

  /// 清除（重置回预设时先调）。
  Future<void> clear() async {
    final p = await _prefs;
    await p.remove(_key);
  }
}
```

- [ ] **Step 2: CRUD 语义方法（新增/更新/删除 entity/term/rule）**

```dart
// load-modify-save 模式：
// upsertEntity / deleteEntity / upsertTerm / deleteTerm / upsertRule / deleteRule
// 实现要点：
//  - upsert: 同 id 覆盖，否则追加
//  - delete entity: 同时删除引用它的规则（from/to 都删），避免悬空边
//  - delete term: 同时删除引用它的规则
//  - id 生成：'e_<micros>' / 't_<micros>' / 'r_<micros>'
```

## Task 1.4: 亲戚关系预设 `kinship_preset.dart`

**Files:**
- Create: `lib/lab/demos/relation_calc/kinship_preset.dart`

- [ ] **Step 1: 实体表（约 50-80 个称谓）**

覆盖（用户拍板：常用直系 + 主要旁系）：
- 自我：我
- 直系长辈：爸爸、妈妈、爷爷（祖父）、奶奶（祖母）、外公（外祖父）、外婆（外祖母）、太爷爷（曾祖父）、太奶奶（曾祖母）、太外公、太外婆
- 直系平辈：哥哥、弟弟、姐姐、妹妹
- 直系晚辈：儿子、女儿、孙子、孙女、外孙、外孙女
- 旁系长辈：伯父、伯母、叔叔、婶婶、姑妈、姑父、舅舅、舅妈、姨妈、姨父
- 旁系平辈：堂哥、堂弟、堂姐、堂妹、表哥、表弟、表姐、表妹
- 旁系晚辈：侄子、侄女、外甥、外甥女
- 姻亲：丈夫、妻子、公公、婆婆、岳父、岳母、儿媳、女婿、嫂子、弟媳、姐夫、妹夫
- 其他：曾孙、曾孙女、重孙、重孙女（可选）

每个实体：`RelationEntity(id: 'e_xxx', name: '爷爷', note: '父亲的父亲')`。

- [ ] **Step 2: 关系词表（作为边的标签）**

```dart
// 爸爸、妈妈、哥哥、弟弟、姐姐、妹妹、儿子、女儿、丈夫、妻子、
// 爷爷、奶奶、外公、外婆、伯父、叔叔、姑妈、舅舅、姨妈（必要时）
// 说明：中文里关系词与称谓同形，作为「边的标签」复用；用户可自定义新词。
```

- [ ] **Step 3: 规则表（A 的 B = C）**

核心规则（抽样验证目标）：
```dart
// 从「我」出发：
//   我 + 爸爸 = 爸爸；我 + 妈妈 = 妈妈
//   我 + 哥哥 = 哥哥；我 + 弟弟 = 弟弟；我 + 姐姐 = 姐姐；我 + 妹妹 = 妹妹
//   我 + 儿子 = 儿子；我 + 女儿 = 女儿
// 父亲链：
//   爸爸 + 爸爸 = 爷爷；爸爸 + 妈妈 = 奶奶
//   爸爸 + 哥哥 = 伯父；爸爸 + 弟弟 = 叔叔；爸爸 + 姐姐 = 姑妈；爸爸 + 妹妹 = 姑妈
//   爷爷 + 爸爸 = 太爷爷；爷爷 + 妈妈 = 太奶奶
// 母亲链：
//   妈妈 + 爸爸 = 外公；妈妈 + 妈妈 = 外婆
//   妈妈 + 哥哥 = 舅舅；妈妈 + 弟弟 = 舅舅；妈妈 + 姐姐 = 姨妈；妈妈 + 妹妹 = 姨妈
//   外公 + 爸爸 = 太外公；外婆 + 妈妈 = 太外婆
// 平辈互链（以「哥哥」为例，兄弟姊妹同理）：
//   哥哥 + 爸爸 = 爸爸；哥哥 + 妈妈 = 妈妈
//   哥哥 + 儿子 = 侄子；哥哥 + 女儿 = 侄女
//   姐姐 + 儿子 = 外甥；姐姐 + 女儿 = 外甥女
// 晚辈链：
//   儿子 + 儿子 = 孙子；儿子 + 女儿 = 孙女
//   女儿 + 儿子 = 外孙；女儿 + 女儿 = 外孙女
//   孙子 + 儿子 = 曾孙；孙女 + 女儿 = 曾孙女
// 姻亲（从「我」出发为主）：
//   我 + 丈夫 = 丈夫；我 + 妻子 = 妻子
//   丈夫 + 爸爸 = 公公；丈夫 + 妈妈 = 婆婆
//   妻子 + 爸爸 = 岳父；妻子 + 妈妈 = 岳母
//   哥哥 + 妻子 = 嫂子；弟弟 + 妻子 = 弟媳；姐姐 + 丈夫 = 姐夫；妹妹 + 丈夫 = 妹夫
//   儿子 + 妻子 = 儿媳；女儿 + 丈夫 = 女婿
// 堂表亲（以「堂哥」为例）：
//   伯父 + 儿子 = 堂哥；伯父 + 女儿 = 堂姐
//   叔叔 + 儿子 = 堂弟；叔叔 + 女儿 = 堂妹
//   姑妈 + 儿子 = 表哥；姑妈 + 女儿 = 表姐
//   舅舅 + 儿子 = 表哥；舅舅 + 女儿 = 表姐
//   姨妈 + 儿子 = 表弟；姨妈 + 女儿 = 表妹
```

- [ ] **Step 4: 导出预设函数**

```dart
/// 内置亲戚关系预设。
RelationGraphData kinshipPresetData() => RelationGraphData(
  entities: [...],
  terms: [...],
  rules: [...],
);
```

## Task 1.5: 模块入口（方案 A 下省略独立 export 文件，各文件相对 import）

**Files:** 无（方案 A：demo 文件直接相对 import 引擎/模型/预设/存储）

---

# Part 2 — Demo UI `lib/lab/demos/relation_calc/`

## Task 2.1: 常量 `const_relation_calc.dart`

**Files:**
- Create: `lib/lab/demos/relation_calc/const_relation_calc.dart`

```dart
/// relation-calc demo 常量 —— 全部经 RelationCalcConsts.* 暴露。
class RelationCalcConsts {
  RelationCalcConsts._();
  static const String demoTitle = '关系计算器';
  static const String demoSlug = 'relation-calc';
  static const String demoDescription = '通用关系链式计算：A 的 B = C，无限嵌套，内置亲戚称呼预设';
  static const String defaultStartEntityName = '我';
}
```

## Task 2.2: demo 注册 + 主页面 `relation_calc_demo.dart`

**Files:**
- Create: `lib/lab/demos/relation_calc/relation_calc_demo.dart`

- [ ] **Step 1: DemoPage 子类**

```dart
class RelationCalcDemo extends DemoPage {
  @override
  String get title => RelationCalcConsts.demoTitle;
  @override
  String get slug => RelationCalcConsts.demoSlug;
  @override
  String get description => RelationCalcConsts.demoDescription;
  @override
  Widget buildPage(BuildContext context) => const RelationCalcPage();
}

void registerRelationCalcDemo() {
  demoRegistry.register(RelationCalcDemo());
}
```

- [ ] **Step 2: 主页面 `RelationCalcPage`（StatefulWidget）**

结构（<400 行，复杂 UI 拆子文件）：
- `initState` → `_load()`：`RelationCalcStore.instance.load()`；若 entities 为空则 `save(kinshipPresetData())` 自动导入预设；`_engine = RelationEngine(...)`
- 起点选择：默认「我」（`defaultStartEntityName` 匹配或第一个实体），可切换（底部 sheet 列出实体）
- 关系链 state：`List<String> _termIds`（已按下的关系词 id 序列）；`_resolve()` 实时计算
- 布局（zen 主题 + 边框强调）：
  - 顶部：起点实体 chip + 关系链横向展示（`我 → 爸爸 → 爸爸`）
  - 中央：`ZenSection` 大卡片，当前结果大字（`ZenText.monoDigitLarge` 或 title 大字号），失败时显示「无法计算」+ 失败步提示
  - 中部：关系词按钮盘（Wrap 自动平衡，`zenButton` 描边强调），点击追加一步
  - 底部操作：撤销（`ZenIconButton` outline，删最后一步）/ 清空（重置为起点）
  - AppBar actions：管理入口（Tab 切换）→ `manage_view.dart`；预设入口 → 预设说明 + 重置（`ZenConfirmDialog` 确认）
- 自适应：`LayoutBuilder` + `SingleChildScrollView` + Wrap（百分比/自动编排，无溢出）

## Task 2.3: CRUD 管理界面 `manage_view.dart`

**Files:**
- Create: `lib/lab/demos/relation_calc/manage_view.dart`

- [ ] **Step 1: 三个 Tab（实体 / 关系词 / 规则）**

- Tab 实体：列表（`zenCard` 卡片 + 名称/描述 + 编辑/删除滑出或按钮）；FAB/按钮「+ 新增」（底部 sheet：名称 + 描述输入，`zenButton` 确认）
- Tab 关系词：列表 + 新增/编辑（名称输入）
- Tab 规则：列表（`哥哥 的 儿子 = 侄子` 渲染：from.name + term.name + to.name）；新增 = 三个下拉选择（实体 A / 关系词 / 实体 C）+ 确认
- 删除实体/关系词时联动删除引用规则（store 已封装）；删除用 `ZenConfirmDialog`
- 每次变更后 `save` + 刷新列表 + 通知主页面重建引擎（通过回调或 `ValueNotifier` 刷新）

## Task 2.4: 注册到 lab_bootstrap.dart

**Files:**
- Modify: `lib/lab/lab_bootstrap.dart`

- [ ] **Step 1: import + 注册**

```dart
import 'demos/relation_calc/relation_calc_demo.dart' show registerRelationCalcDemo;
// registerAllDemos() 内加：
registerRelationCalcDemo();
```

---

# Part 3 — 测试

## Task 3.1: 引擎单测 `test/core/relation_calc/relation_engine_test.dart`

**Files:**
- Create: `test/core/relation_calc/relation_engine_test.dart`（`git add -f`）

- [ ] **Step 1: 覆盖**

- 链式：`[爸爸, 爸爸]` → 爷爷；`[妈妈, 妈妈]` → 外婆；`[爸爸, 哥哥]` → 伯父
- 无限嵌套：`[爸爸, 爸爸, 爸爸]` → 太爷爷
- 单步无解：`[爸爸, 姨夫]`（未定义）→ success=false, failedIndex 指向失败步
- 起点不存在 → success=false
- 空链（termIds=[]）→ success=true, final=起点
- 自定义领域：构造公司团队数据（组长 的 上级 = 经理；经理 的 上级 = 总监）→ 链式传递验证

---

# Part 4 — 收尾

## Task 4.1: flutter analyze

- [ ] 在仓库根执行 `flutter analyze`，确认 0 新增 issue

## Task 4.2: commit + push

- [ ] `git status` 逐条确认改动归属（只含本次任务文件）
- [ ] `git add` 具体文件（含 `git add -f test/...`），commit message 遵循项目风格（如 `feat(lab): 通用关系计算器 demo + 亲戚预设`）
- [ ] `git push` 触发 GitHub APK 流水线

## Task 4.3: kvcli 回填

- [ ] `kvcli todo done 20 --result "..."`（写明做了什么 + 怎么验证）

---

# 验收核对表

- [ ] Lab 出现「关系计算器」demo，可进入
- [ ] 默认导入亲戚预设；`我 → 爸爸 → 爸爸 = 爷爷`；`妈妈 → 哥哥 = 舅舅` 等抽样正确
- [ ] 自定义规则（公司团队：组长→上级→经理）链式可算
- [ ] CRUD 增删改查可用；重启数据不丢；重置回预设可用
- [ ] 撤销/清空可用；无解步骤提示可回溯
- [ ] zen 主题 + 边框强调；窄屏无溢出
- [ ] `flutter analyze` 0 新增 issue
- [ ] 已 push，`kvcli todo done 20` 已回填
