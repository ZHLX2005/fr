# Surround Game UI 层拆分设计 — 单机热座 / 局域网双模式

- **日期**：2026-06-15
- **范围**：`lib/core/surround_game/` 的 **UI 层拆分**（page + view_model + state + event）
- **状态**：已通过 brainstorming 对齐，待用户审阅后进入 writing-plans

---

## 0. 范围与边界（必须先读）

### 0.1 本设计做什么

把 `surround_game` 模块的单机热座 UI 与局域网 UI **彻底拆成两套独立的页面 + ViewModel + 状态机**，共享同一套纯规则引擎与纯展示组件。

### 0.2 本设计不做什么（明确越界清单）

- ❌ LAN 同步协议（推 `GameState` vs 重放 `MoveRecord` history）—— 下一轮
- ❌ `SurroundGameService` 业务实现（`createRoom` / `joinRoom` / `leaveRoom` 的真实逻辑）—— 下一轮
- ❌ `LocalnetService` 启停策略、UDP/HTTP 桥接、TTL —— 下一轮
- ❌ HTTP `/api/game/*` 收发 —— 下一轮
- ❌ 跨机悔棋 / 认输协议 —— 下一轮
- ❌ 断线重连真实实现 —— 下一轮
- ❌ AI 模式、观战模式 —— 未规划
- ❌ `QuoridorEngine` / `models/` 改动 —— 永远不动（共享层）

### 0.3 服务接线策略：A 全部桩化

LAN UI **一个 `SurroundGameService` 方法都不调用**，**不订阅** `roomsStream`，**不调** `localnetService`。所有状态转移为**本地空转**（仅翻 ViewModel 状态值）。唯一允许的副作用是**本地 `Timer.periodic` 倒计时**（无网络、无 service）。

本轮交付 = **纯 UI 骨架 + 状态机形状**。下轮再接业务。

---

## 1. 已对齐的决策

| 决策点 | 选择 |
|---|---|
| 单机模式定义 | **同设备热座**（双人在一台设备轮流操作；现状即此） |
| 拆分颗粒度 | **路由 + ViewModel + 状态机全部独立；Widget 组件层共享** |
| 目录组织 | `lib/core/surround_game/` 下新建 `local/` 与 `lan/` 子目录 |
| 状态机表达 | **sealed class**，ViewModel 内部管理状态转移 |
| 路由方案 | **go_router 命名路由**：`/local/play` 与 `/lan/*` |
| 服务接线 | **A 全部桩化**（见 0.3） |

---

## 2. 三层结构与共享 / 拆分矩阵

### 2.1 三层结构

| 层 | 内容 | 是否随模式分裂 |
|---|---|---|
| **共享层** | `engine/` `models/` `widgets/` `replay/` `board_theme.dart` `surround_game_constants.dart` | 否（不改不动） |
| **模式 A — Local** | `lib/core/surround_game/local/` | 是 |
| **模式 B — LAN** | `lib/core/surround_game/lan/` | 是 |
| **模块导出** | `lib/core/surround_game/surround_game.dart` | 改为按需 re-export |

### 2.2 隔离规则

- `local/*` 不得 import `lan/*`
- `lan/*` 不得 import `local/*`
- 两者只允许 import 共享层

### 2.3 Widget 复用矩阵

| Widget | 共享 / 拆分 | 说明 |
|---|---|---|
| `ChessBoard` / `ChessBoardPainter` | 共享 | 纯展示：`cellSize` `theme` `highlightCellId?` |
| `ChessPlayer` | 共享 | 纯展示：`cellId` `cellSize` `color` |
| `ChessWall` | 共享 | 纯展示 |
| `PlayerPrompt` | 共享 | `validMoves` `cellSize` `theme` `visible` |
| `WallPrompt` | 共享 | 同上 |
| `ConfirmActions` | 共享 | `onConfirm` `onCancel` `theme` |
| `TouchView` | 共享 | `onPointer*` 回调转发 |
| `PlayerPanel` | **下沉为共享组件**（改造） | 行为靠回调注入：`onUndoRequest` / `onExitRequest` / `canRequestUndo` |
| `ReplayController` + `ReplayPage` | 共享 | 无关 mode |
| `RoomListTile` | **移入 `lan/widgets/`** | 局域网专属 |
| `BoardTheme` | 共享 | 视觉令牌 |
| `game_ui_state.dart` | **拆分** | `GameMode`/`TouchPhase` + 触摸态 → `widgets/touch_controller.dart`；UI 状态 → `local/local_ui_state.dart` + `lan/lan_ui_state.dart` |

