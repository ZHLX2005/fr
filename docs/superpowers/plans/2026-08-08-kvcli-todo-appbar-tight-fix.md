# kvcli 清单 AppBar 窄屏"交错"修复实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Lab → KV 清单(AppBar 含工作空间选择器 + 刷新按钮)在窄屏(手机宽度)上出现的视觉交错(AppBar 标题 Row 被挤压穿过 bottom tab 区;点刷新时 `CircularProgressIndicator` 弧线穿过 AppBar bottom 区)。

**Architecture:** 把"工作空间选择 chip"从 AppBar `title` 内部 Row 迁移到 `actions` 区首位,AppBar `title` 仅保留"KV 清单"文字。`actions` 区是固定 48px 槽位,与 `bottom: PreferredSize(48)` tab 行天然分层,不再互相侵占。这样窄屏的渲染模型变成:`AppBar(title=短文, actions=[workspace, refresh, clear], bottom=tabs)` —— 每一行高度可控,不挤兑。

**Tech Stack:** Flutter / Riverpod / Material 3 / `lib/lab/demos/kvcli_todo/`(已建好的子目录)。

## Global Constraints

- **不运行 `flutter run`**。最低成本编译检查 = 根目录 `flutter analyze`（必须无 error）。
- 改完文件若没被 import,靠 analyze 孤儿文件检测兜底。
- lab demo 保持扁平;辅助文件放已建好的 `lib/lab/demos/kvcli_todo/`;常量进 `const_xxx.dart`。
- 不在 lab 里加多余返回按钮(外部 DemoPage 已包装)。
- commit message 风格沿用仓库:`fix(scope): 中文说明`。
- 提交前先 `git status` 确认归属,只 `git add` 本任务改动的文件,**禁止 `add .` / `commit .`**。
- 不破坏任何已存在的交互:
  - `_openWorkspaceSheet()` 必须仍可被点击触发,行为不变(走 `_setActiveGroup → _loadAll`)。
  - `_loadAll` / `_clearAll` 按钮仍在 actions 区。
  - body 的 `_buildComposer` / `_buildQuickTopicsSection` / `_buildList` 不动。
- AppBar `centerTitle` 默认 true 在 Material3 下居中;窄屏要维持"标题不挡按钮"。

---

## 任务数: 1 个

变更面非常小(单一文件 AppBar 几行),按"一个原子改动 + 一个验证提交"组织。

### Task 1: AppBar 工作空间 chip 迁移到 actions,刷新圈位置不再穿过 bottom 区

**Files:**
- Modify: `lib/lab/demos/kvcli_todo_demo.dart` — `Scaffold.appBar` 整段(:585-660)。把 `title:` 从 `Row(Text, InkWell chip)` 简化为只显示 `Text('KV 清单')`;`actions:` 列表首位插入一个"工作空间"按钮(IconButton + tooltip + 文字溢出压缩),沿用 `_openWorkspaceSheet`。
- 不动:`_openWorkspaceSheet`(:489-538)、`_groupLabel`(:481-487)、`build` 其它部分、body、widgets 文件。

**Interfaces:**
- 复用既有:`Future<void> _openWorkspaceSheet()`、`String _groupLabel(int gid)`、`int gid = ref.watch(activeGroupProvider)`。
- 不新增对外 API(纯 UI 改造)。

- [ ] **Step 1: 在 `_KvcliTodoDemoPageState` 中新增 `_buildWorkspaceAction(scheme, gid)` 私有 builder**

文件 `lib/lab/demos/kvcli_todo_demo.dart`,在 `_toast(String msg)` 之前(约 :573)插入:

```dart
/// AppBar actions 第 1 位：工作空间切换按钮。
/// 形态：IconButton + tooltip，避免 chip + 文字塞进窄屏 title 行导致挤压交错。
Widget _buildWorkspaceAction(ColorScheme scheme, int gid) {
  final name = _groupLabel(gid);
  return IconButton(
    tooltip: '工作空间：$name（点击切换）',
    onPressed: _loading ? null : _openWorkspaceSheet,
    icon: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.workspaces_outlined, size: 18, color: scheme.primary),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 72),
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: scheme.primary),
          ),
        ),
      ],
    ),
  );
}
```

> 设计要点:`actions` 区每项天然 48px 槽位,IconButton 自带 padding,Row 内文本 ConstrainedBox 限 72px + ellipsis。窄屏时省略组名,只留图标;宽屏显示完整组名。tooltip 给完整可访问性。

