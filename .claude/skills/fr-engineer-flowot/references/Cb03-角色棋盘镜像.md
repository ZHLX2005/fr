# role-aware-board-mirror — 棋盘对称翻转的"角色为基 + 坐标共识"模型

> 从 surround_game_lua（围追堵截 Quoridor 互联网双人对战）沉淀。适用于 **对称对战棋盘**（双方都看到"自己在底部"）的互联网房间业务：国际象棋、围棋、五子棋、Quoridor、军棋……

核心一句话：**这不是"统一镜像"，而是"按角色 + 按元素类型分别决策翻转"。**

---

## 0. 为什么不是简单镜像？

一个棋盘页面有 **N 种 UI 元素**，每种对翻转的需求**不一样**：

- 棋盘背景、已放墙、棋子 → 跟着规范坐标渲染，整体翻转就行
- 触摸坐标 → Listener 不在 `Transform.flip` 内，`localPosition` 与视觉翻转**无关**，必须手动镜像
- 确认按钮 → 放在翻转层内会被上下镜像，必须移出 + 坐标镜像
- 终局消息 → 与翻转无关，但必须用"角色"推"我方/对方"，不能用"上方/下方"

**所以镜像是一个"逐元素决策表"，不是一个开关。** 下文 §4 给完整决策表。

---

## 1. 两个坐标系 + 一个角色字段

### ① 规范坐标系（canonical）— 服务端共识

服务端只存**一套坐标**，所有玩家共用。约定创建者 = top：

```lua
on_init = function(c, p)
  c.host_id = p.device_id
  -- 权威角色字段：host = top player（y=0），guest = bottom player（y=8）
  c.top_player_id = p.device_id
  ...
end
```

`history`、`validMoves`、墙位置**全部用规范坐标**存储和计算。客户端**不**各存各的坐标。

### ② 视觉坐标系（visual）— 每个客户端自己的

每个客户端都要"**自己在视觉底部**"（人对着屏幕的习惯）：

- guest（bottom=规范 y8）→ 不翻转，自己天然在底部
- host（top=规范 y0）→ 棋盘整体 `Transform.flip(flipY: true)`，自己翻到底部

### ③ 角色字段 — 客户端"我是哪一方"

```dart
/// 我是 top 还是 bottom？用服务端权威字段推，不要用 isHost。
bool get _imTop {
  final topId = SgRoom.topPlayerId(_snap);
  if (topId == null) return false;
  return _room.deviceId == topId;
}
```

> 🟡 **为什么不用 `isHost`？** 万一未来出现"host 旁观、玩家换人"的场景，`isHost` 会错，但"我在棋盘上对应 top/bottom"仍然由 `top_player_id` 正确表达。语义要独立。

**核心派生**：`isMyTurn = _imTop == gs.currentPlayerIsTop`（与视角无关，纯角色判断）。

---

## 2. 镜像策略总览

```
服务端：规范坐标（host=top=y0, guest=bottom=y8）
            │
            ▼ snapshot 推给所有客户端
   ┌────────────────────────┬────────────────────────┐
   │ host 客户端            │ guest 客户端           │
   │ _imTop = true          │ _imTop = false         │
   │ _flipY = true          │ _flipY = false         │
   │                        │                        │
   │  Stack {               │  Stack {               │
   │   Transform.flip(      │   _drawLayer(...)      │
   │     flipY: true,       │     (原样)             │
   │     child: _drawLayer  │   TouchView(...)       │
   │   )                    │  }                     │
   │   TouchView(...)       │                        │
   │  }                     │                        │
   └────────────────────────┴────────────────────────┘
```

**关键结构**：`_drawLayer`（棋盘绘制）被外层 `Transform.flip` 包裹；`TouchView`（触摸层）**在 flip 之外**；确认按钮**也移到 flip 之外**（见 §4）。

---

## 3. 触摸坐标必须手动镜像（最隐蔽的坑）

### 现象

host 端棋子拖不动 / 放不进合法格。

### 根因

`TouchView` 内部是 `Positioned.fill` + `Listener`。Listener **不在** `Transform.flip` 子树里，所以 `event.localPosition` 是 **Stack 局部坐标**，与视觉是否翻转**完全无关**。

