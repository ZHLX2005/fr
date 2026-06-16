# Surround Game LAN 接入 LocalNet 设计文档

> 状态：设计中（spec 自审通过后由用户审批）
> 日期：2026-06-15
> 上一轮：UI 拆分（已完成）→ 本轮接入 localnet 框架

## 目标

将 `lib/core/surround_game/lan/` 子树从「桩化 UI」升级为「通过 `lib/core/localnet/` 框架真正实现双设备联机」。

- 不动 `lib/core/surround_game/local/`（单机热座已完善）
- 不动 `lib/core/surround_game/widgets/`（共享组件）
- 不动 `lib/main.dart`（CLAUDE.md 硬约束）
- 不动 `lib/core/localnet/` 框架内部（除非暴露缺失 API）

## 约束与原则

1. **隔离 framework 细节**：业务层（Page / ViewModel）不直接 `import` localnet，全部走 `LanServiceAdapter`。
2. **协议集中**：所有 channel 字符串与消息 sealed class 集中在 `lan/protocol/`。
3. **不可变不变**：保持 `GameState` 不可变契约；通过外层 `ValueNotifier<GameState>` 提供 Listenable 能力。
4. **Host 权威**：Host 端用 Session 自动发，Client 端用显式 `sendTo` 发；Client 不创建 Session。
5. **TDD 节奏**：每个 task 先写测试 → 看到失败 → 写代码 → 通过 → commit。

## 1. 架构总览

```
lib/core/surround_game/
├── lobby/                            ← 模式选择（不动）
├── local/                            ← 单机热座（不动）
│
├── lan/                              ← 接入 localnet（本轮目标）
│   ├── lan_lobby_page.dart           ← 改：弹 alias + 启 framework + 设备/房间列表
│   ├── lan_room_page.dart            ← 改：Host 建房协议、Client 选房协议
│   ├── lan_host_game_page.dart       ← 改：Session 绑定 + 翻页
│   ├── lan_client_game_page.dart     ← 改：显式 sendTo
│   ├── lan_host_view_model.dart      ← 改：deviceLost / 协议事件路径
│   ├── lan_client_view_model.dart    ← 改：deviceLost / 协议事件路径
│   ├── lan_match_state.dart          ← 不动（HostError / ClientDisconnected 已存在）
│   ├── lan_match_event.dart          ← 不动
│   ├── lan_ui_state.dart             ← 不动
│   ├── widgets/                      ← 不动
│   │
│   ├── protocol/                     ← 新增
│   │   ├── lan_channels.dart         ← channel 常量
│   │   └── lan_messages.dart         ← sealed class 协议消息
│   │
│   ├── serializer/                   ← 新增
│   │   └── game_state_serializer.dart ← GameState ↔ Map
│   │
│   ├── service/                      ← 新增
│   │   └── lan_service_adapter.dart  ← 业务层唯一接触点
│   │
│   └── profile/                      ← 新增
│       └── alias_dialog.dart         ← 弹窗输入本机名称
```

**为什么新增三个子目录**：
- `protocol/`：通道字符串与消息类型集中一处，未来扩展（聊天/投票）同源
- `serializer/`：GameState 序列化与 framework 解耦，可独立单测
- `service/`：唯一接触 `lib/core/localnet/`，业务层零 import 框架

## 2. LanServiceAdapter 接口

**文件**：`lan/service/lan_service_adapter.dart`

### 接口契约

