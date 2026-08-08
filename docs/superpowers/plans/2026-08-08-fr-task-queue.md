# fr 2026-08-08 任务队列（6 条）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 解决 fr 主题 6 条待办：kvcli 清单交互（快捷 topic 误删/自动收集/克隆归档）、课表起始日期弹窗、clock 历史显示与 track stop 白屏。

**Architecture:** 4 簇独立子系统、无相互依赖。kvcli 部分集中在 `lib/lab/demos/kvcli_todo_demo.dart` + `lib/lab/demos/kvcli_todo/`（widgets/dialogs/models/const 已拆分）。课表在 `lib/core/timetable/service/config/`。clock 在 `lib/lab/demos/clock/`。每簇一个任务组，各自独立编译验证 + 提交推送。

**Tech Stack:** Flutter / Riverpod / provider / Hive(课表) / SharedPreferences(clock) / GoFrame KV 后端(kvcli)。

## Global Constraints

- **不运行 `flutter run`**。最低成本编译检查 = 根目录 `flutter analyze`（必须无 error）；`flutter build web --release` 可做追加验证。
- **每完成一个任务 = 一次 commit + 推送**（GitHub Actions 流水线构建 APK，本地无 Java）。`git add` 只列本任务改动的文件，**禁止 `add .` / `commit .`**；提交前先 `git status` 确认归属。
- commit message 风格沿用仓库：`fix(scope): 中文说明` / `feat(scope): 中文说明`。
- lab demo 保持扁平；辅助文件放已建好的 `lib/lab/demos/kvcli_todo/`；常量进 `const_xxx.dart`。
- 不在 lab 里加多余返回按钮（外部 DemoPage 已包装）。
- 本仓库 `flutter analyze` 是全量分析；改完文件若没被 import，靠 analyze 的孤儿文件检测兜底。

---

## Task 1: (id=8) 快捷 topic 独立区块 + 管理弹层 + 删除确认

**Files:**
- Modify: `lib/lab/demos/kvcli_todo_demo.dart` — `_buildComposer` 移除 chip 行（约 :429-445）、body Column 插入 `_buildQuickTopicsSection`、`_addTopic`/`_deleteTopic` 改返回 `Future<bool>`、新增 `_openTopicManager`
- Modify: `lib/lab/demos/kvcli_todo/kvcli_todo_dialogs.dart` — 追加 `showKvTopicDeleteConfirm` + `showKvTopicManagerSheet`
- Modify: `lib/lab/demos/kvcli_todo/kvcli_todo_widgets.dart` — `KvTopicChip` 去掉 `onDelete`（只剩点击回填）；删除不再使用的 `KvAddTopicChip`

**Interfaces:**
- Produces: `Future<bool> _addTopic()`（true=已添加，false=重复/失败）、`Future<bool> _deleteTopic(String topic)`、`Future<void> _openTopicManager()`；dialogs 新增 `Future<bool> showKvTopicDeleteConfirm(BuildContext, String)`、`Future<void> showKvTopicManagerSheet(BuildContext, {required List<String> topics, required Future<bool> Function() onAdd, required Future<bool> Function(String) onDelete})`

- [ ] **Step 1: widgets 文件——`KvTopicChip` 去 `onDelete`、删 `KvAddTopicChip`**

`lib/lab/demos/kvcli_todo/kvcli_todo_widgets.dart`：

把 `KvTopicChip`（:54-113）改成只点击回填：
```dart
/// 快捷 topic chip：点击回填主题框。删除集中在管理弹层，chip 不带 ✕。
class KvTopicChip extends StatelessWidget {
  const KvTopicChip({
    super.key,
    required this.label,
    this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.35), width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: accent,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
```
删除整个 `KvAddTopicChip` 类（:115-154，不再使用）。

- [ ] **Step 2: dialogs 文件——追加删除确认 + 管理弹层**