---

## 3. 目标目录树

```
lib/core/surround_game/
│
├── engine/                              【共享·不动】
│   ├── game_engine.dart
│   └── bfs_pathfinder.dart
│
├── models/                              【共享·不动】
│   ├── game_state.dart
│   ├── game_event.dart
│   ├── game_room.dart
│   └── player_input.dart
│
├── replay/                              【共享·replay_page 移入】
│   ├── replay_controller.dart
│   └── replay_page.dart                 ← 从 pages/ 移入
│
├── widgets/                             【共享·微调】
│   ├── chess_board.dart
│   ├── chess_player.dart
│   ├── chess_wall.dart
│   ├── player_prompt.dart
│   ├── wall_prompt.dart
│   ├── confirm_actions.dart
│   ├── touch_view.dart
│   ├── player_panel.dart                ← 改造为回调注入
│   └── touch_controller.dart            ← 新建（拆自 game_ui_state）
│
├── board_theme.dart                     【共享·不动】
├── surround_game_constants.dart         【共享·不动】
├── surround_game_service.dart           【不动·留位】本轮不碰
│
├── local/                               【★ 新建·单机热座】
│   ├── local_ui_state.dart
│   ├── local_match_state.dart           sealed: Idle / InGame / Finished
│   ├── local_match_event.dart           sealed: Start / Move / Undo / Reset / Exit
│   ├── local_view_model.dart            ValueNotifier<LocalMatchState>
│   ├── local_game_page.dart
│   └── local_lobby_entry.dart
│
├── lan/                                 【★ 新建·局域网】
│   ├── lan_ui_state.dart
│   ├── lan_match_state.dart             sealed: LanHostState + LanClientState
│   ├── lan_match_event.dart             sealed: LanHostEvent + LanClientEvent
│   ├── lan_host_view_model.dart         ValueNotifier<LanHostState>
│   ├── lan_client_view_model.dart       ValueNotifier<LanClientState>
│   ├── lan_lobby_page.dart
│   ├── lan_room_page.dart
│   ├── lan_host_game_page.dart
│   ├── lan_client_game_page.dart
│   └── widgets/
│       └── room_list_tile.dart          ← 从 widgets/ 移入
│
├── surround_game.dart                   【改·模块导出】
└── _legacy/                             【不动】
```

---

## 4. 现存文件去向清单

| 现存文件 | 处理 | 去向 / 说明 |
|---|---|---|
| `engine/*` | 保留 | 共享层不动 |
| `models/*` | 保留 | 共享层不动 |
| `replay/replay_controller.dart` | 保留 | 共享层不动 |
| `pages/replay_page.dart` | **移动** | → `replay/replay_page.dart` |
| `widgets/chess_board.dart` | 保留 | 共享层 |
| `widgets/chess_player.dart` | 保留 | 共享层 |
| `widgets/chess_wall.dart` | 保留 | 共享层 |
| `widgets/player_prompt.dart` | 保留 | 共享层 |
| `widgets/wall_prompt.dart` | 保留 | 共享层 |
| `widgets/confirm_actions.dart` | 保留 | 共享层 |
| `widgets/touch_view.dart` | 保留 | 共享层 |
| `widgets/player_panel.dart` | **改造** | 下沉为共享组件，行为回调注入 |
| `widgets/room_list_tile.dart` | **移动** | → `lan/widgets/room_list_tile.dart` |
| `board_theme.dart` | 保留 | 共享层 |
| `surround_game_constants.dart` | 保留 | 共享层 |
| `surround_game_service.dart` | 保留·不动 | 本轮不碰 |
| `game_ui_state.dart` | **拆分** | → `widgets/touch_controller.dart` + `local/local_ui_state.dart` + `lan/lan_ui_state.dart`；原文件删除 |
| `pages/game_page.dart` | **拆分** | 主体 → `local/local_game_page.dart`；LAN 对局页另建 |
| `pages/game_lobby_page.dart` | **拆分** | "本地对局" → `local/local_lobby_entry.dart`；"创建/加入房间" → `lan/lan_lobby_page.dart` |
| `pages/game_room_page.dart` | **移动+改造** | → `lan/lan_room_page.dart`；移除 `_countdownTimer` 死代码；按 sealed 状态机重写 |
| `surround_game.dart` | **改** | re-export 共享 + local/lan 的 Page + replay_page |
| `_legacy/**` | 不动 | — |

