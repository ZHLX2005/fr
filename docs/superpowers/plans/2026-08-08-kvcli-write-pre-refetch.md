# kvcli 清单写操作 refetch 防御多端快照覆盖

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 KV 清单在"两端长时间打开页面 + 互相操作"场景下持续相互覆盖、丢对方操作的 UX bug。在每个写操作(add / markDone / edit / delete / clone / clearDoneToCold / addTopic / deleteTopic / clearAll)执行前先重新拉一次 server 最新 KV,把本地陈旧快照替换为最新值,本次操作在最新基础上叠加再写回。**接受毫秒级竞态放弃**(用户明确)。

**Architecture:** 在 `_KvcliTodoDemoPageState` 中新增 `bool _refreshing` flag + `Future<void> _refreshLatest({bool silent = true}) async` 私有方法(refetch open/done/topics 三把 key,把 `_open / _done / _topics` 替换为 server 最新)。把 9 个写入口改成"先 `_refreshing = true → await _refreshLatest(silent: true) → _refreshing = false` 再走原写逻辑"。**冲突合并策略 = 本地优先丢弃**(refetch 后本地直接被 server 覆盖,本次操作在 server 最新基础上叠加)。

**Tech Stack:** Flutter / Riverpod / `lib/lab/demos/kvcli_todo/`(已有 `active_group_provider.dart` / `kvcli_todo_widgets.dart` / `kvcli_todo_dialogs.dart` / `kvcli_todo_models.dart` / `const_kvcli_todo.dart`)。

## Global Constraints

- **不运行 `flutter run`**。最低成本编译检查 = `flutter analyze` 全量(必须无新增 error)。
- 改完文件若没被 import,靠 analyze 孤儿文件检测兜底。
- commit message 风格沿用仓库:`fix(scope): 中文说明`。
- 提交前先 `git status` 确认归属,只 `git add` 本任务改动的文件,**禁止 `add .` / `commit .`**。
- 不动 `_loadAll` 全量加载流程;不动 `_openWorkspaceSheet`;不动 body UI。
- 不引入新文件 / 新依赖。
- 不补 widget 测试(本次为状态机级改动,仓库无 RecorderController/Kvcli_todo 现成测试脚手架)。
- refetch 必须用 `_gid` 三元注入(与 `_readTasks`/`_readTopics` 同源)。
- refetch 期间 UI 不阻塞,只通过 `_refreshing` flag 让按钮 disabled 显示 loading 态(后续再视觉化,本次只保证状态正确)。

---

## Task 1: 加 _refreshLatest + 9 个写入口前 refetch

**Files:**
- Modify: `lib/lab/demos/kvcli_todo_demo.dart`
  - 加字段 `bool _refreshing = false;`(在 `bool _loading = true;` 附近,约 :99)
  - 加方法 `Future<void> _refreshLatest()`(在 `_loadAll()` 后面,约 :187)
  - 9 个写入口开头加 refetch + `_refreshing` 状态切换:`_add`、`_markDone`、`_editTask`、`_deleteTask`、`_cloneTask`、`_clearDoneToCold`、`_addTopic`、`_deleteTopic`、`_clearAll`

**Interfaces:**
- 复用既有:`Future<List<KvTask>> _readTasks(String key)`、`Future<List<String>> _readTopics()`、`int? get _gid`、`bool _refreshing`(新增)。
- 新增:`Future<void> _refreshLatest()` —— 同步写本地三把 key;`setState(() => _refreshing = true/false)` 控制按钮 disabled。

- [ ] **Step 1: 新增 `_refreshing` 字段**

`lib/lab/demos/kvcli_todo_demo.dart` :99 后插入:

```dart
bool _refreshing = false; // 写操作前的 refetch 期间为 true(避免重复点击叠加)
```

- [ ] **Step 2: 新增 `_refreshLatest()` 方法**

`lib/lab/demos/kvcli_todo_demo.dart` 在 `_loadAll()`(:164-187)之后、`// ── 操作层 ──` 注释之前插入:

```dart
/// 写操作前的 refetch：把本地 _open / _done / _topics 替换为 server 最新值。
/// 本地优先丢弃策略：本次操作将在 server 最新基础上叠加后再写回。
/// 若 server 写失败则本地不动；调用方负责处理失败 toast。
Future<void> _refreshLatest() async {
  if (_refreshing) return;
  setState(() => _refreshing = true);
  try {
    final open = await _readTasks(KvCliTodoConst.keyOpen);
    final done = await _readTasks(KvCliTodoConst.keyDone);
    final topics = await _readTopics();
    if (!mounted) return;
    setState(() {
      _open = open;
      _done = done;
      _topics = topics;
    });
  } finally {
    if (mounted) setState(() => _refreshing = false);
  }
}
```

