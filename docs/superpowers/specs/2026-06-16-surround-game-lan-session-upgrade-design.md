# LAN 模式升级：双端 Session 同步

> 状态：设计中
> 日期：2026-06-16
> 上一轮：LAN 接入 localnet（桩化→真联机，本轮前一 PR）

## 背景

上一轮 LAN 接入实现了"双端手动 sendGameState + watchGameState"状态同步路径。调试中发现：
1. **状态回退**：Host 收到 Client game_state 时只更新 `_gameStateNotifier`，不更新 VM → Host 再次 dispatch 时用旧 VM state 算 next → 丢弃 Client 走子
2. **手动同步冗余**：sendGameState / watchGameState / HostGameStatePushed / ClientGameStatePushed 四层手动桥接代码量大且易出错
3. **Session 层未被利用**：`lib/core/localnet/session/` 有完整的 `Session<StateT extends Listenable>` 自动同步能力，spec 第 4 节原设计就是用 Session，实施时因 Session channel 命名问题绕开了

## 目标

升级为**双端 Session 自动同步**：双方 GamePage 各创建一个 `Session<ValueNotifier<GameState>>`，落子后只更新 notifier，Session 自动序列化发送给对端。删除所有手动同步代码。

## 约束

- 不动 `lib/core/localnet/` 框架的其他部分（除 Session 小改）
- 不动 `lib/core/surround_game/local/`（单机热座）
- 不动 `lib/core/surround_game/widgets/`（共享组件）
- 不动 `lib/main.dart`
- Session 的 channelName 改造向后兼容（不传时行为不变）

## 架构设计

### 1. Session channelName 改造

**问题**：Session 默认 channel 名 `session/${peerId}_${state.hashCode}`，双端 peerId 和 hashCode 都不同 → 双向不通。

**修法**：Session / SessionManager / LanFramework 的 `createSession` 增加可选 `String? channelName` 参数。传入时用固定 channel 名，不走默认 hashCode 计算。

**改动文件**：
- `lib/core/localnet/session/session.dart`：构造器加 `this.channelName`，`_sessionChannel` getter 用 `channelName ?? 'session/${peerId}_${state.hashCode}'`
- `lib/core/localnet/session/session_manager.dart`：`create` 方法加 `channelName` 参数透传
- `lib/core/localnet/framework/lan_framework.dart`：`createSession` 加 `channelName` 参数透传

**向后兼容**：不传 channelName 行为不变。

### 2. GamePage 双端 Session 同步

**HostGamePage 和 ClientGamePage 对称改造**：

```
initState:
  _gameStateNotifier = ValueNotifier(QuoridorEngine.initialize())
  _session = adapter.createGameSession(
    peerId: opponentDeviceId,
    state: _gameStateNotifier,
    channelName: LanChannels.gameState,   // 'surround/game/state' 固定通道
  )
  _session.onChanged = () { setState(() {}) }
  if (isHost) _session.syncFull()   // Host 发初始 state

_onConfirm:
  current = _gameStateNotifier.value
  next = isWall
      ? QuoridorEngine.switchTurn(QuoridorEngine.placeWall(current, x, y, o)!)
      : QuoridorEngine.switchTurn(QuoridorEngine.movePiece(current, cellId)!)
  _gameStateNotifier.value = next    // Session 自动发

build:
  gs = _gameStateNotifier.value      // 唯一状态源
  isMyTurn = (isHost && gs.currentPlayerIsTop) || (!isHost && !gs.currentPlayerIsTop)
  // 显示棋盘
```

**Session 双向工作原理**：
- Host 发 `_gameStateNotifier.value = stateA` → Session serialize → sendTo `surround/game/state`
- Client 的 Session 在同一 channel 上 listen → deserialize → `_gameStateNotifier.value = stateA`
- Client 再走子 → `_gameStateNotifier.value = stateB` → Session 发 → Host 收 → 更新 Host notifier

