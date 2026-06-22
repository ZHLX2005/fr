# 组件树与 Flutter 映射 · TochuGV-JungleChess UI

> 仓库：`.claude/repo/TochuGV-JungleChess`（Next.js + React + TypeScript，2025）
> 主题：游戏页面组件树、绝对定位渲染、状态管理、SVG 资源 → Flutter/Flame widget 映射
> 定位：**斗兽棋 Flutter UI 蓝图**（React 组件直接对应 Flutter widget，24 个 SVG 棋子可复用）

---

## 1. 游戏页面编排（`web/app/game/page.tsx`）

`"use client"` 客户端组件，165 行，是整个 UI 与交互的中枢。

### 1.1 状态
```tsx
// 来源: web/app/game/page.tsx:22-28
export default function Page() {
  const [board, setBoard] = useState<Board>(loadBoard());              // 棋盘状态
  const [activeCell, setActiveCell] = useState<BoardPosition | undefined>(); // 选中格
  const boardRef = useRef<any>();
  const { cellSize, margin } = useCellSize(board, 100);                // 自适应格子尺寸
  const [showEndModal, setShowEndModal] = useState<boolean>(false);    // 胜负弹窗
  const [moveList, setMoveList] = useState<string[][]>([]);            // 棋谱
  ...
}
```
**状态管理极简**：纯 `useState`（无 Redux/Context，除 `CellSizeContext` 透传 cellSize）。Dart 对应 `StatefulWidget` 或 riverpod `StateNotifier`。

### 1.2 点击交互（`handleClick` `:30-97`）
```tsx
// 来源: web/app/game/page.tsx:30-97 (核心流程)
const handleClick = (event: any) => {
  if (!board.pieces || board.game_ended) return;
  const rect = boardRef.current?.getBoundingClientRect();
  const x = Math.floor((event.clientX - rect.left) / cellSize);        // 像素→格坐标
  const y = Math.floor((event.clientY - rect.top) / cellSize);

  if (activeCell) {                                                    // 已选中→尝试走子
    const activeCellPiece = getPieceByPosition(board.pieces, activeCell).piece;
    if (checkIfPieceWillMove(x, y, board, board.pieces, activeCellPiece, activeCell)) {
      const { piece, pieceIndex } = getPieceByPosition(board.pieces, activeCell);
      const { pieceIndex: pieceToEatIndex } = getPieceByPosition(board.pieces, { x, y });

      const end = getEndInPosition(board, x, y);
      let gameEnded = false;
      if (end && end.color != piece.color) { gameEnded = true; setShowEndModal(true); } // 入敌穴=胜

      // 棋谱：动物字母 + (吃x) + 列字母 + 行号(倒序) + (终局#)
      const formattedMove = getPieceSource(piece)[1] + (pieceToEatIndex != -1 ? "x" : "")
                          + String.fromCharCode(x + 97) + (board.height - y).toString()
                          + (gameEnded ? "#" : "");

      setBoard(prev => ({                                              // 更新棋盘
        ...prev,
        pieces: prev.pieces.map((p, idx) => idx == pieceIndex ? { ...piece, position: { x, y } } : p)
                 .filter((_, idx) => idx != pieceToEatIndex),          // 移除被吃子
        game_ended: gameEnded,
        turn: board.turn < board.turns.length - 1 ? board.turn + 1 : 0  // 换手
      }));
      setActiveCell(undefined);
    }
  }
  // 否则：选中/取消选中己方棋子（须轮到该色）
  ...
}
```

**走子执行范式**（与 Jungle-Chess 不可变重建不同）：TochuGV 用 **`setBoard` 原地 map+filter** 更新 `pieces` 数组——移动选中棋子、过滤掉被吃棋子、推进 turn。Dart 可用不可变 `Board`（仿 Jungle-Chess）或类似的 List 更新。

### 1.3 棋谱记法（`:57`）
`getPieceSource(piece)[1]`（动物字母）+ `x`（吃子）+ 列字母(a-g) + 行号(9-1 倒序) + `#`（终局）。例：`Lxd3#` = 狮吃子至 d3 并获胜。类似国际象棋代数记谱。

---

## 2. 渲染层（绝对定位 + transform）

