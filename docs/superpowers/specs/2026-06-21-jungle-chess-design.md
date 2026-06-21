# 斗兽棋 (Jungle Chess) Demo — 设计文档

## 概述

在 `fr` 项目中实现斗兽棋 (Dou Shou Qi / Jungle Chess) 双人对战 Demo，支持本地热座模式和局域网对战模式。无 AI。

## 架构

### 总体分层（3 层）

```
Engine（纯函数层）     →  Models（不可变数据层）   →  ViewModel + Widgets（状态/UI 层）
JungleEngine           GameState/Piece/Move        LocalViewModel / LanHostViewModel / 棋盘组件
```

### 文件树

```
lib/core/jungle_chess/
├── jungle_chess.dart                  # barrel export
│
├── constants/
│   └── jungle_constants.dart          # 棋盘尺寸、地形坐标、颜色、动画时长
│
├── engine/
│   └── jungle_engine.dart             # 纯函数引擎：初始化、走子、吃子、跳河、胜负判定
│
├── models/
│   ├── game_state.dart                # 不可变 GameState（棋盘 + 棋子 + 回合 + 历史）
│   ├── piece.dart                     # 棋子（Animal 枚举、颜色、等级、位置）
│   └── move.dart                      # 走法记录（from → to，吃子、特殊标注）
│
├── local/
│   ├── local_match_state.dart         # sealed: LocalIdle | LocalInGame | LocalFinished
│   ├── local_match_event.dart         # sealed: StartPressed | MoveCommitted | Undo | Reset | Exit
│   └── local_view_model.dart          # ValueNotifier<LocalMatchState> + reduce()
│
├── lan/
│   ├── game_room.dart                 # GameRoom 模型
│   ├── lan_match_state.dart           # sealed LanHostState + LanClientState
│   ├── lan_match_event.dart           # sealed LanHostEvent + LanClientEvent
│   ├── lan_host_view_model.dart       # Host 端 lobby 状态机
│   ├── lan_client_view_model.dart     # Client 端 lobby 状态机
│   ├── lan_host_protocol_bridge.dart  # 纯函数: LanRoomEvent → LanHostState
│   ├── lan_client_protocol_bridge.dart# 纯函数: LanRoomEvent → LanClientState
│   ├── protocol/
│   │   ├── lan_channels.dart          # channel 常量
│   │   └── lan_messages.dart          # LanRoomEvent sealed class + JSON
│   ├── serializer/
│   │   └── game_state_serializer.dart # GameState ↔ JSON
│   └── service/
│       └── lan_service_adapter.dart   # 适配 localnet 框架的单例桥
│
└── widgets/
    ├── jungle_board.dart              # 棋盘渲染（CustomPainter + SVG）
    ├── jungle_piece.dart              # 棋子渲染（SvgPicture.asset）
    ├── jungle_touch_controller.dart   # 触摸状态机
    └── jungle_dialog.dart             # 胜负/退出弹窗
```

**Lab Demo 入口**（1 文件）：
```
lib/lab/demos/jungle_chess_demo.dart
```

## Engine 层

### 棋盘

- 9 行 × 7 列 = 63 格，1D index = row × 7 + col
- Row 0 = 蓝方阵地，Row 8 = 红方阵地
- 蓝方兽穴 (0,3)，红方兽穴 (8,3)
- 蓝方陷阱 (0,2)(0,4)(1,3)，红方陷阱 (8,2)(8,4)(7,3)
- 河流左：(3-5,1-2) 共 6 格；河流右：(3-5,4-5) 共 6 格

### 棋子

| 动物 | 等级 | 代码 |
|------|------|------|
| 鼠 (Rat) | 1 | R |
| 猫 (Cat) | 2 | C |
| 狗 (Dog) | 3 | D |
| 狼 (Wolf) | 4 | W |
| 豹 (Leopard) | 5 | H |
| 虎 (Tiger) | 6 | T |
| 狮 (Lion) | 7 | L |
| 象 (Elephant) | 8 | E |

双方各 8 枚，共 16 枚。蓝方 (B) 先手，红方 (R) 后手。

### 规则

