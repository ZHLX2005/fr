# 五子棋直接表单主页 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将五子棋入口从“建房/加入二选一面板”改为同页展示两个紧凑表单卡片，减少留白并降低操作层级。

**Architecture:** 保留现有 `SetupPage` 与 `JoinPage` 的网络逻辑和回调接口，仅调整 `GomokuLuaPage` 的入口布局；两个表单同时渲染在统一滚动容器中，使用卡片视觉分区。游戏房间内页面、Lua 协议、棋盘逻辑不变。

**Tech Stack:** Flutter Material 3、现有 `BoardTheme`、RelayV3 `RoomHandle`。

## Global Constraints

- 不新增依赖。
- 不修改 Android 原生目录、Relay/Lua 协议或房间内对战逻辑。
- 保留现有 `SetupPage(onCreated:)` 和 `JoinPage(onJoined:)` 接口。
- 页面使用自适应布局，避免小屏溢出。
- 完成后执行 `flutter analyze`，只提交本次变更文件并 push。

---

### Task 1: 重构五子棋入口主页

**Files:**
- Modify: `lib/lab/demos/gomoku_lua_demo.dart:47-133`

**Interfaces:**
- Consumes: `SetupPage(onCreated:)`、`JoinPage(onJoined:)`、`GomokuOpeningPlayer`。
- Produces: 同页渲染的创建房间卡片和加入房间卡片；成功后仍调用 `_onCreated`/`_onJoined` 进入 `OnlineGamePage`。

- [ ] **Step 1: 删除二选一状态与 SegmentedButton**

移除 `_isMaster` 字段；主页不再使用 `SegmentedButton<bool>`，也不再用 `_isMaster ? SetupPage : JoinPage` 条件渲染。

- [ ] **Step 2: 添加统一滚动主页布局**

将未进入房间时的 `body` 改为 `SafeArea + SingleChildScrollView + Padding + Column`，包含：

1. 紧凑的棋子/标题头部：`五子棋`、`在线双人对战`、`15×15 · 连五获胜`。
2. `Card` 包裹 `SetupPage`，标题“创建房间”、副标题“你执黑，先手”。
3. `Card` 包裹 `JoinPage`，标题“加入房间”、副标题“你执白，后手”。
4. 底部保留“开局学习”按钮。

使用 `LayoutBuilder` 约束内容最大宽度（例如 `min(constraints.maxWidth, 520)`），小屏时上下排列，不使用固定高度。

- [ ] **Step 3: 调整 SetupPage/JoinPage 的嵌入表现**

由于两个表单现在嵌入卡片，移除其 `Center + Padding(32)` 的大面积留白，改为 `Padding(horizontal: 16, vertical: 12)` 和紧凑间距；保留原有输入、校验、loading、错误提示及回调逻辑。

- [ ] **Step 4: 运行分析验证**

Run:

```bash
flutter analyze lib/lab/demos/gomoku_lua_demo.dart lib/lab/demos/gomoku_lua/
```

Expected: 新增代码无 error/warning；若出现已有 `opening` 相关 warning，只确认不由本次布局修改引入，并单独记录。

- [ ] **Step 5: 检查状态并提交**

```bash
git status --short
git add lib/lab/demos/gomoku_lua_demo.dart lib/lab/demos/gomoku_lua/widgets.dart
git commit -m "feat(gomoku): redesign room entry as direct form lobby"
git push
```

只提交本次主页改动文件，不提交其他工作区变更。

---

## Self-review

- 入口不再有建房/加入切换：Task 1 Step 1 覆盖。
- 两个表单同时可见：Task 1 Step 2 覆盖。
- 空旷问题通过统一宽度、紧凑 padding、卡片分区解决：Task 1 Step 2-3 覆盖。
- 原有建房/加入网络接口不变：Interfaces 与 Step 3 覆盖。
- 小屏溢出通过滚动容器和最大宽度约束规避：Step 2 覆盖。
- Lua、房间内游戏逻辑不变：Global Constraints 覆盖。