```dart
abstract class LanServiceAdapter {
  static final LanServiceAdapter instance = _LanServiceAdapterImpl();

  // 生命周期
  Future<void> start({required String myAlias});
  Future<void> stop();

  // 状态
  bool get isRunning;
  Stream<LanServiceError> watchErrors();
  String get myDeviceId;
  String get myAlias;

  // 设备
  Stream<List<Device>> watchDevices();

  // 房间协议（业务层只看到 sealed class，不看到 Map）
  Stream<LanRoomEvent> watchRoomEvents();
  // 单次广播。adapter 内部启动 timer 周期性重发（每 5s）直到 stopRoom 取消
  Future<void> announceRoom(GameRoom room);
  void stopRoom(String roomId);
  Future<SendResult> sendJoinRequest({
    required String hostDeviceId,
    required String clientAlias,
  });
  Future<SendResult> sendJoinAccept({
    required String clientDeviceId,
    required GameRoom room,
  });
  Future<SendResult> sendLeave(String peerDeviceId);

  // 游戏状态同步
  // Host 端使用：自动监听 state 变化 → 发送至 peer
  // Client 端不使用此 API（见第 4 节）
  Session<ValueNotifier<GameState>> createGameSession({
    required String peerDeviceId,
    required ValueNotifier<GameState> state,
  });

  // Client 端使用：显式发送一次 GameState
  Future<SendResult> sendGameState({
    required String hostDeviceId,
    required GameState state,
  });

  // Client 端使用：监听 Host 发来的 GameState
  Stream<GameState> watchGameState(String hostDeviceId);
}
```

### 实现要点

- 内部唯一接触 `LanFramework.instance` 与 `SessionManager`。
- `watchRoomEvents()` 内部合并 `fw.watchChannel('surround/room/announce')` + `fw.watchChannel('surround/room/join')`，转换为 `LanRoomEvent` sealed class 后推流。
- `start({myAlias})` → 调 `fw.start(FrameworkConfig(deviceAlias: myAlias))`；`stop()` → `fw.stop()`。
- 幂等：start 时若 framework 已 running 则只更新 alias；stop 同理。

## 3. 协议

### 3.1 通道常量

**文件**：`lan/protocol/lan_channels.dart`

```dart
abstract class LanChannels {
  static const String roomAnnounce = 'surround/room/announce';
  static const String roomJoin     = 'surround/room/join';
  static const String gameState    = 'surround/game/state';
  // 注：roomLeave 本轮不实现（YAGNI）。断线依赖 UDP 心跳超时 + deviceLost 检测。
}
```

### 3.2 协议消息

**文件**：`lan/protocol/lan_messages.dart`

```dart
sealed class LanRoomEvent {
  const LanRoomEvent();
  Map<String, dynamic> toJson();
  static LanRoomEvent fromJson(Map<String, dynamic> json) { /* dispatch by 'type' */ }
}

/// Host → 广播：建了房间
class HostRoomAnnounced extends LanRoomEvent {
  HostRoomAnnounced({
    required this.room,
    required this.hostDeviceId,
    required this.hostAlias,
  });
  final GameRoom room;
  final String hostDeviceId;
  final String hostAlias;
}

/// Host → 广播：关房
class HostRoomClosed extends LanRoomEvent {
  HostRoomClosed({required this.roomId});
  final String roomId;
}

/// Client → Host：请求加入
class ClientJoinRequested extends LanRoomEvent {
  ClientJoinRequested({
    required this.clientDeviceId,
    required this.clientAlias,
    required this.roomId,
  });
  final String clientDeviceId;
  final String clientAlias;
  final String roomId;
}

/// Host → Client：加入结果
class ClientJoinResult extends LanRoomEvent {
  ClientJoinResult({
    required this.roomId,
    required this.clientDeviceId,
    required this.accepted,
    this.reason,
  });
  final String roomId;
  final String clientDeviceId;
  final bool accepted;
  final String? reason;
}
```

**协议消息序列化**：所有 `toJson` / `fromJson` 集中在本文件，使用 `type` 字段做 sealed class 分发（避免 client 端收到未知 type 时崩溃）。

## 4. GameState 序列化

**文件**：`lan/serializer/game_state_serializer.dart`