`lib/lab/demos/kvcli_todo/kvcli_todo_dialogs.dart` 末尾追加：
```dart
/// 确认删除快捷 topic，返回是否确认。
Future<bool> showKvTopicDeleteConfirm(BuildContext context, String topic) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除快捷 topic？'),
      content: Text(topic, maxLines: 2, overflow: TextOverflow.ellipsis),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: EmphasisButton.dangerEmphasis(context),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 快捷 topic 管理弹层：顶部「+ 新增」，列表每行一个删除（44px 热区 + 确认）。
Future<void> showKvTopicManagerSheet(
  BuildContext context, {
  required List<String> topics,
  required Future<bool> Function() onAdd,
  required Future<bool> Function(String) onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _KvTopicManagerSheet(
      topics: topics,
      onAdd: onAdd,
      onDelete: onDelete,
    ),
  );
}

class _KvTopicManagerSheet extends StatefulWidget {
  const _KvTopicManagerSheet({
    required this.topics,
    required this.onAdd,
    required this.onDelete,
  });

  final List<String> topics;
  final Future<bool> Function() onAdd;
  final Future<bool> Function(String) onDelete;

  @override
  State<_KvTopicManagerSheet> createState() => _KvTopicManagerSheetState();
}

class _KvTopicManagerSheetState extends State<_KvTopicManagerSheet> {
  late final List<String> _topics = List.of(widget.topics);

  Future<void> _add() async {
    final name = await showKvAddTopicDialog(context);
    if (name == null || name.isEmpty) return;
    final ok = await widget.onAdd();
    if (!ok || !mounted) return;
    setState(() => _topics.add(name));
  }

  Future<void> _delete(String topic) async {
    final ok = await showKvTopicDeleteConfirm(context, topic);
    if (!ok) return;
    final applied = await widget.onDelete(topic);
    if (!applied || !mounted) return;
    setState(() => _topics.remove(topic));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('快捷 topic',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新增'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _topics.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '暂无快捷 topic',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.outline),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final t in _topics)
                          ListTile(
                            dense: true,
                            leading: Icon(Icons.tag, size: 18,
                                color: scheme.primary),
                            title: Text(t),
                            trailing: IconButton(
                              tooltip: '删除',
                              icon: Icon(Icons.delete_outline,
                                  color: scheme.error),
                              constraints: const BoxConstraints(
                                  minWidth: 44, minHeight: 44),
                              onPressed: () => _delete(t),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: demo 页——移除 composer 里的 chip 行**

`lib/lab/demos/kvcli_todo_demo.dart` `_buildComposer`：删除 `Align(alignment: Alignment.centerLeft, child: Wrap(...for (final t in _topics) KvTopicChip(...) ... KvAddTopicChip(onTap: _addTopic)))` 整块（原 :430-445，含前后 `const SizedBox`）。

- [ ] **Step 4: demo 页——新增快捷 topic 区块 + 管理入口**

`lib/lab/demos/kvcli_todo_demo.dart` 新增两个方法，并在 `build` 的 body Column 插入区块：
```dart
// 独立快捷 topic 区块：标题 + ⚙ 管理；chip 横向滚动、点击回填
Widget _buildQuickTopicsSection(ColorScheme scheme) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '快捷 topic',
              style: TextStyle(
                fontSize: 12,
                color: scheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: '管理',
              icon: const Icon(Icons.settings_outlined, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: _openTopicManager,
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_topics.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '暂无快捷 topic，提交任务时自动收集',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in _topics)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: KvTopicChip(
                      label: t,
                      onTap: () => _applyTopicChip(t),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

Future<void> _openTopicManager() async {
  await showKvTopicManagerSheet(
    context,
    topics: _topics,
    onAdd: _addTopic,
    onDelete: _deleteTopic,
  );
}
```
body Column 改为：
```dart
body: _loading
    ? const Center(child: CircularProgressIndicator())
    : Column(
        children: [
          _buildComposer(scheme),
          const Divider(height: 1),
          _buildQuickTopicsSection(scheme),
          const Divider(height: 1),
          Expanded(child: _buildList()),
        ],
      ),
```

- [ ] **Step 5: demo 页——`_addTopic` / `_deleteTopic` 改返回 `Future<bool>`**

`lib/lab/demos/kvcli_todo_demo.dart`：
```dart
Future<bool> _addTopic() async {
  final name = await showKvAddTopicDialog(
    context,
    initial: _topicCtrl.text.trim(),
  );
  if (name == null || name.isEmpty) return false;
  if (_topics.contains(name)) {
    _toast('快捷 topic「$name」已存在');
    return false;
  }
  final next = [..._topics, name];
  try {
    await _saveTopics(next);
  } catch (e) {
    _toast('添加失败：${_errMsg(e)}');
    return false;
  }
  if (!mounted) return false;
  setState(() => _topics = next);
  return true;
}

Future<bool> _deleteTopic(String topic) async {
  final next = _topics.where((t) => t != topic).toList();
  try {
    await _saveTopics(next);
  } catch (e) {
    _toast('删除失败：${_errMsg(e)}');
    return false;
  }
  if (!mounted) return false;
  setState(() => _topics = next);
  return true;
}
```

- [ ] **Step 6: 编译检查**

Run: `flutter analyze`
Expected: 无 error（本任务改动文件：`kvcli_todo_demo.dart`、`kvcli_todo_dialogs.dart`、`kvcli_todo_widgets.dart`）。若 widget 文件里出现 `KvAddTopicChip`/`onDelete` 残留引用 → 一并清掉。

- [ ] **Step 7: 提交 + 推送**

```bash
git status
git add lib/lab/demos/kvcli_todo_demo.dart lib/lab/demos/kvcli_todo/kvcli_todo_dialogs.dart lib/lab/demos/kvcli_todo/kvcli_todo_widgets.dart
git commit -m "fix(lab/kvcli-todo): 快捷 topic 独立区块 + 管理弹层删除确认"
git push
```

> 手动 E2E：进 KV 清单 → 快捷区 chip 点击回填主题、不再有 ✕ → ⚙ 管理弹层里删除有确认、取消不删、确认删且持久化。

---

## Task 2: (id=10) 提交任务自动收集快捷 topic

**Files:**
- Modify: `lib/lab/demos/kvcli_todo_demo.dart` — `_add()`

**Interfaces:**
- Consumes: Task 1 的 `_saveTopics(List<String>)`、`_topics`、`_toast(String)`

- [ ] **Step 1: `_add()` 提交成功后把新 topic 写进 `todo:topics`**

`lib/lab/demos/kvcli_todo_demo.dart` `_add()` 整体替换（主题若不在快捷列表则一并持久化，两把 key 一起写，失败整单放弃）：
```dart
Future<void> _add() async {
  final topic = _topicCtrl.text.trim();
  final text = _textCtrl.text.trim();
  if (topic.isEmpty || text.isEmpty) {
    _toast('主题与任务文本均必填');
    return;
  }

  var maxId = 0;
  for (final t in _open) {
    if (t.id > maxId) maxId = t.id;
  }
  final task = KvTask(
    id: maxId + 1,
    topic: topic,
    text: text,
    createdAt: DateTime.now().toIso8601String(),
  );
  final next = [..._open, task];
  final addTopic = !_topics.contains(topic);
  final nextTopics = addTopic ? [..._topics, topic] : _topics;
  try {
    await _saveTasks(KvCliTodoConst.keyOpen, next);
    if (addTopic) await _saveTopics(nextTopics);
  } catch (e) {
    _toast('提交失败：${_errMsg(e)}');
    return;
  }
  if (!mounted) return;
  setState(() {
    _open = next;
    if (addTopic) _topics = nextTopics;
  });
  _textCtrl.clear();
  _textFocus.requestFocus();
}
```

- [ ] **Step 2: 编译检查**

Run: `flutter analyze`
Expected: 无 error。

- [ ] **Step 3: 提交 + 推送**

```bash
git status
git add lib/lab/demos/kvcli_todo_demo.dart
git commit -m "feat(lab/kvcli-todo): 提交任务自动收集快捷 topic"
git push
```

> 手动 E2E：手输一个不在快捷列表的新主题 + 任务 → 提交 → 快捷区出现该主题 chip；重复提交同主题不重复。

---

## Task 3: (id=15) 已完成克隆回待办 + 清理到冷数据

**Files:**
- Modify: `lib/lab/demos/kvcli_todo/const_kvcli_todo.dart` — 冷数据 key 常量 + 日期分片 helper
- Modify: `lib/lab/demos/kvcli_todo_demo.dart` — `_cloneTask`、`_clearDoneToCold`、`_buildList` 加已完成区头、`KvTaskCard` 传 `onClone`
- Modify: `lib/lab/demos/kvcli_todo/kvcli_todo_widgets.dart` — `KvTaskCard` 加 `onClone` 参数 + 克隆图标
- Modify: `lib/lab/demos/kvcli_todo/kvcli_todo_dialogs.dart` — 追加 `showKvClearDoneConfirm`

**Interfaces:**
- Produces: `static String KvCliTodoConst.coldKeyFor(DateTime)`（形如 `todo:done:cold:2026-08-08`）；`Future<void> _cloneTask(KvTask)`；`Future<void> _clearDoneToCold()`；`Future<bool> showKvClearDoneConfirm(BuildContext, int count)`
- Consumes: 已有 `_readTasks(String)`、`_writeKey(String,String)`、`_saveTasks`、`widget.kv.delete`、`EmphasisButton`

- [ ] **Step 1: 冷数据 key 常量**

`lib/lab/demos/kvcli_todo/const_kvcli_todo.dart` 追加：
```dart
/// 冷数据 key 前缀（已完成清理归档；app 只写不查）
static const String keyDoneColdPrefix = 'todo:done:cold:';

/// 按日期分片的冷数据 key，避免同前缀被覆盖。
static String coldKeyFor(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '$keyDoneColdPrefix${d.year}-${two(d.month)}-${two(d.day)}';
}
```

- [ ] **Step 2: 克隆 + 清理方法**

`lib/lab/demos/kvcli_todo_demo.dart` 追加：
```dart
Future<void> _cloneTask(KvTask task) async {
  var maxId = 0;
  for (final t in _open) {
    if (t.id > maxId) maxId = t.id;
  }
  final cloned = KvTask(
    id: maxId + 1,
    topic: task.topic,
    text: task.text,
    createdAt: DateTime.now().toIso8601String(),
  );
  final next = [..._open, cloned];
  try {
    await _saveTasks(KvCliTodoConst.keyOpen, next);
  } catch (e) {
    _toast('克隆失败：${_errMsg(e)}');
    return;
  }
  if (!mounted) return;
  setState(() => _open = next);
  _toast('已克隆回待办：#${cloned.id}');
}

Future<void> _clearDoneToCold() async {
  final ok = await showKvClearDoneConfirm(context, _done.length);
  if (!ok) return;
  final coldKey = KvCliTodoConst.coldKeyFor(DateTime.now());
  try {
    // 同一天多次清理 → 合并到同一冷数据 key
    final existing = await _readTasks(coldKey);
    final merged = [...existing, ..._done];
    await _writeKey(coldKey, jsonEncode(merged.map((t) => t.toJson()).toList()));
    await widget.kv.delete(KvCliTodoConst.keyDone);
  } catch (e) {
    _toast('清理失败：${_errMsg(e)}');
    return;
  }
  if (!mounted) return;
  setState(() => _done = const []);
}
```

- [ ] **Step 3: 已完成区头 + 克隆按钮接线**

`lib/lab/demos/kvcli_todo_demo.dart` `_buildList()` 改为：列表非空时，已完成 tab 顶部加一行「已完成 N 条 + 清理到冷数据」按钮：
```dart
Widget _buildList() {
  final list = _tab == 0 ? _open : _done;
  final isOpen = _tab == 0;
  if (list.isEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          isOpen ? '暂无待办任务' : '暂无已完成任务',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ),
    );
  }
  return Column(
    children: [
      if (!isOpen) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Text(
                '已完成 ${_done.length} 条',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _clearDoneToCold,
                style: EmphasisButton.dangerEmphasis(context),
                icon: const Icon(Icons.archive_outlined, size: 16),
                label: const Text('清理到冷数据'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final task = list[i];
            return KvTaskCard(
              task: task,
              isOpen: isOpen,
              onDone: isOpen ? () => _markDone(task) : null,
              onEdit: () => _editTask(task, isDone: !isOpen),
              onDelete: () => _deleteTask(task, isDone: !isOpen),
              onClone: isOpen ? null : () => _cloneTask(task),
            );
          },
        ),
      ),
    ],
  );
}
```

- [ ] **Step 4: `KvTaskCard` 加克隆按钮**

`lib/lab/demos/kvcli_todo/kvcli_todo_widgets.dart` `KvTaskCard`（:157）加字段：
```dart
this.onClone,
```
构造参数区 `final VoidCallback? onClone;`（:171 附近）。在操作 Row（编辑图标前，:252）插入：
```dart
_IconAction(
  icon: Icons.content_copy_outlined,
  tooltip: '克隆',
  onTap: onClone,
),
```

- [ ] **Step 5: 清理确认弹窗**

`lib/lab/demos/kvcli_todo/kvcli_todo_dialogs.dart` 末尾追加：
```dart
/// 确认把全部已完成归档到冷数据，返回是否确认。
Future<bool> showKvClearDoneConfirm(BuildContext context, int count) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('清理已完成？'),
      content: Text(
        '将 $count 条已完成任务归档到冷数据 key（按日期分片，app 不再查询），并清空已完成列表。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: EmphasisButton.dangerEmphasis(context),
          child: const Text('归档'),
        ),
      ],
    ),
  );
  return ok == true;
}
```

- [ ] **Step 6: 编译检查**

Run: `flutter analyze`
Expected: 无 error。

- [ ] **Step 7: 提交 + 推送**

```bash
git status
git add lib/lab/demos/kvcli_todo/const_kvcli_todo.dart lib/lab/demos/kvcli_todo_demo.dart lib/lab/demos/kvcli_todo/kvcli_todo_widgets.dart lib/lab/demos/kvcli_todo/kvcli_todo_dialogs.dart
git commit -m "feat(lab/kvcli-todo): 已完成克隆回待办 + 清理到冷数据(key带日期)"
git push
```

> 手动 E2E：完成 1 条任务 → 已完成 tab 点克隆 → 待办出现新任务（id 递增）；点「清理到冷数据」→ 确认 → 已完成清空；用 kvcli 拉 `todo:done:cold:2026-08-08` 应看到完整 JSON。

---

## Task 4: (id=9) 课表起始日期弹窗 Tab 切换 + 入口收敛

**Files:**
- Modify: `lib/core/timetable/service/config/timetable_week_calculator.dart` — TabController 监听、去自绘 barrier、修双层描边、标题
- Modify: `lib/core/timetable/service/config/timetable_settings_page.dart` — 「选日期」按钮去掉自动 `_save()`
- Test: `test/core/timetable/week_calculator_test.dart` — 追加 Tab 切换 widget 测试

**Interfaces:**
- Consumes: 现有 `findNearestMondayOnOrBefore`、`zenCard()`、`ZenColors`、`ZenText`

- [ ] **Step 1: 先写失败测试（TDD）**

`test/core/timetable/week_calculator_test.dart` 追加（若文件已存在 `main()`，把下面合并进现有 `main`；若不存在则新建，头部 import flutter/material + flutter_test + 目标文件）：
```dart
  testWidgets('WeekCalculatorDialog Tab 切换内容跟随', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: WeekCalculatorDialog())),
    );
    // 初始在「周数推算」Tab
    expect(find.text('输入当前是第几周，推算出起始日期（周一）'), findsOneWidget);
    // 切到「选日期」Tab，内容应立即切换
    await tester.tap(find.text('选日期'));
    await tester.pumpAndSettle();
    expect(find.text('选择任意一天，自动回退到当天或之前的最近周一。'),
        findsOneWidget);
  });
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/timetable/week_calculator_test.dart`
Expected: FAIL —— 「选择任意一天…」找不到（Tab 切换不重建内容）。

- [ ] **Step 3: TabController 加 listener**

`lib/core/timetable/service/config/timetable_week_calculator.dart` `initState`（:33）：
```dart
_tab = TabController(length: 2, vsync: this)
  ..addListener(() {
    if (mounted) setState(() {});
  });