棋盘用 CSS Grid 容器 + **子元素 absolute + `transform: translate(x*cellSize, y*cellSize)`** 定位。

```tsx
// 来源: web/app/game/page.tsx:106-158
<div className="grid grid-cols-7" onMouseDown={handleClick} ref={boardRef}
     style={{ width: cellSize * board.width, height: cellSize * board.height, ...}}>

  <CellTags board={board} cellSize={cellSize} />     {/* 棋盘格底色 + 行列标签 */}
  <Traps board={board} />                            {/* 陷阱 */}
  <Ends board={board} />                             {/* 兽穴 */}
  <Waters board={board} />                           {/* 河流 */}

  {activeCell && <div className={`absolute bg-${...}-${getActiveCellColor(...)}`}
      style={{ transform: `translate(${activeCell.x*cellSize}px, ${activeCell.y*cellSize}px)`,
               width: cellSize, height: cellSize }} />}   {/* 选中高亮 */}

  <Pieces board={board} cellSize={cellSize} />       {/* 棋子 */}

  {activeCell && getPosibleMoves(...).map(pos => (    {/* 合法走法圆点提示 */}
    <div className="absolute grid place-content-center z-20"
         style={{ transform: `translate(${pos.x*cellSize}px, ${pos.y*cellSize}px)`, ...}}>
      <div className="w-3 h-3 rounded-full bg-[rgba(0,0,0,0.5)]"></div>
    </div>))}
</div>
<MoveListTable {...{board, moveList}} />             {/* 棋谱表 */}
<Modal show={showEndModal} ...>{whoWon(board)} won! ...</Modal>  {/* 胜负弹窗 */}
```

### 组件清单
| 组件 | 文件 | 职责 |
|---|---|---|
| `CellTags` | `components/game/CellTags.tsx:9-41` | 棋盘格交错底色（`bg-primary-500/700`）+ 底行列字母 A-G + 左列行号 9-1 |
| `Trap`/`Traps` | `components/game/Trap.tsx:11-49` | 陷阱格（`bg-trapBackground` + `/assets/board/{B\|R}T.svg`，scale-75） |
| `End`/`Ends` | `components/game/End.tsx:11-49` | 兽穴格（`bg-endBackground-{0\|1}` + `/assets/board/{B\|R}E.svg`） |
| `Water`/`Waters` | `components/game/Water.tsx:6-31` | 河流格（`bg-secondary-{500/700}` 交错） |
| `Piece`/`Pieces` | `components/game/Piece.tsx:12-42` | 棋子（`next/image` + `/assets/pieces/{BR}{R}.svg`） |
| `MoveListTable` | `components/game/MoveListTable.tsx` | 棋谱表 |
| `Modal` | `components/game/Modal.tsx` | 胜负弹窗 |

---

## 3. SVG 资源（可直接复用到 Flutter）

- **棋子**：`web/public/assets/pieces/*.svg`，命名 `{B|R}{R|C|D|W|H|T|L|E}.svg`（`getPieceSource.ts`），共 **16 个**（蓝红各 8），由 `getPieceSource` 拼接文件名（`Piece.tsx:17`）。
  - 注意 CHEETAH（豹）代码是 `H`（`getPieceSource.ts:28-30`）。
- **棋盘地形**：`web/public/assets/board/*.svg`，`{B|R}T.svg`（陷阱）、`{B|R}E.svg`（兽穴），共 **4 个**（`Trap.tsx:24`、`End.tsx:24`）。

> Flutter 用 `flutter_svg`（`SvgPicture.asset`）直接渲染这 20+4 个 SVG，零额外美术成本。

---

## 4. React 组件 → Flutter widget 映射表