---

## 5. 状态机形状

### 5.1 Local（单机热座）— 3 状态

```dart
sealed class LocalMatchState {
  const LocalMatchState();
}
class LocalIdle extends LocalMatchState {
  const LocalIdle();
}
class LocalInGame extends LocalMatchState {
  const LocalInGame(this.gameState);
  final GameState gameState;
}
class LocalFinished extends LocalMatchState {
  const LocalFinished(this.finalState, this.result);
  final GameState finalState;
  final GameResult result;   // topWin / bottomWin / draw
}
```

### 5.2 LAN Host — 6 状态

```dart
sealed class LanHostState {
  const LanHostState();
}
class HostLobby extends LanHostState {
  const HostLobby();
}
class HostWaiting extends LanHostState {
  const HostWaiting(this.room);
  final GameRoom room;
}
class HostCountdown extends LanHostState {
  const HostCountdown(this.room, this.secondsLeft);
  final GameRoom room;
  final int secondsLeft;
}
class HostInGame extends LanHostState {
  const HostInGame(this.gameState, this.room);
  final GameState gameState;
  final GameRoom room;
}
class HostFinished extends LanHostState {
  const HostFinished(this.finalState, this.room, this.result);
  final GameState finalState;
  final GameRoom room;
  final GameResult result;
}
class HostError extends LanHostState {
  const HostError(this.message, {this.previous});
  final String message;
  final LanHostState? previous;
}
```

### 5.3 LAN Client — 7 状态

```dart
sealed class LanClientState {
  const LanClientState();
}
class ClientIdle extends LanClientState {
  const ClientIdle();
}
class ClientJoining extends LanClientState {
  const ClientJoining(this.targetRoom);
  final GameRoom targetRoom;
}
class ClientWaiting extends LanClientState {
  const ClientWaiting(this.room);
  final GameRoom room;
}
class ClientCountdown extends LanClientState {
  const ClientCountdown(this.room, this.secondsLeft);
  final GameRoom room;
  final int secondsLeft;
}
class ClientInGame extends LanClientState {
  const ClientInGame(this.gameState, this.room);
  final GameState gameState;
  final GameRoom room;
}
class ClientFinished extends LanClientState {
  const ClientFinished(this.finalState, this.room, this.result);
  final GameState finalState;
  final GameRoom room;
  final GameResult result;
}
class ClientDisconnected extends LanClientState {
  const ClientDisconnected({this.canReconnect = true});
  final bool canReconnect;
}
```

> **关键**：`LocalMatchState` / `LanHostState` / `LanClientState` 三个状态机类型**互不引用**。共享的只是 `GameState` / `GameRoom` / `GameResult` 值对象。

### 5.4 事件形状（sealed class）