```dart
class GameStateSerializer implements StateSerializer<ValueNotifier<GameState>> {
  GameStateSerializer();

  @override
  Map<String, dynamic> serialize(ValueNotifier<GameState> notifier) {
    return notifier.value.toJson();
  }

  @override
  ValueNotifier<GameState> deserialize(
    Map<String, dynamic> data,
    ValueNotifier<GameState> target,
  ) {
    // 1. 解析为 GameState 临时对象（adjacency/wallGrid 为空，但 history 已就绪）
    final temp = GameState.fromJson(data);
    // 2. 用 QuoridorEngine.replayHistory(temp.history) 重建
    //    签名：static GameState replayHistory(List<MoveRecord> history, {int? upTo})
    //    流程：initialize() → 逐条 applyMoveRecord → _recomputeTurn 重算回合
    final rebuilt = QuoridorEngine.replayHistory(temp.history);
    // 3. in-place 更新 target.value
    target.value = rebuilt;
    return target;
  }
}
```

**关键点**：
- `target.value = rebuilt` 触发 Listenable 通知 → Session 内部自动判定本端修改 → **抑制再发送**（Session 自身有 `_suppressSync` 机制）
- 不构造新 ValueNotifier，保留原引用（Page 的 ValueListenableBuilder 继续监听）
- 不可变契约维持：`rebuilt` 仍是新的 GameState 值对象

## 5. 核心时序

### 5.1 建房（Host 在 LanLobbyPage → LanRoomPage）

```
User: LanLobbyPage 弹 aliasDialog → 填名字 → 点确定
  ↓
LanLobbyPage._aliasConfirmed(alias):
  await adapter.start(myAlias: alias)
  ↓
User: 点击「创建房间」按钮
  ↓
vm.dispatch(HostCreateRoomPressed()) → HostWaiting(room)
Navigator.push(LanRoomPage(role: 'host', initialRoom: room))
  ↓
LanRoomPage.initState:
  _vm.dispatch(HostCreateRoomWithRoom(room))
  订阅 adapter.watchRoomEvents() → 处理 ClientJoinRequested
  adapter.announceRoom(room)    ← adapter 内部每 5s 自动重发
  ↓
User: 点「开始游戏」 → _vm.dispatch(HostStartGamePressed)
  HostCountdown(3) → HostTick × 3 → HostInGame
  Navigator.pushReplacement(LanHostGamePage)
  ↓
LanHostGamePage.initState:
  _gameStateNotifier = ValueNotifier(QuoridorEngine.initialize())
  _session = adapter.createGameSession(
    peerId: clientDeviceId,
    state: _gameStateNotifier,
  )
  _session.onChanged = () => setState(() {})
  _session.syncFull()    ← 主动推初始状态
```

### 5.2 选房（Client 在 LanLobbyPage → LanRoomPage）

```
User: LanLobbyPage 弹 aliasDialog → 填名字 → 点确定
  await adapter.start(myAlias: alias)
  订阅 adapter.watchRoomEvents() → HostRoomAnnounced 时插列表
  ↓
User: 点击列表中某个房间（带 hostAlias 显示）
  Navigator.push(LanRoomPage(role: 'client', targetRoom: room))
  ↓
LanRoomPage.initState:
  _clientVm.dispatch(ClientJoinPressed(targetRoom)) → ClientJoining
  adapter.sendJoinRequest(hostDeviceId, clientAlias)
  订阅 watchRoomEvents() → 处理 ClientJoinResult
  ↓
Client 收到 ClientJoinResult(accepted=true):
  _clientVm.dispatch(ClientJoinAccepted(room)) → ClientWaiting
  ↓
Client 收到 HostStartedCountdown (从 HostCountdown 同步):
  _clientVm.dispatch(HostStartedCountdown(3)) → ClientCountdown
  ClientTick × 3 → ClientInGame
  Navigator.pushReplacement(LanClientGamePage)
  ↓
LanClientGamePage.initState:
  _gameStateNotifier = ValueNotifier(QuoridorEngine.initialize())
  // 不创建 Session
  // 订阅 adapter.watchGameState(hostDeviceId) 推送给 notifier
```

### 5.3 落子同步