| React (TochuGV) | Flutter 等价 | 说明 |
|---|---|---|
| `<div className="grid grid-cols-7">` 棋盘容器 | `SizedBox(width: cellSize*7, height: cellSize*9)` + `Stack` | Grid 容器→固定尺寸 Stack |
| 子元素 `absolute` + `transform: translate(x*cs, y*cs)` | `Positioned(left: x*cs, top: y*cs, ...)` | 绝对定位一一对应 |
| `useState<Board>` | `StatefulWidget` / riverpod `StateNotifier<Board>` | 状态管理 |
| `onMouseDown={handleClick}` | `GestureDetector(onTapDown: ...)` | 点击坐标→`RenderBox.globalToLocal` |
| `<Image src=svg>` | `SvgPicture.asset('assets/pieces/BR.svg')` | flutter_svg |
| `useCellSize(board, 100)` 自适应 | `LayoutBuilder` + `min(constr.maxWidth/7, ...)` | 响应式格子尺寸 |
| `CellSizeContext` (Context) | `InheritedWidget` 或直接传参 | cellSize 透传 |
| Tailwind `bg-primary-500/700` 交错 | `Color` 按 `(x+y)%2` 选 | 棋盘格色 |
| 合法走法圆点提示 | `Positioned` + `Container(decoration: BoxDecoration(shape: circle))` | 走法高亮 |
| `<Modal>` 胜负弹窗 | `showDialog` / `AlertDialog` | 终局弹窗 |
| `MoveListTable` 棋谱 | `ListView` / `DataTable` | 棋谱展示 |

### 渲染层对应示例（Stack + Positioned）
```dart
// Flutter 等价（示意，非 TochuGV 代码）
SizedBox(
  width: cellSize * board.width, height: cellSize * board.height,
  child: Stack(
    children: [
      // 棋盘格底色
      for (final c in cells) Positioned(left: c.x*cs, top: c.y*cs, ...),
      // 河流/陷阱/兽穴
      for (final w in board.objects.water) Positioned(left: w.x*cs, top: w.y*cs, child: Water()),
      // 棋子
      for (final p in board.pieces) Positioned(
        left: p.position.x*cs, top: p.position.y*cs,
        child: SvgPicture.asset('assets/pieces/${source(p)}.svg'),
      ),
      // 选中高亮 + 合法走法圆点
      if (activeCell != null) ...[
        Positioned(left: activeCell!.x*cs, top: activeCell!.y*cs, child: Highlight()),
        for (final m in possibleMoves) Positioned(left: m.x*cs, top: m.y*cs, child: MoveDot()),
      ],
    ],
  ),
)
```

---

## 5. 自适应格子尺寸（`web/hooks/useCellSize.ts`）

52 行 hook，根据 `board` 尺寸和容器宽度算 `cellSize` 与居中 `margin`。Flutter 对应 `LayoutBuilder`：
```dart
LayoutBuilder(builder: (ctx, c) {
  final cellSize = (c.maxWidth / board.width).floor();
  ...
});
```

---

## 6. 工程结构（Next.js App Router）

- `web/app/game/page.tsx`：游戏主页（本文件）。
- `web/app/{layout,page,register,head}.tsx`：布局/首页/注册/头。
- `web/helpers/game/*.ts`：纯逻辑（见游戏逻辑文档）。
- `web/components/game/*.tsx`：游戏组件（本文件）。
- `web/hooks/useCellSize.ts`：自适应。
- `web/helpers/context.ts`：仅 `CellSizeContext`（`:1-3`）。
- `web/axios/`：API 客户端（仅用户 CRUD，与棋局无关）。
- `api/`：Express + mssql 后端，仅用户管理（不参与棋局逻辑）。
- `database/script.sql`：SQL Server 存储过程（用户相关）。

> **后端与棋局无关**：斗兽棋逻辑全在 `web/` 前端（纯客户端），`api/` 只做用户注册/登录。Flutter 移植可完全忽略 `api/`。

---

## 7. 移植要点

1. **UI 主参考**：React 组件树（`Stack`+`Positioned`）直接译成 Flutter；`getPosibleMoves` 作规则骨架但修正 `_read/.../游戏逻辑/01-...md` §5 的 5 处偏差。
2. **SVG 资源零成本**：20 个棋子 + 4 个地形 SVG 直接复制到 Flutter `assets/`，`flutter_svg` 渲染。
3. **状态管理**：riverpod `StateNotifier<Board>`（仿 fr 项目现有 riverpod 用法），或 `ValueNotifier`。
4. **交互**：`GestureDetector` + `RenderBox.globalToLocal` 把点击像素转格坐标（对应 `page.tsx:32-34`）。
5. **棋谱**：可复用其代数记谱（动物字母+列+行），或简化。
6. **忽略 `api/`**：后端与棋局无关。