```dart
// local/local_match_event.dart
sealed class LocalMatchEvent { const LocalMatchEvent(); }
class LocalStartPressed extends LocalMatchEvent { const LocalStartPressed(); }
class LocalMoveCommitted extends LocalMatchEvent {
  const LocalMoveCommitted(this.input);
  final PlayerInput input;
}
class LocalUndoRequested extends LocalMatchEvent { const LocalUndoRequested(); }
class LocalResetRequested extends LocalMatchEvent { const LocalResetRequested(); }
class LocalExitRequested extends LocalMatchEvent { const LocalExitRequested(); }
```

```dart
// lan/lan_match_event.dart
sealed class LanHostEvent { const LanHostEvent(); }
class HostCreateRoomPressed extends LanHostEvent { const HostCreateRoomPressed(); }
class HostStartGamePressed extends LanHostEvent { const HostStartGamePressed(); }
class HostClientJoined extends LanHostEvent { const HostClientJoined(this.clientId, this.clientName); final String clientId; final String clientName; }
class HostClientLeft extends LanHostEvent { const HostClientLeft(); }
class HostMoveReceived extends LanHostEvent { const HostMoveReceived(this.input); final PlayerInput input; }
class HostMoveCommitted extends LanHostEvent { const HostMoveCommitted(this.input); final PlayerInput input; }
class HostTick extends LanHostEvent { const HostTick(); }
class HostAbortGame extends LanHostEvent { const HostAbortGame(); }
class HostRetryPressed extends LanHostEvent { const HostRetryPressed(); }
class HostExitRequested extends LanHostEvent { const HostExitRequested(); }

sealed class LanClientEvent { const LanClientEvent(); }
class ClientJoinPressed extends LanClientEvent { const ClientJoinPressed(this.room); final GameRoom room; }
class ClientJoinAccepted extends LanClientEvent { const ClientJoinAccepted(this.room); final GameRoom room; }
class ClientJoinRejected extends LanClientEvent { const ClientJoinRejected(this.reason); final String reason; }
class HostStartedCountdown extends LanClientEvent { const HostStartedCountdown(this.secondsLeft); final int secondsLeft; }
class ClientTick extends LanClientEvent { const ClientTick(); }
class ClientMoveCommitted extends LanClientEvent { const ClientMoveCommitted(this.input); final PlayerInput input; }
class HostStatePushed extends LanClientEvent { const HostStatePushed(this.gameState); final GameState gameState; }
class HostAborted extends LanHostEvent { const HostAborted(); }
class ClientReconnectPressed extends LanClientEvent { const ClientReconnectPressed(); }
class ClientExitRequested extends LanClientEvent { const ClientExitRequested(); }
```

> 事件类**仅描述"用户/外部想干什么"**；状态机转移逻辑放在 ViewModel 的 `reduce` 内部。

---

## 6. ViewModel 设计

### 6.1 通用骨架

```dart
abstract base class _MatchViewModel<S> extends ValueNotifier<S> {
  _MatchViewModel(S initial) : super(initial);

  /// Page 唯一入口：把事件喂给状态机
  void dispatch(SealedEvent event) {
    final next = reduce(value, event);   // 纯函数：state × event → state
    if (!identical(next, value)) {
      value = next;                       // ValueNotifier 自动通知
    }
  }

  /// 子类实现：每个 mode 自己的转移表
  S reduce(S state, SealedEvent event);

  @override
  void dispose() {
    // 本轮无 stream subscription；下轮接 service 时在此 dispose
    super.dispose();
  }
}
```

**约束**：
- `dispatch` 是 Page 的唯一入口；Page **不直接写** `value`
- `reduce` 是纯函数，便于单测
- 副作用（调 service）本轮全部省略；下轮在 `dispatch` 包一层 `await _performSideEffects(...)`
- `identical` 守卫避免无变化的 rebuild

### 6.2 Local 转移表