```

- [ ] **Step 4: 去掉自绘 barrier + 修双层描边**

`timetable_week_calculator.dart` `build`（:79-94）：把最外层 `Stack` + `GestureDetector(Container(black26))` + `Center(Material(...))` 的包法，换成只保留 `Center` 内层，且外层 `Material` 透明化（barrier 交给 `showDialog`，描边/圆角交给 `zenCard()`）：
```dart
return Center(
  child: Material(
    elevation: 8,
    color: Colors.transparent,
    clipBehavior: Clip.antiAlias,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      width: 320,
      padding: const EdgeInsets.all(16),
      decoration: zenCard(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ... 原有 Header / TabBar / Tab1 / Tab2 / 结果 内容不变 ...
        ],
      ),
    ),
  ),
);
```
Header 标题（:105）`'起始日期'` → `'设置起始日期'`。

- [ ] **Step 5: 「选日期」按钮不再自动保存整页**

`lib/core/timetable/service/config/timetable_settings_page.dart`（:344-377）「选日期」按钮 onPressed 里，删掉 `_save();`（:360），只保留 `setState(() => _startDateController.text = iso);` —— 与点卡片走 `WeekCalculatorDialog` 的「只回填不保存」路径对齐，用户再点右上角 💾 保存，避免整页被 pop、未保存滑块改动被静默提交。

- [ ] **Step 6: 运行测试确认通过**

Run: `flutter test test/core/timetable/week_calculator_test.dart`
Expected: PASS（含原有 `findNearestMondayOnOrBefore` 用例）。

- [ ] **Step 7: 编译检查**

Run: `flutter analyze`
Expected: 无 error。

- [ ] **Step 8: 提交 + 推送**

```bash
git status
git add lib/core/timetable/service/config/timetable_week_calculator.dart lib/core/timetable/service/config/timetable_settings_page.dart test/core/timetable/week_calculator_test.dart
git commit -m "fix(timetable): 起始日期弹窗 Tab 切换失效 + 选日期不再整页保存退出"
git push
```

> 手动 E2E：设置页点日期卡片 → 弹窗内切「选日期」Tab 内容即变；点下方「选日期」按钮 → 只回填、页面不退出。

---

## Task 5: (id=11) 无 clock 时历史记录仍显示 + 删 clock 结算在飞记录

**Files:**
- Modify: `lib/lab/demos/clock/widgets/clocks_tab.dart` — 空状态改为 `SliverToBoxAdapter`，Records slivers 恒渲染
- Modify: `lib/lab/demos/clock/providers/lab_clock_provider.dart` — `getRecordLiveDuration` 兜底；`deleteClock` 先结算在飞记录

**Interfaces:**
- Consumes: `provider.clocks`、`provider.records`、`_EmptyState`、`getRecordLiveDuration(LabClockRecord)`、`LabClockRecord.copyWith(endTime/completed/accumulatedSeconds)`

- [ ] **Step 1: `clocks_tab` 去掉早退，空状态进 CustomScrollView**

`lib/lab/demos/clock/widgets/clocks_tab.dart` build（:67-113）：删掉 `if (provider.clocks.isEmpty) { return _EmptyState(...); }` 早退，改成始终 `CustomScrollView`，grid sliver 与空状态用 `if/else` 二选一：
```dart
return CustomScrollView(
  slivers: [
    if (provider.clocks.isEmpty)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: _EmptyState(onAdd: () => _openEditor(context)),
        ),
      )
    else
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.85,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _ClockCard(clock: provider.clocks[i]),
            childCount: provider.clocks.length,
          ),
        ),
      ),
    const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Text('Records', style: ZenText.label),
      ),
    ),
    if (provider.records.isEmpty)
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Text('No records yet.', style: ZenText.label),
        ),
      )
    else
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => _RecordTile(record: provider.records[i]),
          childCount: provider.records.length,
        ),
      ),
    const SliverToBoxAdapter(child: SizedBox(height: 96)),
  ],
);
```
（即原 grid 区块挪进 `else`，空状态改成 `SliverToBoxAdapter` 包 `_EmptyState`。）

- [ ] **Step 2: `getRecordLiveDuration` 兜底不再恒 0**

`lib/lab/demos/clock/providers/lab_clock_provider.dart`（:528-529）：
```dart
    // 时钟不存在且未完成：用已累计秒数兜底（不再恒 0）
    return record.accumulatedSeconds ?? 0;