| 规则 | 处理 |
|------|------|
| 走子 | 上下左右 1 步（河内鼠也是 4 方向 1 步） |
| 吃子 | `attacker.rank >= defender.rank`，同级可互吃 |
| 鼠→象 | 鼠可吃象（特例），象不可吃鼠（除非鼠在对方陷阱中） |
| 水中鼠 | 在水中不能被陆地上的棋子吃，也不能吃陆地上的棋子 |
| 陷阱 | 对方棋子踏入陷阱后 rank 降为 0，可被任何棋子吃 |
| 兽穴 | 己方兽穴不能进入；进入对方兽穴即获胜 |
| 狮虎跳河 | 纵向跨 3 格(row 2↔6)，横向跨 2 格(col 0↔3 或 3↔6)，中间有鼠则阻挡 |
| 胜利 | 进对方兽穴 / 吃光对方所有棋子 / 对方无子可走 |
| 和棋 | 连续 150 回合未分胜负（300 步） |

### 引擎设计

```dart
abstract final class JungleEngine {
  static GameState createInitialState();
  static GameState? movePiece(GameState state, Coord from, Coord to);
  static List<Coord> getValidMoves(GameState state, Coord pos);
  static bool canCapture(Piece attacker, Piece defender);
  static List<Coord> getRiverJumps(GameState state, Piece piece);
  static ({bool isOver, PlayerColor? winner, String? reason}) checkGameEnd(GameState state);
}
```

- 所有方法为 `static` 纯函数
- 非法操作返回 `null`（调用方据此判断是否合法）
- 无任何 Flutter 或网络依赖，可单独单元测试

## 数据模型

### GameState（不可变）

```dart
final class GameState {
  final Map<Coord, Piece> pieces;      // 存活棋子
  final PlayerColor currentTurn;       // 当前走子方
  final List<Move> history;            // 走棋历史
  final int roundCount;                // 对局轮数
  final bool isOver;                   // 是否结束
  final PlayerColor? winner;           // 胜者
  final String? gameOverReason;        // 结束原因
}
```

- 每次走子通过 `copyWith` 生成新实例
- `history` 用于悔棋和和棋判定

## Local 模式

### 状态机

```
LocalIdle  ──StartPressed──→  LocalInGame(gameState, currentPlayerIndex=0)
                                  │
                              ┌───┴───┐
                              │       │
                          MoveCommitted  UndoRequested
                              │       │
                              v       v
                          LocalInGame(new) / LocalFinished
                                  │
                              ResetRequested / ExitRequested
                                  │
                                  v
                              LocalIdle
```

### ViewModel

```dart
final class LocalViewModel extends ValueNotifier<LocalMatchState> {
  void dispatch(LocalMatchEvent event);     // 入口
  static LocalMatchState reduce(LocalMatchState state, LocalMatchEvent event);  // 纯函数
}
```

- `reduce()` 是纯函数 —— 不调 setState、不发网络、不读时间
- `identical(next, value)` 避免不必要的通知
- 引擎返回 null 时保持原状态（非法操作直接被忽略）

### 触摸交互

```
idle → 点击己方棋子 → 选中 + 高亮合法目标 → 点击目标格 → dispatch(MoveCommitted)
                                                 ↓ 点击己方另一棋子 → 切换选中
                                                 ↓ 点击非法位置 → 取消选中
```

## LAN 模式

### 架构

```
Page → ViewModel (lobby) → ProtocolBridge → LanServiceAdapter → localnet
Page → ValueNotifier<GameState> + Session (ingame)
```

### 房间生命周期

```
Host:   Lobby → Waiting(client) → Countdown(3s) → InGame → Finished
Client: Idle → Joining → Waiting → Countdown(3s) → InGame → Finished
```

- **Lobby 阶段**：Host 用 `LanHostViewModel`，Client 用 `LanClientViewModel`
- **InGame 阶段**：切换到 `ValueNotifier<GameState>` + Session 同步

### 协议

| Channel | 传输 | 用途 |
|---------|------|------|
| `jungle/room/announce` | UDP 周期广播 | Host 宣告房间存在（3s 间隔） |
| `jungle/room/join` | UDP 多播 | Client 请求加入 |
| `jungle/game/state` | HTTP Session | GameState 双向同步 |