| From | Event | → To | 副作用 |
|---|---|---|---|
| `LocalIdle` | `LocalStartPressed` | `LocalInGame(GameState.initial())` | 无 |
| `LocalInGame` | `LocalMoveCommitted(input)` | `LocalInGame(applyMove)` 或 `LocalFinished`（若终局） | 无（纯引擎） |
| `LocalInGame` | `LocalUndoRequested` | `LocalInGame(undoLast)`；空历史时不变 | 无 |
| `LocalInGame` | `LocalResetRequested` | `LocalInGame(GameState.initial())` | 无 |
| `LocalFinished` | `LocalResetRequested` | `LocalInGame(GameState.initial())` | 无 |
| `LocalFinished` | `LocalExitRequested` | 页面 pop（不更状态） | 无 |
| 任意 | 不适用事件 | 保持原状态 | 无 |

```dart
final class LocalViewModel extends _MatchViewModel<LocalMatchState> {
  LocalViewModel() : super(const LocalIdle());

  @override
  LocalMatchState reduce(LocalMatchState s, LocalMatchEvent e) {
    return switch (e) {
      LocalStartPressed()              when s is LocalIdle     => LocalInGame(GameState.initial()),
      LocalMoveCommitted(:final input) when s is LocalInGame   => _applyAndCheck(s, input),
      LocalUndoRequested()             when s is LocalInGame   => LocalInGame(QuoridorEngine.undoLast(s.gameState)),
      LocalResetRequested()            when s is LocalInGame   => LocalInGame(GameState.initial()),
      LocalResetRequested()            when s is LocalFinished => LocalInGame(GameState.initial()),
      _ => s,
    };
  }

  LocalMatchState _applyAndCheck(LocalInGame s, PlayerInput input) {
    final next = QuoridorEngine.applyMove(s.gameState, input);
    if (next.status == GameStatus.running) return LocalInGame(next);
    return LocalFinished(next, _resultOf(next));
  }
}
```

### 6.3 LAN Host 转移表

| From | Event | → To | 副作用 |
|---|---|---|---|
| `HostLobby` | `HostCreateRoomPressed` | `HostWaiting(GameRoom.placeholder())` | 【桩】`createRoom` 不调 |
| `HostWaiting` | `HostClientJoined` | `HostWaiting(room.copyWith(clientId, clientName))` | 【桩】HTTP join 收到 |
| `HostWaiting` | `HostStartGamePressed` | `HostCountdown(room, 3)` + 启动本地 Timer | 本地 `Timer.periodic`（允许） |
| `HostCountdown` | `HostTick` | `s>1 ? HostCountdown(s-1) : HostInGame(initial, room)` | Timer 继续/取消 |
| `HostInGame` | `HostMoveReceived(input)` | `HostInGame(applyMove + 检查终局)` | 【桩】HTTP input 收到 |
| `HostInGame` | `HostMoveCommitted(input)` | 同上 | 【桩】主机自落子 |
| `HostInGame` | `HostAbortGame` | `HostLobby()` | 【桩】通知客户端，不调 |
| 任意 host 态 | `HostError` 触发 | `HostError(msg, previous: current)` | — |
| `HostError` | `HostRetryPressed` | `value.previous ?? HostLobby()` | — |
| `HostFinished` | `HostExitRequested` | 页面 pop | — |

### 6.4 LAN Client 转移表

| From | Event | → To | 副作用 |
|---|---|---|---|
| `ClientIdle` | `ClientJoinPressed(room)` | `ClientJoining(room)` | 【桩】HTTP join 不发 |
| `ClientJoining` | `ClientJoinAccepted(room)` | `ClientWaiting(room)` | 【桩】主机 ack |
| `ClientJoining` | `ClientJoinRejected(reason)` | `ClientIdle()` + 错误提示 | 【桩】主机 nack |
| `ClientWaiting` | `HostStartedCountdown(s)` | `ClientCountdown(room, s)` + 启动本地 Timer | 本地 `Timer.periodic`（允许） |
| `ClientCountdown` | `ClientTick` | `s>1 ? ClientCountdown(s-1) : ClientInGame(initial, room)` | Timer 继续/取消 |
| `ClientInGame` | `ClientMoveCommitted(input)` | `ClientInGame(applyMove + 检查终局)` | 【桩】`sendInputToHost` 不调 |
| `ClientInGame` | `HostStatePushed(gameState)` | `ClientInGame(gameState)` | 【桩】主机推状态 |
| `ClientInGame` | `HostAborted` / 超时 | `ClientDisconnected(canReconnect: false)` | 【桩】 |
| `ClientInGame` | 终局 | `ClientFinished(...)` | — |
| `ClientDisconnected` | `ClientReconnectPressed` | `ClientIdle()` | 【桩】重连不调 |

