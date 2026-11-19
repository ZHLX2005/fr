# skill C00 治理史归档（2026-11-19 迁出）

> 来源：`.claude/skills/fr-engineer-flowot/references/C00-RelayLua路由.md`。
> 按 SKILL.md 维护规则「治理史不进 skill」迁出归档。原 C00 内嵌教程/坑表已改写为
> `Ca04-Lua房间契约检查表` 与 `Cb01-双人对战房间模板` §9 反模式行；本文只保留操作教训历史，
> 正文不再维护，以 `references/` 现行页为准。

### [2026-08-28] key_board_3 操作教训

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 把"图标对称"也独立成一个 ref | 和 `Cb03-角色棋盘镜像` 翻转决策表重复（都属于"棋盘对称"主题） | 在 `Cb03-角色棋盘镜像` 加 §4.5 一节，沿用其"翻转决策表"框架 |
| 把"手势层"塞进 `Cb01-双人对战房间模板` | 200+ 行让端到端模板臃肿，且未来"非对战棋盘"（围棋布局编辑器 / 解谜）也要用 | 独立 `Cb04-棋盘手势模式` ref，按"主题判据"（不是"内容多少"）拆 |
| 把"WS 检测 + 快照拉取"独立成 ref | 适用范围狭窄（只互联网对战），但 `Cb01-双人对战房间模板` 已经是"对战通用模板"，扩 §3.5 一节即可 | 扩 `Cb01-双人对战房间模板.md`，加 §3.5 WS 状态条 + §3.6 落子音 |
| 把"音效"独立成 ref | 所有 4 个对战游戏都用同一个 `PieceSound`，不是 relay-v3 协议相关 | 同样扩 §3.6，不另起 ref |

### [2026-08-28] codebase-optimizer 反思（4 个新经验）

#### good_eg：跨游戏通用 UI 组件抽到 core 子目录

**来源：** 在 jungle_chess_lua 内联实现 WS 状态条后，扩展到 7 个 Lua 房间游戏时，提取为 `RelayConnectionBar`。

**场景：** 同一段 UI / 逻辑（stream 订阅 + 防双击 + 失败 snackbar）在 4+ 个 demo 各写一遍时。

**做法（做对了什么）：**
- 抽出到 `lib/core/<subsystem>/<name>.dart`（本例 `lib/core/ui/game/relay_connection_bar.dart`——UI 件落全局组件目录 `lib/core/ui/game/`，2026-10-24 起）
- 自带 stream 订阅 + 状态管理（callers 0 状态代码）
- 在所有 demo 文件加 1 行 import + 1 行调用即接入（`<RelayConnectionBar(handle: widget.handle) />`）
- 适用范围 ≤ 5 个 demo 时**不要**硬抽——直接 inline；≥ 4 个时**应该**抽出来

**为什么不这么做会出问题：** 7 个 demo 每个写 30 行重复订阅代码 ≈ 200 行技术债，且 bug 修一处忘一处。

**关联：** 配合 `Cb01-双人对战房间模板` §3.5（WS 状态条）使用效果更好——该 ref 直接指向共享 widget。

#### bad_eg：照搬其他游戏的 UI 模式不校验语义 ❌

**来源：** 第一次做 jungle_chess_lua 时，照搬五子棋"两步确认门"。

**错误做法：** `onLocalMoveConfirmed → _pending 待确认 → 确认按钮 → _room.move`。

**后果：** 斗兽棋走法已由 `JungleEngine.getValidMoves` 校验，非法目标根本不响应 → 确认门是冗余 UX，用户多一次点击且 56px 槽位浪费屏幕。

**根因分析：** 没想清楚"是否需要确认"是由**游戏走法可逆性**决定的，不是由"我之前怎么做的"决定的。

**正确做法：**
- 落子不可逆 / 操作复杂（五子棋）：保留两步确认
- 走法靠引擎校验、非法目标已被拦截（斗兽棋 / 围棋 / 黑白翻转棋 / 政变）：**直接落子** + 拖动 + 点击两种交互共存

**预防：** 在 §3.3 playing 阶段文档里明确"是否需要确认"的两条决策路径。

#### bad_eg：复用引擎时不区分双方先手约定 ❌

**来源：** jungle_chess_lua 红蓝双方控制对方棋子 bug。

**错误做法：** 复用 `JungleEngine.createInitialState()`（LAN 蓝方先手），但 Lua 服务端约定 `top_player_id`（红方 / host）先走。

**后果：** 客户端 `GameState.currentTurn = blue`，但服务端判定 `current_player` 是 red → host 端触摸控制器 `piece.color == state.currentTurn` = `red == blue` = false → 反而能选蓝方棋子（对方的）。

**根因分析：** `createInitialState` 把"先手方"硬编码为 blue，没有参数化。

**正确做法：**

```dart
// core：保留原函数（LAN 向后兼容）
static GameState createInitialState() =>
    createInitialStateFor(firstTurn: PlayerColor.blue);

// core：参数化版本
static GameState createInitialStateFor({required PlayerColor firstTurn}) { ... }

// Lua 互联网版：显式 red 先手
static GameState rebuildBoard(List<JungleMoveRecord> history) {
  var s = JungleEngine.createInitialStateFor(firstTurn: PlayerColor.red);
  ...
}
```

**预防：** 共享引擎被多个上层（LAN / Lua / 教程）复用时，**先手方 / 任何"业务侧可选"参数必须参数化**，不能硬编码默认。

#### good_eg：自包含 widget 自带 stream 订阅

**来源：** `RelayConnectionBar` 的设计。

**场景：** UI 组件需要监听 `RoomHandle.closeEvents` + `snapshots` 来显示连接状态。

**做法：**
- widget 自带 `initState / dispose` 订阅 + cancel
- callers 只需要 `import + 用一次`（`<RelayConnectionBar(handle: widget.handle) />`）
- 不暴露内部状态给 parent（`_wsConnected` 是 private）

**为什么不这么做会出问题：** 如果 widget 暴露 `_wsConnected` 给 callers，7 个 demo 每个都要写 4 个状态字段 + 3 个 listener cancel，bug 同步成本高。

**关联：** `Cb01-双人对战房间模板` §3.5 直接引用此模式。

#### bad_eg：外层 GestureDetector + 内部 GestureDetector 双触发 ❌

**来源：** jungle_chess_lua 第二次修触摸 bug 时，外层自写 GestureDetector 把 `localPosition` 直接喂 `JungleTouchController`，同时 JungleBoard 内部也挂了一个。

**错误做法：**
```dart
// widget.dart 外面
Positioned.fill(child: GestureDetector(
  onTapDown: (d) => _touchController.onCellTap(_gameState, _canonicalIdx(d.localPosition)),
  ...
)),
// JungleBoard 内部还有
GestureDetector(onTapDown: (d) => ctrl.onCellTap(...))
```

**后果：** 两个回调都会触发 → 触摸状态错乱 → 选中/拖动/落子逻辑互相覆盖 → 用户体感是"按了没反应"。

**根因分析：** 没意识到 JungleBoard 已经自带 GestureDetector（当 `touchController != null` 时挂载）。

**正确做法：** 复用 JungleBoard **内部** 的 GestureDetector，让 `localPosition` 在 board-local 坐标系（不受外层 `Transform.flip` 影响）。删除外层 wrapper。

**预防：** 任何"在 widget 外层套 Listener / GestureDetector"的模式都要先**搜索基类是否已挂载**。详细决策表见 `Cb04-棋盘手势模式` §3.1。
