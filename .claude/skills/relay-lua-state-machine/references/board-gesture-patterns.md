# board-gesture-patterns — 棋盘手势范式

> 从斗兽棋互联网版沉淀（2026-08）：可拖动 + 可点击选择 + 点击落子（国际象棋 / 中国象棋的预备范式）。
>
> 与 [[role-aware-board-mirror]] 配合使用：本 ref 讲"手势层在做什么"；mirror ref 讲"host 视觉翻转怎么套到这些手势上"。

---

## 0. 为什么需要统一手势范式？

棋盘手势看似简单，但实战中至少 4 类需求叠加：

1. **点击选中 + 二次点击落子**（中国象棋 / 国际象棋玩家习惯——桌面棋子不能拖）
2. **长按拖动 + 松手落子**（五子棋 / 围棋 / 斗兽棋玩家习惯——快速移动）
3. **拖动中实时预览目标点**（drag hover 高亮 + 浮起阴影）
4. **非法目标静默拒绝**（不响铃、不弹 toast，只不触发 `onMoveConfirmed`）

如果 4 个需求散在 4 个地方写，会出现：

- 双 GestureDetector 冲突（外层 + 内层同时监听同一手势）
- 触摸状态在 build 之间丢失
- 落子坐标 / 视觉坐标混淆

下面是一个**统一**的状态机：把 4 种交互收敛到 1 个 `TouchController`，所有视觉反馈（合法目标点 / 拖动浮起 / 选中环）都从 controller 派生。

---

## 1. `TouchController` 状态机

### 4 个 `phase`

```dart
enum TouchPhase { idle, pieceSelected, dragging, moveConfirmed }
```

| phase | 含义 | 进入方式 | 退出方式 |
|-------|------|----------|----------|
| `idle` | 无选子 | 初始态 / `_reset()` | → `pieceSelected`（点己方棋子）<br>→ `dragging`（按住己方棋子） |
| `pieceSelected` | 已选子待二次点击 | 点己方棋子 | → `moveConfirmed`（点合法目标）<br>→ `pieceSelected`（点另一颗己方棋子，切换选中）<br>→ `idle`（点非法位置，取消） |
| `dragging` | 拖动中 | 按住己方棋子 | → `moveConfirmed`（松手在合法目标）<br>→ `pieceSelected`（松手在非法目标 → 保持选中等待二次点击） |
| `moveConfirmed` | 触发回调 + 清状态 | onCellTap/onDragEnd 命中合法目标 | → `idle`（`_reset()` 在 `onMoveConfirmed` 内部调用） |

### 关键属性

```dart
class TouchController extends ChangeNotifier {
  TouchPhase phase = TouchPhase.idle;
  int? selectedIndex;             // 当前选中的格子 1D index
  List<Coord> validTargets = [];  // 该子的合法落点（合法目标圆点 + 拦截非法点击）
  int? targetIndex;               // 拖动悬停的格子
  Offset? dragFingerPos;          // 拖动中手指在 board-local 的位置
  int? dragHoverIndex;            // 拖动中手指命中格（用于 hover 高亮）

  void Function(Coord from, Coord to)? onMoveConfirmed;
}
```

---

## 2. 4 种交互的最小实现

### 2.1 点击选中

```dart
void onCellTap(GameState state, int index) {
  final piece = state.pieces[index];
  switch (phase) {
    case TouchPhase.idle:
      // 空闲 → 点到己方棋子 → 选中
      if (piece != null && piece.isAlive && piece.color == state.currentTurn) {
        selectedIndex = index;
        validTargets = engine.getValidMoves(state, CoordUtils.fromIndex(index));
        phase = TouchPhase.pieceSelected;
        notifyListeners();
      }
      break;
    // ... pieceSelected 见 2.2
    case TouchPhase.dragging:
      break;  // 拖动中点击无响应（防止误触）
  }
}
```

### 2.2 二次点击落子（点选移动的关键）

```dart
case TouchPhase.pieceSelected:
  // 命中合法目标 → 直接落子
  if (selectedIndex != null && validTargets.any((c) => c.index == index)) {
    final from = CoordUtils.fromIndex(selectedIndex!);
    final to = CoordUtils.fromIndex(index);
    _reset();
    phase = TouchPhase.moveConfirmed;
    notifyListeners();
    onMoveConfirmed?.call(from, to);
    break;
  }
  // 点了另一颗己方棋子 → 切换选中
  if (piece != null && piece.isAlive && piece.color == state.currentTurn) {
    selectedIndex = index;
    validTargets = engine.getValidMoves(state, CoordUtils.fromIndex(index));
    notifyListeners();
    break;
  }
  // 非法位置（已方阻挡 / 不可吃对方 / 空格不在 validTargets）→ 取消
  _reset();
  break;
```

> 🟡 **必须**区分"合法目标"、"另一颗己方棋子"、"非法位置" 三类。否则用户点了空格就什么都不发生，体感很差。