- [ ] **Step 2: 重写 `build()` 里的 `AppBar` 块**

把 `lib/lab/demos/kvcli_todo_demo.dart` 的 `Scaffold(...appBar: AppBar(...))`(约 :585-660)的 `title` 与 `actions` 替换为:

```dart
appBar: AppBar(
  title: const Text('KV 清单'),
  backgroundColor: scheme.inversePrimary,
  actions: [
    _buildWorkspaceAction(scheme, gid),
    IconButton(
      tooltip: '刷新',
      icon: const Icon(Icons.refresh),
      onPressed: _loading ? null : _loadAll,
    ),
    IconButton(
      tooltip: '清空两把 key',
      icon: const Icon(Icons.delete_outline),
      onPressed: _open.isEmpty && _done.isEmpty ? null : _clearAll,
    ),
  ],
  bottom: PreferredSize(
    preferredSize: const Size.fromHeight(48),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          KvTabChip(
            label: '待办 (${_open.length})',
            selected: _tab == 0,
            onTap: () => setState(() => _tab = 0),
          ),
          const SizedBox(width: 8),
          KvTabChip(
            label: '已完成 (${_done.length})',
            selected: _tab == 1,
            onTap: () => setState(() => _tab = 1),
          ),
        ],
      ),
    ),
  ),
),
```

> 关键差异:
> 1. `title:` 只剩 `Text('KV 清单')` —— 不再承载"工作空间 chip",不再有 Row 挤压;
> 2. `actions:` 首位是 `_buildWorkspaceAction(scheme, gid)` —— 工作空间入口挪到固定 48px 槽位;
> 3. `bottom: PreferredSize(48)` tab 行不动,与 actions 不再视觉重叠;
> 4. 保留 `centerTitle` 默认 true —— 标题居中,工作空间在右,两边互不侵占。

- [ ] **Step 3: 移除 `_openWorkspaceSheet` 里的 `import` 风险确认**

`_openWorkspaceSheet`(:489-538)与 `_groupLabel`(:481-487)未改动,继续被 `_buildWorkspaceAction` 调用,无需 import 调整。

- [ ] **Step 4: `flutter analyze` 校验**

```bash
flutter analyze lib/lab/demos/kvcli_todo_demo.dart
```

Expected: no errors, no warnings introduced by this change.若出现未使用 import/字段,顺手清理(只清本任务相关)。

- [ ] **Step 5: 验证行为不变**

代码层验证(无需起 app):
- `_openWorkspaceSheet` 引用计数 1(`_buildWorkspaceAction`),无死代码。
- `_groupLabel` 引用计数:既有 1(`_openWorkspaceSheet`) + 新增 1(`_buildWorkspaceAction`) = 2。
- `ref.watch(activeGroupProvider)` 仍在 `build`(:583)读取,传给 `_buildWorkspaceAction`。
- body `Column` 内 `_loading ? CircularProgressIndicator : Column(composer + topics + list)` 不动;刷新弧线现在覆盖整个 body,不接触 AppBar bottom 区,**视觉不再与 tab 行交错**。

- [ ] **Step 6: Commit + Push**

```bash
git add lib/lab/demos/kvcli_todo_demo.dart
git status   # 确认只有本任务文件被 add
git commit -m "fix(lab/kvcli-todo): AppBar 工作空间迁移到 actions 消除窄屏交错"
git push
```

---

## 自检(写入前)

1. **Spec 覆盖**:任务"头部空间选择,和刷新的 UI 冲突了,出现的堆叠,ui 出现了交错,点击正常,宽度比较小的平台,kv清单"——本计划把"工作空间 chip"挪进 actions 槽位 + 不让刷新圈覆盖 AppBar bottom 区 = ✅ 覆盖。
2. **占位符**:无 "TBD / TODO / 适当处理" 字样。
3. **类型一致性**:`_buildWorkspaceAction(ColorScheme, int)` 与调用点 `(scheme, gid)` 一致;`ref.watch(activeGroupProvider)` 返回 `int`,`_groupLabel(int)` 签名匹配。

## 已知非目标

- 不动 `bottom: PreferredSize(48)` 的 tab 行(它已经独立一行,不是交错源)。
- 不改 `_openWorkspaceSheet` 的弹层内容(用户已确认布局没问题)。
- 不动 composer / quick topics / list(无关)。
- 不引入新文件、不新增依赖。