### 6.5 错误处理（仅 UI 层）

- **Local**：无外部依赖；`LocalUndoRequested` 在无可悔步时引擎返回原状态，ViewModel 不进错误态，UI 静默（按钮禁用）。
- **LAN Host/Client**：错误态独立成 `HostError` / `ClientDisconnected`。
  - `HostError` 携带 `previous` → 支持"错误→重试→回到出错上下文"
  - `ClientDisconnected` 携带 `canReconnect` → UI 决定显示"重连"还是"返回大厅"
  - 本轮这些错误态只在状态机声明 + 转移表列出；真实触发源（HTTP 失败、socket 断开）下轮接 service 时再连。本轮若需演示，可加开发者按钮手动 `dispatch`，默认路径不进入错误态。

---

## 7. 路由表（go_router）

| 路径 | Page | 触发场景 | 入参 |
|---|---|---|---|
| `/` | 应用首页（现状保留） | — | — |
| `/local/play` | `LocalGamePage` | 用户点"本地对局" | 无 |
| `/lan/lobby` | `LanLobbyPage` | 用户点"局域网对局" | 无 |
| `/lan/room/:roomId` | `LanRoomPage` | 创建房间后 / 点击房间列表项 | `roomId` |
| `/lan/host/play/:roomId` | `LanHostGamePage` | 主机倒计时结束 | `roomId` |
| `/lan/client/play/:roomId` | `LanClientGamePage` | 客户端倒计时结束 | `roomId` |
| `/replay` | `ReplayPage` | 终局点"复盘" | `extra: List<MoveRecord>` |

### 7.1 设计要点

- **`roomId` 走路径参数，不传 `GameRoom` 对象**。`LanRoomPage` 收到 `roomId` 后，本轮用 `GameRoom.placeholder(roomId:)` 构造占位房间；下轮改为查 `surroundGameService.rooms`。
- **`/replay` 用 `extra` 传 `List<MoveRecord>`**，与现有 `ReplayPage(history: ...)` 一致。
- **`LanRoomPage` 本轮用入参 `LanRole { host, client }` 区分身份**，不查 service。下轮身份由 `surroundGameService.isHost` 决定。

### 7.2 导航流程图

```
应用首页
  │
  ├──► [本地对局] ──► /local/play  (LocalGamePage)
  │                    ├─ Idle → InGame → Finished
  │                    └─ Finished → /replay (extra: history)
  │
  └──► [局域网对局] ──► /lan/lobby  (LanLobbyPage)
                        │
                        ├─ [创建房间] ──► /lan/room/:id  (LanRoomPage·host)
                        │                  ├─ HostWaiting → HostCountdown
                        │                  └─ 倒计时完 ──► /lan/host/play/:id
                        │
                        └─ [点房间项] ──► /lan/room/:id  (LanRoomPage·client)
                                          ├─ ClientWaiting → ClientCountdown
                                          └─ 倒计时完 ──► /lan/client/play/:id
```

---

## 8. Widget 接线细节

### 8.1 `PlayerPanel` 改造为回调注入

**现状**：直接依赖 `GameController`，`onUndoRequest: VoidCallback?` 已是可空回调。

**改造后**：不再 import 任何 mode 的 ViewModel，行为全走回调：