```

- [ ] **Step 3: `deleteClock` 先结算名下在飞记录**

`lib/lab/demos/clock/providers/lab_clock_provider.dart`（:383-388）替换：
```dart
/// 删除时钟（先结算名下未完成的在飞记录，避免删 clock 丢时长）
Future<void> deleteClock(String id) async {
  final now = DateTime.now();
  var needSaveRecords = false;
  _records = _records.map((r) {
    if (r.clockId == id && !r.completed && r.endTime == null) {
      needSaveRecords = true;
      final live = getRecordLiveDuration(r); // 删前先算，此时 clock 还在
      return r.copyWith(
        endTime: now,
        completed: false,
        accumulatedSeconds: live,
      );
    }
    return r;
  }).toList();
  _clocks.removeWhere((c) => c.id == id);
  await _saveClocks();
  if (needSaveRecords) await _saveRecords();
  _syncToWidget(); // 同步到桌面小组件
  notifyListeners();
}
```

- [ ] **Step 4: 编译检查**

Run: `flutter analyze`
Expected: 无 error（确认 `_records` 声明为可赋值的 `List<LabClockRecord>`，是则 `.map().toList()` 合法）。

- [ ] **Step 5: 提交 + 推送**

```bash
git status
git add lib/lab/demos/clock/widgets/clocks_tab.dart lib/lab/demos/clock/providers/lab_clock_provider.dart
git commit -m "fix(clock): 无 clock 时历史记录仍显示 + 删 clock 结算在飞记录"
git push
```

> 手动 E2E：一个 clock 都没有时，Records 仍显示历史；删除运行中的 clock 后其历史记录时长不再是 0s。

---

## Task 6: (id=12) track stop 双重 pop 白屏 + totalRemaining 越界崩溃

**Files:**
- Modify: `lib/lab/demos/clock/widgets/track_runner_page.dart` — Stop 前熄灭自动 pop 源；ticker 自 pop 后 cancel
- Modify: `lib/lab/demos/clock/providers/lab_track_provider.dart` — `totalRemaining` 越界保护；`_completeTrack` 先置空再 await；`stopTrack` 结算实际消耗秒数

**Interfaces:**
- Consumes: `LabTrackProvider.stopTrack/startTrack/skipSegment`、`_ticker`、`_autoPopped`、`activeTrackId`

- [ ] **Step 1: ticker 自动 pop 后 cancel 自身**

`lib/lab/demos/clock/widgets/track_runner_page.dart`（:26-30）：
```dart
      if (p.activeTrackId == null && !_autoPopped) {
        _autoPopped = true;
        _ticker?.cancel();
        Future.microtask(() {
          if (mounted) Navigator.of(context).pop();
        });
      }