- [ ] **Step 3: 9 个写入口前加 refetch + `_refreshing` 校验**

**统一前缀**(每个写入口的最开头加):

```dart
if (_refreshing || _loading) {
  _toast('正在同步最新数据，请稍候');
  return;
}
await _refreshLatest();
```

按顺序应用到下列方法(每个方法只插入上述两段,不动其它逻辑):

| 方法 | 文件位置 | 调整 |
| --- | --- | --- |
| `_add` | :191 | 插入前缀 |
| `_markDone` | :229 | 插入前缀 |
| `_editTask` | :253 | 插入前缀 |
| `_deleteTask` | :274 | 插入前缀 |
| `_cloneTask` | :295 | 插入前缀 |
| `_clearDoneToCold` | :319 | 插入前缀 |
| `_addTopic` | :340 | 插入前缀 |
| `_deleteTopic` | :362 | 插入前缀 |
| `_clearAll` | :375 | 插入前缀(末尾 `return` 前也提前) |

> 注意:`_addTopic` / `_deleteTopic` 返回 `Future<bool>`,前缀里的 `return;` 要改成 `return false;`;`_clearAll` 是 `Future<void>`,用 `return;`。

- [ ] **Step 4: `flutter analyze` 校验**

```bash
flutter analyze lib/lab/demos/kvcli_todo_demo.dart
```

Expected: `No issues found!`(无新增 error/warning)

- [ ] **Step 5: 代码层验证**

- `_refreshLatest` 是幂等的:并发调用时第一个进入后置位 `_refreshing = true`,第二个 if 守门 return;`finally` 保证恢复。
- 9 个写入口 refetch 后,后续 `_saveTasks(...)` 用的 `next / open / done / nextTopics` 都基于 server 最新值,不会再覆盖对方刚加的。
- refetch 期间按钮 disabled:`AppBar.actions` 已经有 `_loading ? null : _loadAll` 同款 disabled 模式;本次只把 9 个写入口的入口守门加上,后续视觉化(`_refreshing` 接按钮 onPressed 守门)留后续任务。
- `_loadAll`(全量加载)不动;首屏进入仍走 initState 的 `_loadAll`。
- `_openWorkspaceSheet → _setActiveGroup → _loadAll` 仍走全量刷新(workspace 切换的语义是"换组",不是常规写操作,不该被 refetch 介入)。

- [ ] **Step 6: Commit + Push**

```bash
git add lib/lab/demos/kvcli_todo_demo.dart
git status   # 确认只有本任务文件被 add
git commit -m "fix(lab/kvcli-todo): 写操作前 refetch 最新 KV 防御多端快照覆盖

- 新增 _refreshing flag + _refreshLatest() 把 _open/_done/_topics 替换为 server 最新
- 9 个写入口(add/markDone/edit/delete/clone/clearDoneToCold/addTopic/deleteTopic/clearAll)前 refetch
- 本地优先丢弃:refetch 后本次操作在 server 最新基础上叠加再写回
- _refreshing 期间写入口幂等守门,并发不会触发第二次 refetch
- 接受毫秒级竞态(用户明确放弃)
- 不动 _loadAll 全量加载、不动 _openWorkspaceSheet
- analyze 干净"
git push
```

---

## 自检(写入前)

1. **Spec 覆盖**:"在添加之前调用 get,避免快照覆盖过长"——本计划覆盖所有 9 个写入口的 refetch ✅;本地优先丢弃策略 ✅;loading 状态(本轮仅保证 state,视觉留后续)✅
2. **占位符**:无 TBD / TODO / 适当处理字样。
3. **类型一致性**:`_refreshing` 是 `bool`;`_refreshLatest()` 是 `Future<void>`;调用点用 `await _refreshLatest();` 与所有 9 个写入口签名匹配。

## 已知非目标

- 不引入 CAS / 乐观锁 / 版本号 —— 用户接受毫秒级竞态放弃。
- 不补 widget 测试 —— 仓库无此页现成脚手架。
- 不做按钮级 loading 视觉化 —— 仅保证 state,后续单独任务。
- 不改 `_openWorkspaceSheet` 走的 `_loadAll` 全量路径 —— workspace 切换语义不同。
- 不动后端 GoFrame KV 接口 —— 客户端防御。