### 2.3 长按拖动

```dart
void onDragStart(GameState state, int index, Offset fingerPos) {
  final piece = state.pieces[index];
  if (piece == null || !piece.isAlive || piece.color != state.currentTurn) return;
  selectedIndex = index;
  validTargets = engine.getValidMoves(state, CoordUtils.fromIndex(index));
  dragFingerPos = fingerPos;
  dragHoverIndex = index;
  phase = TouchPhase.dragging;
  notifyListeners();
}

void onDragUpdate(GameState state, Offset fingerPos) {
  if (phase != TouchPhase.dragging) return;
  dragFingerPos = fingerPos;
  dragHoverIndex = _hitFromPos(state, fingerPos)?.index;
  notifyListeners();
}

void onDragEnd(GameState state, Offset fingerPos) {
  if (phase != TouchPhase.dragging) return;
  final dropIndex = _hitFromPos(state, fingerPos)?.index;
  if (dropIndex != null && validTargets.any((c) => c.index == dropIndex)) {
    final from = CoordUtils.fromIndex(selectedIndex!);
    final to = CoordUtils.fromIndex(dropIndex);
    _reset();
    phase = TouchPhase.moveConfirmed;
    notifyListeners();
    onMoveConfirmed?.call(from, to);
  } else {
    // 松手在非法目标 → 退到 pieceSelected（视觉保持选中，提示"再点目标"）
    phase = TouchPhase.pieceSelected;
    dragFingerPos = null;
    dragHoverIndex = null;
    notifyListeners();
  }
}
```

### 2.4 非法目标静默拒绝

`onCellTap` 命中非合法目标的格子时：

- 是另一颗己方棋子 → 切换选中（不拒绝）
- 是对方不可吃的棋子 → 取消（不响铃，不弹 toast）
- 是空格但不在 `validTargets` → 取消

`onDragEnd` 松手在非法目标时：

- 退到 `pieceSelected`（不直接清空 — 让用户感觉"还能再点一次")

---

## 3. JungleBoard / 通用棋盘 widget 的接入

### 3.1 单 GestureDetector 设计

JungleBoard 内部**只挂一个** GestureDetector，把点击和拖动两种事件都接上：

```dart
if (ctrl == null) return Center(child: board);  // 只读模式：无手势

return Center(
  child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (d) {
      final hit = _hitTest(d.localPosition, cellSize);
      if (hit == null) return;
      ctrl.onCellTap(widget.gameState, hit.row * kBoardCols + hit.col);
    },
    onPanStart: (d) {
      final hit = _hitTest(d.localPosition, cellSize);
      if (hit == null) return;
      ctrl.onDragStart(widget.gameState, hit.row * kBoardCols + hit.col, d.localPosition);
    },
    onPanUpdate: (d) {
      ctrl.onDragUpdate(widget.gameState, d.localPosition);
    },
    onPanEnd: (d) {
      ctrl.onDragEnd(widget.gameState, d.localPosition);
    },
    child: board,
  ),
);
```

> 🟡 **不要**在外层 widget 写第二个 GestureDetector + 自定义镜像坐标——和 JungleBoard 内部会双触发。直接复用 JungleBoard 的内置 GestureDetector，让 `localPosition` 在 board-local 坐标系（不受外层 Transform.flip 影响）。

### 3.2 controller 只首次校准

```dart
void _ensureTouchController() {
  // 只在类型不对时重建，避免每次 build 重置触摸状态
  if (_touchCtrl is! TouchController) {
    _touchCtrl = TouchController();
  }
}
```

> 🟡 **反模式**：`else { _touchCtrl = TouchController(); }` 每次 build 都 new 一个 → `phase` / `targetIndex` / `previewWall` 在 pointerMove 之间全丢 → 按下棋子抬不起来。

### 3.3 controller 只在 myTurn 时挂载

```dart
final canMountTouchView = _snap != null
    && _snap?.state == 'playing'
    && _isMyTurn;
```

```dart
JungleBoard(
  gameState: gs,
  touchController: canMountTouchView ? _touchCtrl : null,
)
```

> 🟡 **不要加 `gs.history.isNotEmpty`**！开局 history 为空时先手玩家要下第一步。加这一项会导致先手 TouchView 永不挂载。合法性由 `validMoves.contains(targetId)` 保证，不需要 history 非空。

---

## 4. 视觉反馈（从 controller 派生，不重复维护）

| 视觉 | 来源 | 渲染时机 |
|------|------|----------|
| **合法目标圆点**（绿色空格 / 红色可吃） | `ctrl.validTargets` | `phase != idle` 时显示 |
| **悬停高亮**（圆点放大 + 描边） | `ctrl.dragHoverIndex == target && phase == dragging` | 拖动中 |
| **选中环**（棋子金色描边 + 发光） | `ctrl.selectedIndex == piece.position.index` | `phase == pieceSelected \|\| dragging` |
| **拖动浮起**（缩放 1.1 + 阴影加强） | `isDragging` 标记 | `phase == dragging` |
| **拖动中跟随手指** | `ctrl.dragFingerPos`（board-local 坐标） | `phase == dragging` 时渲染 `Positioned` 在棋盘内 |