**双方 notifier 始终同步**，无需手动 bridge。

### 3. deviceLost（不走 VM）

GamePage 不再持有 ViewModel。deviceLost 由 GamePage 自己处理：

```
initState:
  _devicesSub = adapter.watchDevices().listen((devices) {
    if (!devices.any((d) => d.deviceId == opponentDeviceId)) {
      _showDisconnectDialog()
    }
  })

dispose:
  _devicesSub?.cancel()
  _session?.dispose()
  _gameStateNotifier?.dispose()
```

"对手掉线"对话框：显示"对手已掉线" + 退出按钮 → Navigator.pop 退出 GamePage。

### 4. 删除清单

**GamePage（Host + Client）删除**：
- ❌ `_viewModel` 字段（VM 参与 game 状态机）
- ❌ initState 里的 fast-forward（HostCreateRoomWithRoom / HostStartGamePressed / 4×HostTick / ClientJoinPressed / ClientJoinAccepted / HostStartedCountdown / 4×ClientTick）
- ❌ `_gameStateSub`（watchGameState listener）
- ❌ `sendGameState(...)` 调用
- ❌ `_onConfirm` 里 dispatch VM 的逻辑
- ❌ `dispatch(HostGameStatePushed / ClientGameStatePushed)` 同步给 VM

**adapter 删除**：
- ❌ `sendGameState` 方法 + 实现
- ❌ `watchGameState` 方法 + 实现
- ❌ `_gameStateCtrl` StreamController
- ❌ `_gameStateStreams` map
- ❌ `_multicastSub` 里 `key == 'game_state'` 分支

**VM 事件删除**：
- ❌ `HostGameStatePushed`（lan_match_event.dart）
- ❌ `ClientGameStatePushed`（lan_match_event.dart）

**测试删除**：
- ❌ `host_device_lost_test.dart`（VM deviceLost 路径不再用）
- ❌ `client_device_lost_test.dart`（同上）

**保留**：
- ✅ `LanChannels.gameState` 常量（Session channelName 用）
- ✅ `sendJoinRequest` / `sendJoinAccept`（房间 join 仍走多播）
- ✅ `watchRoomEvents`（LanRoomPage 用）
- ✅ bridge 纯函数（reduceHostProtocol / reduceClientProtocol，但仅 LanRoomPage 设备用）
- ✅ protocol 消息 sealed class（HostRoomAnnounced / ClientJoinRequested 等）
- ✅ serializer（GameStateSerializer，供 Session 用）

### 5. 错误处理

- GamePage 双端订阅 `adapter.watchErrors()` 显示 SnackBar
- Session 内部 `_onMessage` 反序列化失败时推 errors 流（framework 已处理）
- deviceLost → 对话框 + 退出

### 6. 测试策略

- **保留**：协议消息单测、bridge 单测、serializer 单测（这些不依赖 VM）
- **删除**：`host_device_lost_test` / `client_device_lost_test`
- **新增**：`session_channel_name_test.dart`（验证 channelName 参数：传与不传的 channel 名不同）
- **新增**：`game_page_session_test.dart`（widget test，模拟 Session onChanged → 棋盘更新）
- **集成**：仍降级为手动 demo（framework 单例约束），但 demo 文档更新为 Session 路径

### 7. 验证标准

- `flutter analyze lib/core/surround_game/lan/` 0 errors
- `flutter test` 全绿
- 双机手动 demo：Host 落子 → Client 同步 → Client 落子 → Host 同步 → 多步不回退

## 附录

**Spec 第 4 节原文摘录**（本次升级实现）：
> "Host 端用 Session 自动发；Client 端也用 Session；双方同一份 notifier。"
> "GameState 不变；外层 ValueNotifier<GameState> 提供 Listenable。"
> "双端都创 Session<ValueNotifier<GameState>>，双向自动同步。"

**当前 commit 基线**：`7eb8176`（Host VM 同步 game_state 修复，本轮前最后一个 commit）