```

- [ ] **Step 2: Stop 按钮先熄灭自动 pop 源再 pop**

`lib/lab/demos/clock/widgets/track_runner_page.dart`（:122-130）：
```dart
                    _RunnerButton(
                      icon: Icons.stop_rounded,
                      label: 'Stop',
                      onTap: () async {
                        // 熄灭 ticker 的自动 pop，避免 300ms 退出动画期间二次 pop → 内层 Navigator 空 → 白屏
                        _ticker?.cancel();
                        _autoPopped = true;
                        final nav = Navigator.of(context);
                        await p.stopTrack();
                        if (mounted) nav.pop();
                      },
                    ),
```

- [ ] **Step 3: `totalRemaining` 加越界保护**

`lib/lab/demos/clock/providers/lab_track_provider.dart` `totalRemaining`（:49-60），`final t = activeTrack; if (t == null) return 0;` 之后插入：
```dart
    if (_currentSegmentIndex >= t.segments.length) return 0;
```

- [ ] **Step 4: `_completeTrack` 把置空挪到 await 之前**

`lib/lab/demos/clock/providers/lab_track_provider.dart`（:217-237）替换：
```dart
  Future<void> _completeTrack() async {
    BeatCoordinator.releaseOwnership('track:$_activeTrackId');
    final i = _tracks.indexWhere((t) => t.id == _activeTrackId);
    if (i == -1) return;
    final t = _tracks[i];
    final totalConsumed = t.segments.fold<int>(
        0, (s, seg) => s + seg.snapshotDurationSeconds);
    final recIdx = _records.indexWhere(
      (r) => r.trackId == _activeTrackId && r.endTime == null,
    );
    if (recIdx != -1) {
      _records[recIdx] = _records[recIdx].copyWith(
        endTime: DateTime.now(),
        completed: true,
        accumulatedSeconds: totalConsumed,
      );
    }
    // 先置空 + 停 timer，消除 await 间隙里 activeTrackId!=null 且 index 越界的不一致态
    _activeTrackId = null;
    _timer?.cancel();
    await _saveRecords();
    notifyListeners();
  }