> 🟢 5 种视觉都从 controller 的 4 个属性派生（`phase` / `selectedIndex` / `validTargets` / `dragHoverIndex` / `dragFingerPos`）——**单一真相**。不要在 widget 层维护"我选中没"等镜像状态。

---

## 5. 撤销按钮的协调

`pieceSelected` 状态期间，用户应该能点一个"取消选中"按钮（避免必须去点非法位置才能取消）。

```dart
void clearSelection() {
  if (phase != TouchPhase.dragging) {  // 拖动中不清
    _reset();
  }
}
```

调用时机：撤销按钮 / 悔棋按钮 / 网络 snapshot 导致 board state 变化（历史变化）时调用一次。

---

## 6. 完整代码骨架（约 150 行）

```dart
enum TouchPhase { idle, pieceSelected, dragging, moveConfirmed }

class TouchController extends ChangeNotifier {
  TouchPhase phase = TouchPhase.idle;
  int? selectedIndex;
  List<Coord> validTargets = [];
  int? targetIndex;
  Offset? dragFingerPos;
  int? dragHoverIndex;
  void Function(Coord from, Coord to)? onMoveConfirmed;

  void onCellTap(GameState state, int index) { /* §2.1 + §2.2 */ }
  void onDragStart(GameState state, int index, Offset pos) { /* §2.3 */ }
  void onDragUpdate(GameState state, Offset pos) { /* §2.3 */ }
  void onDragEnd(GameState state, Offset pos) { /* §2.3 */ }
  void clearSelection() { /* §5 */ }

  void _reset() {
    phase = TouchPhase.idle;
    selectedIndex = null;
    validTargets = [];
    targetIndex = null;
    dragFingerPos = null;
    dragHoverIndex = null;
    notifyListeners();
  }
}
```

---

## 7. 反模式速查

| ❌ 错误 | 后果 | ✅ 正确 |
|---------|------|---------|
| 外层 widget 自写第二个 GestureDetector | 与 JungleBoard 内部双触发，触摸状态错乱 | 复用 JungleBoard 内部 GestureDetector |
| `_ensureTouchController` 每次 build 重置 | 触摸状态丢失 | 只首次校准 |
| TouchView mount 加 `history.isNotEmpty` | 开局先手进不去 | 只 `state==playing && _isMyTurn` |
| `onCellTap` 在 `pieceSelected` 阶段只检查"是不是己方棋子" | 点了合法目标 / 对方不可吃位置无响应 | 完整分支：合法目标落子 / 切换选中 / 取消 |
| 拖动浮起用 widget state 而非 controller `dragFingerPos` | 渲染位置和 controller 不同步 | 全部从 controller 派生 |
| `Positioned` 放 `Transform.flip` 子树内 | 布局报错 | `Positioned` 必须是 Stack 直接子节点 |
| 落子后保留选中态等"下次点击" | 用户体感奇怪 | 落子即清状态 → `moveConfirmed` → `idle` |
| 把"撤销选中"靠点非法位置实现 | 用户找不到入口 | 提供显式 `clearSelection` 按钮 |
| 触摸层 listener 在 `Transform.flip` 子树里 + 用 `localPosition` 直接喂 controller | host 端坐标全部错（validMoves 匹配失败） | 复用 JungleBoard 内部 Listener（不受外层 flip 影响） |

---

## 8. 真实 fix 时间线（斗兽棋互联网版踩坑记录）

| 轮 | bug | 根因 | 修法 |
|----|-----|------|------|
| ① | 拖动中棋子松手不能落子 | `_touchController` 每帧 new 一个 → `phase` / `validTargets` 在 `onDragUpdate` 之间全丢 | controller 只首次校准（§3.2） |
| ② | 点了合法目标（空格）无响应 | `onCellTap` 在 `pieceSelected` 阶段只检查"是不是己方棋子"，没检查 validTargets | §2.2 三分支完整实现 |
| ③ | 拖动到非法目标后想再点合法目标，但状态错乱 | `_reset()` 直接清 → 用户失去选中态 | 退到 `pieceSelected` 而非 `idle`（§2.3） |
| ④ | host 端拖动坐标全错（validMoves 匹配失败） | 外层 `Transform.flip` 不影响内部 Listener 的 `localPosition`（在 board-local 坐标系），但我自写了外层 GestureDetector 把 `localPosition` 直接喂 controller | 删除外层 GestureDetector，复用 JungleBoard 内部 Listener |

**教训**：手势层最容易出"双触发"和"坐标系混淆"两种 bug。**单一 GestureDetector + JungleBoard 内部坐标 = 安全**。