### 游戏中同步

- Host 权威执行所有 `JungleEngine.movePiece()` 调用
- `ValueNotifier<GameState>` 变化自动触发 Session 序列化推送给 Client
- Client 只接收不执行，通过 `gameStateNotifier.value = rebuilt` 更新 UI
- Host 翻转棋盘，触摸坐标通过 `LanHostTouchController` Y 镜像

### LAN 适配器

```dart
class LanServiceAdapter {
  static final instance = LanServiceAdapter._();
  Future<void> start({required String myAlias});
  Future<void> stop();

  Stream<GameRoom> watchRooms();       // 房间列表
  Future<void> announceRoom(GameRoom room);
  Future<void> sendJoinRequest(String hostId, String alias);
  Future<void> sendJoinResult(String clientId, bool accepted);

  Session<ValueNotifier<GameState>> createGameSession({
    required String peerId,
    required ValueNotifier<GameState> state,
  });

  Stream<LanRoomEvent> watchRoomEvents();
}
```

## Widgets

### 棋盘 (JungleBoard)

- `CustomPainter` 绘制网格线 + 河流 + 兽穴/陷阱背景色
- `SvgPicture.asset` 叠加兽穴、陷阱标记（`den.svg`、`trap.svg`）
- `Stack` + `Positioned` 布局（与 TochuGV 的 CSS `transform: translate` 等价）
- `SvgPicture.asset` 渲染棋子（`assets/animal/{B|R}{C,D,E,H,L,R,T,W}.svg`）

### 触摸控制器 (JungleTouchController)

- 纯触摸状态机，与 `surround_game/widgets/touch_controller.dart` 模式一致
- 三阶段：idle → selected → confirmed
- LAN Host 端使用 `LanHostTouchController`（Y 坐标镜像）

### 弹窗 (JungleDialog)

- 胜负弹窗：显示胜者、原因，"再来一局" / "退出"
- 退出确认弹窗
- LAN 断线弹窗

## 页面导航

```
Lab Demo 入口 (jungle_chess_demo.dart)
    │
    ├── "本地对战" → LocalGamePage
    │                  ├── 棋盘组件（JungleBoard + JunglePiece）
    │                  ├── 回合指示器
    │                  ├── 悔棋按钮（>0 步可悔）
    │                  ├── 重新开始按钮
    │                  └── 退出确认弹窗
    │
    └── "局域网对战" → LanLobbyPage
                        ├── 昵称输入
                        ├── "创建房间" → LanHostRoomPage → 倒计时 → LanHostGamePage
                        └── 房间列表 → 点击加入 → LanClientRoomPage → 倒计时 → LanClientGamePage
```

### Lab Demo 入口规范

遵循 `fr` 项目规范：
- 使用 `buildPage(BuildContext)` 模式
- 不创建多余的返回按钮（由 `DemoPage` 提供）
- 入口在 `demo` 分组下

## 不包含的范围（显式排除）

- AI（任何形式的电脑对手）
- 计时器 / 读秒
- 在线匹配（仅局域网）
- 游戏房间历史 / 棋谱存档
- 重播功能
- 动画效果（首版不做）

## 资产

- 棋子 SVG：`assets/animal/{B|R}{C,D,E,H,L,R,T,W}.svg`（16 文件，已存在）
- 棋盘标记：`assets/animal/trap.svg`、`assets/animal/den.svg`（2 文件，已存在）
- 无需额外图片或字体资源

## 关键约束

1. 所有 Engine 方法为纯函数，无副作用
2. ViewModel reduce() 为纯函数
3. Host 是权威端，所有走子操作在 Host 执行
4. SVG 渲染依赖 `flutter_svg` 包
5. LAN 复用项目现有的 `localnet` 框架（`lib/core/localnet/`）

## 自检清单

- [x] 无 TBD 或 TODO 占位符
- [x] 架构与 feature 描述一致
- [x] 范围聚焦，无过大或分散
- [x] 每项需求无歧义
- [x] 显式排除了 AI 和非目标功能