**Host 端：**
```
User 落子 → _onConfirm
  ↓
vm.dispatch(HostMoveCommitted(moveData)) → reduce _applyAndCheck
  next = QuoridorEngine.movePiece or placeWall + switchTurn
  ↓
_gameStateNotifier.value = next
  ↓
[Session 自动] Listenable 触发 → serializer.serialize(notifier) → toJson
  ↓
fw.sendTo(clientDeviceId, 'surround/game/state', json)
```

**Client 端：**
```
User 落子 → _onConfirm
  ↓
vm.dispatch(ClientMoveCommitted(moveData)) → reduce _applyAndCheck
  next = QuoridorEngine.movePiece or placeWall + switchTurn
  ↓
_gameStateNotifier.value = next    ← 本端 UI 立即更新
  ↓
adapter.sendGameState(hostDeviceId, next)    ← 显式 sendTo
```

**Host 端接收 Client 落子：**
```
fw.watchChannel('surround/game/state') 触发
  ↓
Adapter 内部: 从 notifier.value 取出，serializer.deserialize 重建
  （注：本端创建 Session 时，Session 内部已订阅 watchChannel）
  ↓
serializer.deserialize:
  temp = GameState.fromJson(data)
  rebuilt = QuoridorEngine.replayHistory(temp)
  _gameStateNotifier.value = rebuilt
  ↓
[Session 自动] _suppressSync=true → 不再发回 Client
  ↓
Page onChanged → setState
```

## 6. 错误处理与断线

### 6.1 三类错误

| 错误 | 触发 | 检测 | 处理 |
|---|---|---|---|
| framework 启动失败 | `fw.start()` 抛异常 | adapter 内部 try/catch | `start()` 返回的 Future 抛 → LanLobbyPage 渲染错误页 |
| 对方断线 | UDP 心跳超时 | `fw.watchDevices()` 不再 emit 该 deviceId | ViewModel 监听 → 推 HostError / ClientDisconnected |
| Session 发送失败 | `fw.sendTo` 返回 SendResult.fail | adapter 内部累计 | 失败 ≥ 3 次触发 HostError / ClientDisconnected |

### 6.2 状态机迁移

```
HostInGame → (对方掉线) → HostError('对手已掉线', previous: HostInGame)
ClientInGame → (对方掉线) → ClientDisconnected(canReconnect: true)
```

**deviceLost 检测代码位置**：
- 注入式：`adapter.watchDevices().listen(...)` 在 ViewModel 构造时挂载
- 触发 dispatch：`HostClientLeft` (Host) 或 `ClientDisconnected` 内态（Client 端通过 `dispatch(HostClientLeft)` 走统一路径）
- 单测可注入 mock stream 覆盖

### 6.3 重连

- HostError / ClientDisconnected 页面渲染「对手已掉线」+「重连」按钮
- 点重连 → `adapter.createSession(...)` 旧 session dispose + 新 session 同步 `syncFull()`
- **不实现增量合并**：仅快照同步

## 7. 状态机集成

### 7.1 新增事件

`lan_match_event.dart` 不动。所有协议相关事件封装在 `LanRoomEvent` sealed class 内，由 ViewModel 在构造时订阅 `adapter.watchRoomEvents()` 后转换为内部事件 dispatch。

转换函数（提取为可测纯函数）：

```dart
// lan/lan_host_protocol_bridge.dart
LanHostState? processRoomEvent(LanHostState current, LanRoomEvent event) {
  return switch ((current, event)) {
    (HostWaiting(), ClientJoinRequested(:final clientId, :final clientAlias))
      => HostWaiting(/*...*/),
    // ...
  };
}
```

### 7.2 注入式测试

ViewModel 构造时接受 `Stream<LanRoomEvent> roomEvents` 参数（生产环境 = adapter.instance.watchRoomEvents()），单测可注入 mock stream。

类似：`Stream<List<Device>> devicesStream`。

## 8. 测试策略

### 8.1 单元测试（`test/core/surround_game/lan/`）