```
host 视觉底部（自己棋子）  →  localPosition.y ≈ boardSize（大）
服务端规范：host 自己 = y0  →  需要 y=0（小）
```

直接把 `localPosition` 喂给 TouchController，算出的 `targetId` 在规范 y8 区域（bottom 起点），不在 host 的 `validMoves` 里 → `handleTouchEnded` 静默 reset。

### 修复：在指针回调里镜像

```dart
/// Listener 内的 localPosition → 规范坐标系 localPosition
Offset _canonicalLocalPosition(Offset pos) =>
    _flipY ? Offset(pos.dx, _boardSizePx - pos.dy) : pos;

void _onPointerDown(Offset pos, double cs, double dist) {
  if (!_isMyTurn) return;
  _touchCtrl.handleTouchBegan(_canonicalLocalPosition(pos), cs, dist, ...);
}
// onPointerMove / onPointerUp 同理
```

`_boardSizePx` 在 `LayoutBuilder` 里赋值（= `constraints.maxWidth`）。

> 💡 这样 TouchController 内部的 `targetCellId`、`pendingWall`、`dragOffset` **全是规范坐标**，后续 `validMoves.contains(targetId)` 是规范坐标系的匹配，host/guest 逻辑统一。

---

## 4. 翻转决策表（核心交付物）

| 元素 | host 端策略 | 为什么 | guest 端 |
|------|------------|--------|----------|
| 棋盘背景 `ChessBoard` | 外层 `Transform.flip` | 跟规范坐标一致渲染 | 原样 |
| 已放墙 `ChessWall` | 外层 `Transform.flip` | 同上 | 原样 |
| 棋子 `ChessPlayer` | 外层 `Transform.flip` | 同上 | 原样 |
| 合法走点 `PlayerPrompt` | 外层 `Transform.flip` | 同上 | 原样 |
| **触摸坐标** | **回调里 `_canonicalLocalPosition` 手动镜像** | Listener 不在 flip 子树，localPosition 与视觉无关 | 不镜像 |
| 浮动棋子 `_FloatingPiece` | 放 flip 层内，`dragOffset` 用规范坐标 | 整层翻转自动校正视觉 | 同（规范坐标） |
| 墙预览 `WallPrompt` | 放 flip 层内，用规范坐标 | 同上 | 同 |
| **确认按钮 `ConfirmActions`** | **移出 flip 层**，传入坐标 `y → 8-y` 镜像 | flip 会把按钮 top 上下镜像（视觉对称反向） | 原样传入 |
| `PlayerPanel` | `rotated: false`，不翻转 | 面板始终底部，棋盘翻转代替 | 同 |
| 终局消息 | 用 `_imTop` 推"我方/对方" | 角色感知，host 视觉翻转后"上方"语义错位 | 同 |
| **棋子图标朝向** | **保留内置 `flipped` 标记（如 `piece.color == PlayerColor.red`）** | 详见 §4.5 — 外层 `Transform.flip` 会和内置翻转**对消** | 同 host 列 |

### 确认按钮为什么特殊？

`ConfirmActions` 的 `top` 用规范坐标（默认在目标格"规范下方"）。host 端如果把它放在被 `Transform.flip` 的 `_drawLayer` 里，按钮 top 被翻转 → 视觉跑到棋子**上方**，看起来"上下对称反向"。

**修复**：把 `ConfirmActions` 移到外层 Stack 直接子节点（不被翻转），host 端把传入坐标镜像后再传：

```dart
Widget _buildConfirmActions(double cs, double boardSize, BoardThemeData theme) {
  final toc = _touchCtrl;
  int? visualCellId = toc.pendingTargetCellId;
  ({int x, int y, WallOrientation o})? visualWall = toc.pendingWall;
  if (_flipY) {
    if (visualCellId != null) {
      final x = visualCellId % 9, y = visualCellId ~/ 9;
      visualCellId = (8 - y) * 9 + x;       // y 镜像
    }
    if (visualWall != null) {
      visualWall = (x: visualWall.x, y: 8 - visualWall.y, o: visualWall.o);
    }
  }
  return ConfirmActions(
    pendingTargetCellId: visualCellId,
    pendingWall: visualWall,
    isTopTurn: false,   // 互联网版双方视觉都"从底部看"，按钮图标恒不翻转
    ...
  );
}
```