```

- [ ] **Step 5: `stopTrack` 结算实际消耗秒数**

`lib/lab/demos/clock/providers/lab_track_provider.dart`（:250-267）替换：
```dart
  Future<void> stopTrack() async {
    _timer?.cancel();
    BeatCoordinator.releaseOwnership('track:$_activeTrackId');
    // Mark record as stopped (not completed) so the user can see partial progress.
    final recIdx = _records.indexWhere(
      (r) => r.trackId == _activeTrackId && r.endTime == null,
    );
    if (recIdx != -1) {
      final rec = _records[recIdx];
      // 结算实际已消耗秒数（不再写死 0）
      final consumed = rec.perSegmentSeconds
          .take(rec.segmentIndex + 1)
          .fold(0, (a, b) => a + b);
      _records[recIdx] = rec.copyWith(
        endTime: DateTime.now(),
        completed: false,
        accumulatedSeconds: consumed,
      );
      await _saveRecords();
    }
    _activeTrackId = null;
    notifyListeners();
  }
```

- [ ] **Step 6: 编译检查**

Run: `flutter analyze`
Expected: 无 error。

- [ ] **Step 7: 提交 + 推送**

```bash
git status
git add lib/lab/demos/clock/widgets/track_runner_page.dart lib/lab/demos/clock/providers/lab_track_provider.dart
git commit -m "fix(clock): track stop 双重 pop 白屏 + totalRemaining 越界崩溃"
git push
```

> 手动 E2E：建 track → 开始 → 点 Stop → 只 pop 一次正常回列表（不白屏）；自然跑完 / 连点 Skip 到末段 → 不白屏；停止的 record 时长 = 实际消耗。

---

## 已知搁置（本轮不做）

- `pauseTrack` 不置 `_activeTrackId` 且 `currentSegmentRemaining` 走墙钟推导 → 暂停后剩余时间仍走、UI 表达不了暂停态。属 id=12 之外的既有缺陷，本轮不修，避免扩大回归面。
- 后端 `todo:prompt:fr` 读取超时未取到，本计划按代码现状 + 用户口述对齐。

## 待办回填

每簇完成后 `kvcli todo done <id> --result "<完成结果摘要>"`（6 条：8 / 10 / 15 / 9 / 11 / 12），结果摘要把根因一句话 + 修复要点写进 note。