| 文件 | 覆盖 |
|---|---|
| `protocol/lan_messages_test.dart` | 4 个 event 的 toJson / fromJson round-trip + 未知 type 抛 |
| `serializer/game_state_serializer_test.dart` | serialize + deserialize + replayHistory 重建正确 |
| `service/lan_service_adapter_test.dart` | mock fw，验证 start/stop/announce/sendJoinRequest 流程 |
| `view_model/host_protocol_bridge_test.dart` | processRoomEvent 纯函数状态转移 |
| `view_model/client_protocol_bridge_test.dart` | 同上 |
| `view_model/host_device_lost_test.dart` | mock deviceLost stream → 触发 HostError |
| `view_model/client_device_lost_test.dart` | mock deviceLost stream → 触发 ClientDisconnected |

预计 ~25 个 case。

### 8.2 集成测试（`integration_test/lan_session_integration_test.dart`）

**前置条件**：framework 暴露多实例或可注入 transport。当前 `LanFramework.instance` 是单例，集成测试需绕过。**本轮在 spec 中加一个 framework 小修改任务**（见第 9 节 Task 0）。

集成测试场景：
1. 起 2 个 LanFramework 实例（deviceId 区分、端口区分）
2. Host 建房 → 广播 → Client 收 → join → 接受
3. Host 落子 → Client 收到 GameState 变更 → assert 一致
4. Client 落子 → Host 收到 → assert 一致

### 8.3 端到端（手动）

跨进程手动 demo 验证：两台手机/模拟器，A 建 B 加，落子同步。**不写自动化 e2e**。

## 9. 实施分块（16 个 task）

| # | Task | 文件 | 状态 |
|---|---|---|---|
| 0 | framework 暴露多实例 API（仅 spec 标注，task 列表外） | `lib/core/localnet/framework/lan_framework.dart` | 需 framework owner 评估 |
| 1 | 新增通道常量 | `lan/protocol/lan_channels.dart` | 新建 |
| 2 | 新增协议消息 sealed class + (de)serialize | `lan/protocol/lan_messages.dart` | 新建 |
| 3 | 单测：协议消息 round-trip | `test/.../lan_messages_test.dart` | 新建 |
| 4 | GameState Serializer | `lan/serializer/game_state_serializer.dart` | 新建 |
| 5 | 单测：Serializer round-trip | `test/.../game_state_serializer_test.dart` | 新建 |
| 6 | LanServiceAdapter 接口 + impl | `lan/service/lan_service_adapter.dart` | 新建 |
| 7 | 单测：Adapter（mock fw） | `test/.../lan_service_adapter_test.dart` | 新建 |
| 8 | aliasDialog 组件 | `lan/profile/alias_dialog.dart` | 新建 |
| 9 | Host protocol bridge 纯函数 | `lan/lan_host_protocol_bridge.dart` | 新建 |
| 10 | Client protocol bridge 纯函数 | `lan/lan_client_protocol_bridge.dart` | 新建 |
| 11 | 单测：两个 bridge 状态转移 | `test/.../*bridge_test.dart` | 新建 |
| 12 | LanLobbyPage 集成 adapter.start + aliasDialog | `lan/lan_lobby_page.dart` | 改 |
| 13 | LanRoomPage 接入 protocol events | `lan/lan_room_page.dart` | 改 |
| 14 | LanHostViewModel 接入 deviceLost + bridge | `lan/lan_host_view_model.dart` | 改 |
| 15 | LanClientViewModel 接入 deviceLost + bridge | `lan/lan_client_view_model.dart` | 改 |
| 16 | LanHostGamePage 创 Session | `lan/lan_host_game_page.dart` | 改 |
| 17 | LanClientGamePage 显式 sendTo | `lan/lan_client_game_page.dart` | 改 |
| 18 | deviceLost 路径单测 | `test/.../*device_lost_test.dart` | 新建 |
| 19 | 集成测试：2 个 fw 实例 e2e | `integration_test/lan_session_integration_test.dart` | 新建 |
| 20 | flutter analyze + flutter test 全绿 | — | 验证 |
| 21 | commit + PR 描述 | — | 收尾 |