> 🟡 `Positioned` widget 必须是 `Stack` 的**直接**子节点，不能被 `Transform` 包裹（否则布局报错）。这是把 ConfirmActions 移出 flip 层的另一个技术原因。

---

## 4.5 棋子图标对称 — 内置 `flipped` 和外层 `Transform.flip` 的对消

> 从斗兽棋互联网版沉淀：棋子图标的"对自己正 / 对对方反"语义在 LAN 和互联网两种模式下是**天然兼容**的。

### 经典 LAN 设计

LAN 面对面坐，两人共享一块屏幕。设计师约定：棋子图标的"正"方向是给**棋子所属方**看的。渲染时：

```dart
// JunglePieceWidget
Transform.rotate(
  angle: flipped ? math.pi : 0,  // flipped = piece.color == PlayerColor.red
  child: Image.asset(piece.assetPath),
)
```

**效果**：
- LAN 蓝方视角：己方（蓝）棋子不翻转 → 自己看的动物是正的；对方（红）棋子旋转 180° → 看着对面玩家
- LAN 红方视角：刚好相反

### 互联网模式的兼容

互联网模式下，整块棋盘按 §2 翻转了 180°（host 端 `Transform.flip`）。棋子的内置 `flipped` 标记 **继续生效**（因为 JungleBoard 在 flip 子树内），产生**双重翻转对消**：

| 客户端 | 棋子 | 内置 flipped | 外层 flip | 视觉朝向 |
|--------|------|--------------|-----------|----------|
| **host**（top=red） | 自己的红子 | 旋转 180° | 旋转 180° | **正向**（己方看着自己） |
| **host**（top=red） | 对方的蓝子 | 不旋转 | 旋转 180° | **反向**（看着对面玩家） |
| **guest**（bottom=blue） | 自己的蓝子 | 不旋转 | 不旋转 | **正向**（己方看着自己） |
| **guest**（bottom=blue） | 对方的红子 | 旋转 180° | 不旋转 | **反向**（看着对面玩家） |

**结论**：互联网模式直接复用 LAN 的 JunglePieceWidget，**零额外代码**——只要"自己正、对方反"是正确语义。`flipped = piece.color == PlayerColor.red`（或 bottom 之外的颜色）这种 LAN 写法**不需要任何改动**就能在互联网模式下工作。

### 反模式：互联网模式下"自己棋子也翻"

> 🟡 不要写 `flipped: piece.color == state.currentTurn` 或 `flipped: !isMine`。这会让**自己棋子反向**、**对方棋子正向**——和直觉完全相反。

```dart
// ❌ 反模式（互联网模式下）
flipped: !isMine
// 自己棋子 → flipped → 外层再翻 → 双重翻转对消 → 正向 ✓
// 对方棋子 → 不翻 → 外层翻 → 反向 ✓
// ……看起来对？但 _imTop 不同时方向相反。host 端自己的红子是 !isMine = true，
//   flipped=true → 外层翻 → 对消成正向 ✓
//   guest 端自己的蓝子是 !isMine = false，
//   flipped=false → 外层不翻 → 正向 ✓
//   这个写法**碰巧**也对，但耦合了"isMine"和"颜色"，不易维护。

// ✅ 正确（沿用 LAN 写法）
flipped: piece.color == PlayerColor.red  // 或任意非 top 方颜色
// 直接基于颜色语义，不依赖 isMine 派生。LAN / 互联网共用同一行代码。
```

### 何时必须自己写翻转

如果棋子的"正方向"对**当前玩家视角**而言需要翻转（例如中国象棋的红黑双方字面朝向）：

```dart
// 例如：棋子上的"帅"字应该正对**当前玩家**——host 看自己的帅字是正的
Transform.rotate(
  angle: (isMyTurn || isMine) ? 0 : math.pi,
  child: ...,
)
```

**判断方法**：问"我的棋子上的字/图，应该是**我**看正，还是**对面的对方**看正"。前者用 `isMine`；后者用内置 LAN 写法（颜色派别）。

---

## 5. 角色感知的终局/消息

