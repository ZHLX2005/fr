# PR: LAN 模式升级双端 Session 同步

## 概要

把上一轮「双端手动 sendGameState + watchGameState」状态同步升级为「双端 Session 自动同步」。删除冗余手动 bridge 代码，利用 `lib/core/localnet/session/` 框架层能力。

## 背景

上一轮 LAN 接入实现了"双端手动 sendGameState + watchGameState"路径。调试中发现：
1. **状态回退**：Host 收到 Client game_state 时只更新 notifier，不更新 VM → Host 再次 dispatch 时用旧 VM state 算 next → 丢弃 Client 走子
2. **手动同步冗余**：sendGameState / watchGameState / HostGameStatePushed / ClientGameStatePushed 四层手动桥接代码量大且易出错
3. **Session 层未被利用**：`lib/core/localnet/session/` 有完整的 Session 自动同步能力，spec 第 4 节原设计就是用 Session

## 改动

### framework（`lib/core/localnet/`）
- `Session` / `SessionManager` / `LanFramework.createSession` 加可选 `channelName` 参数（向后兼容）
- 不传 channelName 时使用默认 `session/${peerId}_${state.hashCode}` 命名

### surround_game/lan
- `LanHostGamePage` / `LanClientGamePage` 双端各创 `Session<ValueNotifier<GameState>>`，共享 channel `surround/game/state`
- GamePage 不再持有 VM 状态机；落子直接调 QuoridorEngine 算 next → notifier → Session 自动发
- GamePage 自己处理 deviceLost（订阅 watchDevices）
- 删除：sendGameState / watchGameState / HostGameStatePushed / ClientGameStatePushed / GamePage VM fast-forward / 旧 deviceLost 测试

### adapter（`lan_service_adapter.dart`）
- `createGameSession` 加 `channelName` 可选参数透传到 framework
- 删除 `_gameStateCtrl` / `_gameStateStreams` / `key == 'game_state'` 多播分支

## 验证

- `flutter analyze lib/core/surround_game/lan/`：**0 errors**
- `flutter test`：**22/22 通过**（比上一轮 -3：删 2 死代码 + 1 deviceLost VM 测试，新增 1 Session 契约测试 + 1 LanBoardStack widget 测试）
- 跨进程手动 demo：Host 落子 → Client 同步 → Client 落子 → Host 同步 → 多步不回退（待用户验证）

## 范围

### 做
- Session channelName 改造（向后兼容）
- 双端 GamePage Session 同步
- GamePage deviceLost 检测
- 旧手动 sync 代码清理
- LanBoardStack 行为 widget 测试归档

### 不做（YAGNI）
- Session 失败重连机制
- 增量 GameState 同步（仍走全量）
- 跨进程自动化集成测试（framework 单例约束）

## 风险

- GamePage 不再持有 VM，但 LanRoomPage 仍持有 VM（处理 join/leave 状态）
- `LanChannels.gameState` 常量保留（Session channelName 用），但 HTTP channel 用途删除
- `_buildVictoryOverlay` 被删除（玩家获胜/失败时无弹窗提示）— 后续轮次补回

## Follow-up

- GamePage deviceLost UX 提升：当前 AlertDialog + 返回，可加"重试"按钮
- `_buildVictoryOverlay` 补回（基于 `gs.status` 判断显示）
- Session 失败重连机制

## 文件清单

**新增（2）**：
- `test/core/localnet/session/session_channel_name_test.dart`
- `test/core/surround_game/lan/widget/game_page_session_test.dart`

**删除（3）**：
- `test/core/surround_game/lan/view_model/host_device_lost_test.dart`
- `test/core/surround_game/lan/view_model/client_device_lost_test.dart`
- `test/core/surround_game/lan/view_model/host_wall_turn_test.dart`（死代码）

**重命名（1）**：
- `test/core/surround_game/lan/widgets/host_wall_turn_widget_test.dart` → `lan_board_stack_test.dart`

**修改（9）**：
- `lib/core/localnet/session/session.dart` — 加 channelName
- `lib/core/localnet/session/session_manager.dart` — 加 channelName
- `lib/core/localnet/framework/lan_framework.dart` — 加 channelName
- `lib/core/surround_game/lan/lan_host_game_page.dart` — 重写（-184/+96）
- `lib/core/surround_game/lan/lan_client_game_page.dart` — 重写（+115/-176）
- `lib/core/surround_game/lan/service/lan_service_adapter.dart` — 删除旧 API + 加 channelName
- `lib/core/surround_game/lan/lan_match_event.dart` — 删 GameStatePushed 事件
- `lib/core/surround_game/lan/lan_host_view_model.dart` — 删 GameStatePushed reducer case
- `lib/core/surround_game/lan/lan_client_view_model.dart` — 删 GameStatePushed reducer case

## 参考

- Spec: `docs/superpowers/specs/2026-06-16-surround-game-lan-session-upgrade-design.md`
- Plan: `docs/superpowers/plans/2026-06-16-surround-game-lan-session-upgrade-plan.md`
- 上一轮 PR: `docs/superpowers/pr/2026-06-15-surround-game-lan-localnet.md`