实际 task 编号 1-21（21 个 task，比最初估的 16 多 5 个，因拆分 bridge 纯函数独立可测 + 加 deviceLost 路径单测）。

## 10. 范围与 YAGNI

**不做**（明确）：
- 跨设备聊天 / 表情
- 观战模式
- 房间密码
- 跨网段（中继）连接
- 增量合并重连（仅快照）
- 自动化 e2e
- 持久化 alias（每次启动弹窗输入）
- 修改 framework 内部协议（仅可申请追加 API）

**做**：
- Host/Client 双设备局域网对战
- 一局走完后回 lobby 重新建房
- 对手掉线提示与重连按钮

## 11. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| `LanFramework.instance` 是单例，集成测试难 | task 19 集成测试受阻 | Task 0：申请 framework 暴露 `LanFramework.create({deviceId, port})` 多实例 |
| UDP 在某些网络下被阻断 | 设备发现失败 | 后续轮次加中继（不在本轮范围） |
| GameState.toJson 体积大（history 全量） | 流量大 | 本轮容忍；下轮增量 |
| Session 内部 Listenable 抑制机制 | 远端→本端更新不重复发 | framework 已实现 `_suppressSync`，无需额外处理 |
| Host 端 dispose Session 时机 | 内存泄漏 | HostInGame → HostFinished/HostError 时 dispose；Page dispose 时兜底 |

## 12. 验证标准

- `flutter analyze lib/core/surround_game/lan/` 0 error
- `flutter test test/core/surround_game/lan/` 全绿
- 集成测试 `flutter test integration_test/lan_session_integration_test.dart` 全绿
- 手动跨进程 demo：两台机器完成一局完整对局

---

## 附录 A：涉及的现有文件（仅参考，不直接改 framework）

- `lib/core/localnet/localnet.dart`（barrel，不动）
- `lib/core/localnet/framework/lan_framework.dart`（Task 0 申请扩展）
- `lib/core/localnet/session/session.dart`（用作 `createGameSession` 返回类型）
- `lib/core/localnet/session/state_serializer.dart`（`StateSerializer` 接口已定义）
- `lib/core/surround_game/engine/game_engine.dart`（`replayHistory` 已在该文件中）
- `lib/core/surround_game/models/game_state.dart`（`toJson`/`fromJson` 已实现）

## 附录 B：变更文件清单

**新建（10 个）**：
- `lib/core/surround_game/lan/protocol/lan_channels.dart`
- `lib/core/surround_game/lan/protocol/lan_messages.dart`
- `lib/core/surround_game/lan/serializer/game_state_serializer.dart`
- `lib/core/surround_game/lan/service/lan_service_adapter.dart`
- `lib/core/surround_game/lan/profile/alias_dialog.dart`
- `lib/core/surround_game/lan/lan_host_protocol_bridge.dart`
- `lib/core/surround_game/lan/lan_client_protocol_bridge.dart`
- `test/core/surround_game/lan/protocol/lan_messages_test.dart`
- `test/core/surround_game/lan/serializer/game_state_serializer_test.dart`
- `test/core/surround_game/lan/service/lan_service_adapter_test.dart`
- `test/core/surround_game/lan/view_model/host_protocol_bridge_test.dart`
- `test/core/surround_game/lan/view_model/client_protocol_bridge_test.dart`
- `test/core/surround_game/lan/view_model/host_device_lost_test.dart`
- `test/core/surround_game/lan/view_model/client_device_lost_test.dart`
- `integration_test/lan_session_integration_test.dart`

**修改（7 个）**：
- `lib/core/surround_game/lan/lan_lobby_page.dart`
- `lib/core/surround_game/lan/lan_room_page.dart`
- `lib/core/surround_game/lan/lan_host_view_model.dart`
- `lib/core/surround_game/lan/lan_client_view_model.dart`
- `lib/core/surround_game/lan/lan_host_game_page.dart`
- `lib/core/surround_game/lan/lan_client_game_page.dart`
- `pubspec.yaml`（若 framework 需新增 export 或 alias 持久化）