```dart
class PlayerPanel extends StatelessWidget {
  const PlayerPanel({
    required this.cellSize,
    required this.theme,
    required this.active,
    required this.isTop,
    required this.rotated,
    required this.playerId,
    required this.wallsRemaining,
    this.canRequestUndo = false,
    this.onUndoRequest,
    this.onExitRequest,
    this.onForfeitRequest,
    super.key,
  });

  final double cellSize;
  final BoardThemeData theme;
  final bool active;
  final bool isTop;
  final bool rotated;
  final String playerId;
  final int wallsRemaining;
  final bool canRequestUndo;
  final VoidCallback? onUndoRequest;
  final VoidCallback? onExitRequest;
  final VoidCallback? onForfeitRequest;
}
```

**各 mode 注入**：

| Mode | `onUndoRequest` | `onExitRequest` | `canRequestUndo` |
|---|---|---|---|
| Local | `() => vm.dispatch(LocalUndoRequested())` | `() => Navigator.pop` | `history.length > 0` |
| LAN Host | `() => vm.dispatch(HostUndoRequested())` | `() => vm.dispatch(HostAbortGame())` | 本轮恒 `false` |
| LAN Client | `() => vm.dispatch(ClientUndoRequested())` | `() => vm.dispatch(ClientExitRequested())` | 本轮恒 `false` |

### 8.2 `ChessBoard` / `ChessPlayer` / `ChessWall` / `PlayerPrompt` / `WallPrompt` / `ConfirmActions` / `TouchView`

保持现状（已是纯展示组件）。各 mode 的 Page 从 ViewModel 的 `GameState` 提取 `highlightCellId` / `validMoves` 等喂给这些组件；`TouchView.onPointer*` 路由到 mode 自己的触摸态处理（`LocalUiState` / `LanUiState`）。

### 8.3 `RoomListTile`

移入 `lan/widgets/room_list_tile.dart`。本轮 A 桩化下房间列表数据源为空，`LanLobbyPage` 渲染"暂无房间"占位 + "创建房间"按钮。组件本身保留完整实现，等下轮接 `roomsStream` 直接喂数据。

### 8.4 `game_ui_state.dart` 拆分

- `GameMode` / `TouchPhase` enum + 触摸态逻辑 → **`widgets/touch_controller.dart`**（新建，纯触摸状态机，与 mode 无关）
- `local/local_ui_state.dart`：`LocalUiState`（持有 `GameState` + 引用 `TouchController`）
- `lan/lan_ui_state.dart`：`LanUiState`（同上，多一个"等待对方"禁用标志）
- 原 `game_ui_state.dart` **删除**

---

## 9. Page 接线方式

```dart
class LocalGamePage extends StatefulWidget { ... }

class _LocalGamePageState extends State<LocalGamePage> {
  late final LocalViewModel _vm = LocalViewModel();

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LocalMatchState>(
      valueListenable: _vm,
      builder: (_, state, __) {
        return switch (state) {
          LocalIdle()     => _IdleView(onStart: () => _vm.dispatch(const LocalStartPressed())),
          LocalInGame()   => _InGameView(state: state, vm: _vm),
          LocalFinished() => _FinishedView(state: state, onReset: () => _vm.dispatch(const LocalResetRequested())),
        };
      },
    );
  }
}
```

- Page **零** `setState`；所有重建来自 `ValueListenableBuilder`
- `_InGameView` 内部再用 `ValueListenableBuilder<LocalUiState>`（触摸态）驱动 `ChessBoard` / `PlayerPrompt` / `TouchView`
- LAN 三个 Page（lobby / room / host_game / client_game）同构，仅 state 类型不同

---

## 10. 副作用白名单（本轮边界）

| 操作 | 本轮允许？ | 理由 |
|---|---|---|
| `QuoridorEngine.applyMove` / `undoLast` / `replayHistory` | ✅ | 纯函数，引擎是共享层 |
| `Timer.periodic`（倒计时） | ✅ | 纯本地计时，无网络无 service |
| `Navigator.push/pop`（路由） | ✅ | UI 层职责 |
| `ValueNotifier.value =` | ✅ | ViewModel 内部 |
| 订阅 `surroundGameService.roomsStream` | ❌ | A 桩化 |
| 调 `surroundGameService.createRoom/joinRoom/leaveRoom` | ❌ | A 桩化 |
| HTTP `/api/game/*` 收发 | ❌ | A 桩化 |
| `localnetService.start/stop` | ❌ | A 桩化 |
| 写 `SharedPreferences` / Hive 持久化 | ❌ | 不在本轮 |