LAN 模式两人看同一棋盘，"上方获胜"有明确视觉对应。互联网版 host 视觉翻转，"上方" = 自己 → "上方获胜"对 host 是赢、对 guest 是输，**语义错位**。

统一用**角色**推：

```dart
final String msg;
if (gs.status == GameStatus.draw) {
  msg = '平局';
} else if (isTopWin == _imTop) {
  msg = '我方获胜！';   // 我是 top 且 top 赢 / 我是 bottom 且 bottom 赢
} else {
  msg = '对方获胜';
}
```

认输、悔棋提示同理：基于 `_imTop` / `top_player_id`，不用"上/下方"。

---

## 6. TouchView 挂载 guard

```dart
final canMountTouchView = _snap != null
    && _snap?.state == 'playing'
    && _isMyTurn;
```

> 🟡 **不要加 `gs.history.isNotEmpty`**！开局 history 为空时先手玩家要下第一步，加这一项会导致先手 TouchView 永不挂载。合法性由 `validMoves.contains(targetId)` 保证，不需要 history 非空。

---

## 7. `_ensureTouchController` 只首次校准

```dart
void _ensureTouchController(double boardSize) {
  // 只在类型不对时重建，避免每次 build 重置触摸状态
  if (_touchCtrl is! TouchController) {
    _touchCtrl = TouchController();
  }
}
```

> 🟡 **反模式**：`else { _touchCtrl = TouchController(); }` 每次 build 都 new 一个 → `phase`/`targetCellId`/`previewWall` 在 `pointerMove` 之间全丢 → 按下棋子抬不起来。这是围追堵截"拖不动"的第一根因。

---

## 8. 真实 fix 时间线（围追堵截踩坑记录）

| 轮次 | 方案 | 失败点 | 修法 |
|------|------|--------|------|
| ① | host 用 `SgHostTouchController._mirror` 镜像触摸 | `_ensureTouchController` 每帧 new controller → 触摸状态丢失 | controller 只首次校准（§7） |
| ② | 删 `SgHostTouchController`，统一基线 + `_canonicalLocalPosition` | host 拖动了，但 ConfirmActions 在 flip 层内被上下镜像 | ConfirmActions 移出 flip 层 + 坐标镜像（§4） |
| ③ | 上述都修好 | 开局先手 TouchView 不挂载（history 空被 guard 挡） | 删 `history.isNotEmpty` guard（§6） |
| ④ | 角色用 `isHost` 推 | 终局消息"上方获胜"host/guest 语义错位 | 加 `top_player_id` 服务端字段 + `_imTop`（§1、§5） |

**教训**：镜像问题不是一次性 fix，而是**逐元素、逐症状**排查。每修一个症状，下一层症状才暴露。决策表（§4）是把隐性经验固化成显性 checklist 的关键。

---

## 9. 反模式速查

| ❌ 错误 | 后果 | ✅ 正确 |
|--------|------|---------|
| 用 `isHost` 推角色 | host 旁观/换人时错 | 用 `top_player_id` 推 `_imTop` |
| TouchView mount 加 `history.isNotEmpty` | 开局先手进不去 | 只 `state==playing && _isMyTurn` |
| `_ensureTouchController` 每次 build 重置 | 触摸状态丢失，拖不动 | 只首次校准 |
| ConfirmActions 放 `Transform.flip` 子树内 | 按钮上下镜像 | 移到外层 Stack，坐标镜像 |
| 触摸坐标直接喂 TouchController（host） | validMoves 匹配失败 | `_canonicalLocalPosition` 镜像 |
| 终局消息用"上方/下方获胜" | host 视觉翻转后语义错位 | 用 `_imTop` 推"我方/对方" |
| `Positioned` 被 `Transform` 包裹 | 布局报错 | `Positioned` 必须是 Stack 直接子节点 |

---

## 10. 适用判断

读这个 ref 当且仅当你的业务**同时满足**：

- ✅ 有"棋盘"这种**共识坐标系**（服务端权威坐标）
- ✅ 多个客户端**对称视角**（都看到自己在底部/自己一侧）
- ✅ 涉及**触摸交互**（拖棋子、放墙、落子）

纯聊天/投票/白板（无对称视角）**不需要**这个 ref。