---

## 11. 测试策略

### 11.1 状态机单测（核心，必做）

`reduce(state, event)` 是纯函数，每个 mode 一组，覆盖每条转移表：

- Local：`Idle+Start→InGame`、`InGame+Move→InGame/Finished`、`InGame+Undo(空历史)→不变`、`InGame→Finished`、`Finished+Reset→InGame`、`Idle+未知事件→不变`
- LAN Host：`Lobby+Create→Waiting`、`Waiting+ClientJoined→Waiting(copyWith)`、`Waiting+Start→Countdown`、`Countdown+Tick→递减/进 InGame`、`InGame+Move→InGame/Finished`、`任意+Error→HostError(previous)`、`Error+Retry→previous/Lobby`
- LAN Client：`Idle+Join→Joining`、`Joining+Accepted→Waiting`、`Joining+Rejected→Idle`、`Waiting+StartedCountdown→Countdown`、`Countdown+Tick→递减/进 InGame`、`InGame+MoveCommitted→InGame/Finished`、`InGame+HostStatePushed→InGame`、`InGame+HostAborted→Disconnected`、`Disconnected+Reconnect→Idle`

### 11.2 Widget 渲染契约测（建议做）

`flutter test` 的 `pumpWidget`：
- `LocalGamePage` 在 `LocalIdle` 渲染"开始"按钮
- `LocalGamePage` 在 `LocalFinished` 渲染胜利覆盖层 + "重新开始"
- `PlayerPanel` 改造后，`active: true` + `canRequestUndo: true` 时悔棋按钮可见可点
- `LanLobbyPage` 本轮渲染"暂无房间"占位（A 桩化）

### 11.3 不测的内容

- ❌ 网络同步（A 桩化，无网络）
- ❌ `SurroundGameService` / `LocalnetService` 行为（本轮不动）
- ❌ 引擎正确性（共享层，已有/应有自己的测试）

### 11.4 测试目录结构

```
test/core/surround_game/
├── local/
│   ├── local_view_model_test.dart
│   └── local_game_page_test.dart
├── lan/
│   ├── lan_host_view_model_test.dart
│   ├── lan_client_view_model_test.dart
│   ├── lan_lobby_page_test.dart
│   └── lan_room_page_test.dart
└── shared/
    ├── touch_controller_test.dart
    └── player_panel_test.dart
```

---

## 12. 迁移与回滚策略

### 12.1 迁移顺序

1. 共享层不动（`engine/models/widgets/replay` 零改动，除 `PlayerPanel` 改造与 `game_ui_state` 拆分）
2. 建 `local/`，把现有 `GamePage` 逻辑搬进 `LocalGamePage`，确保单机热座功能不回归
3. 建 `lan/` 骨架（状态机 + Page，全桩化），与 `local/` 并存
4. 改路由表，让入口按钮指向新路径
5. 删除旧 `pages/` 目录（`game_page.dart` / `game_lobby_page.dart` / `game_room_page.dart`）

### 12.2 回滚

每步独立 commit；若回归，`git revert` 单个 commit。

### 12.3 关键里程碑

- 单机热座功能不回归（步骤 2 完成后手动验证）
- LAN 骨架编译通过、状态机单测全绿（步骤 3 完成后）

---

## 13. 开放问题（留给下一轮 brainstorm）

1. LAN 同步协议：主机推 `GameState` vs 双方重放 `MoveRecord` history
2. `SurroundGameService` 业务实现（createRoom / joinRoom / leaveRoom 真实逻辑）
3. `LocalnetService` 启停策略与 lobby 页面的归属
4. 跨机悔棋 / 认输协议
5. 断线重连真实实现
6. `GameRoom.state` 仍用 `@Deprecated` 的 `RoomState` enum，下轮清理前需定方案
