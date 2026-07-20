---
name: lan-local-playbook
description: 当用户需要"开发局域网多人模式"、"实现本地热座对战"、"查看通信架构"、"排查局域网连接问题"、"添加新游戏的双人模式"时触发。覆盖 xiaodouzi_fr 项目 LanFramework 框架集成 + surround_game 本地/LAN 模式完整开发流程。包含三层架构（Framework → Biz → Game）、模式参考、坑点汇总、调试 SOP。
---

# LAN + Local Mode Playbook

xiaodouzi_fr 项目里局域网通信和本地对战的全链路开发参考。

## 1. 架构总览

```
┌─────────────────────────────────────────────────────┐
│                     Game Layer                       │
│           lib/core/surround_game/  (53 files)        │
│  ┌─────────────────┐  ┌──────────────────────────┐  │
│  │   Local 模式      │  │   LAN 模式               │  │
│  │  VM+State+Event  │  │  Adapter + StateMachine  │  │
│  │  热座双人         │  │  SDK 协议 + Session 同步  │  │
│  └────────┬─────────┘  └───────────┬──────────────┘  │
│           │                        │                 │
├───────────┼────────────────────────┼─────────────────┤
│           │    Service Adapter      │                 │
│           │  lib/core/localnet_biz/ │  (已废弃)       │
│           │   LanServiceAdapter     │                 │
│           └───────────┬─────────────┘                 │
│                       │      Biz Layer                │
├───────────────────────┼─────────────────────────────┤
│                       v                             │
│              LanFramework.instance                   │
│  lib/core/localnet/  (28 files)                      │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌──────────────┐ │
│  │Transport│ │ Device │ │Channel │ │  Session      │ │
│  │UDP+HTTP │ │发现/注册│ │消息路由│ │  状态同步      │ │
│  └────────┘ └────────┘ └────────┘ └──────────────┘ │
│                       Framework Layer               │
└─────────────────────────────────────────────────────┘
```

**关键设计决策**：
- 业务层（Game）不直接 import `localnet` → 通过 `LanServiceAdapter` 单层隔离
- 本地模式不需要网络层，但共用同一套 Engine + State + UI Widget
- Session 模式用于状态同步，Channel 模式用于消息流 —— 两者不混用

**Lan/Relay 双后端（自 2026-07 重构后）**：
- **LanCore**（现）：UDP 多播（端口 5678）+ HTTP P2P（端口 53317）— 同子网设备
- **RelayCore**（新增）：HTTP 控制面（房间号注册/查询）+ WS 多路复用（端口 443 wss）— 跨网段设备
- 两者通过 `transportKind: lan|relay` 配置切换，业务层 LanServiceAdapter 一行不动
- 共用同一套 DeviceManager / ChannelManager / SessionManager 骨架
- 协议契约：`docs/superpowers/specs/2026-07-20-engine-refactor-design.md`

## 2. 什么时候用这个 Skill

| 场景 | 参考章节 |
|------|---------|
| 为新游戏添加本地热座双人模式 | §4.1 |
| 为已有游戏添加局域网多人对战 | §4.2 |
| 排查两台设备互不发现 | ref/discovery-debug.md |
| 修改 LAN 协议消息 | §4.2.2 |
| 新增 LAN protocol channel | §4.2.2 |
| 调整状态同步逻辑 | §4.2.4 |
| 移动端真机调试网络 | ref/discovery-debug.md §1 |
| 理解三层之间的关系 | §3 |
| 为游戏添加互联网房间模式（房间号发现） | §4.4 |
| 排查 Relay（WS）模式连接问题 | §4.4.10 + ref/discovery-debug.md §2.6 |

## 3. 快速启动

### 3.1 纯本地模式（热座）

```dart
// 1. 创建 ViewModel
final viewModel = LocalViewModel();

// 2. 分发事件
viewModel.dispatch(const LocalStartPressed());
// → state: LocalIdle → LocalInGame(initialGameState)

// 3. 确认走棋
viewModel.dispatch(LocalMoveCommitted(targetCellId: 36));
// → state: LocalInGame(switchedTurnGameState)

// 4. 确认放墙
viewModel.dispatch(LocalMoveCommitted(
  targetCellId: 36, // 放墙时用墙壁坐标，此处必需但不
  wallX: 4, wallY: 4, wallOrientation: WallOrientation.horizontal,
));

// 5. 悔棋
viewModel.dispatch(const LocalUndoRequested());

// 6. UI 绑定
ValueListenableBuilder<LocalMatchState>(
  valueListenable: viewModel,
  builder: (ctx, state, _) { /* switch(state) 渲染 */ },
);

// 7. 退出时释放
viewModel.dispose();
```

**核心文件**：`reference/local-mode-pattern.md`

### 3.2 局域网模式

```dart
// 1. 启动适配器（底层启动 LanFramework）
await LanServiceAdapter.instance.start(myAlias: 'Player1');

// 2. 订阅设备列表和设备列表
LanServiceAdapter.instance.watchDevices().listen(...);
LanServiceAdapter.instance.watchRoomEvents().listen(...);

// 3. Host：广播房间
final room = GameRoom(roomId: 'room-xxx', hostId: myDeviceId, hostName: myAlias);
await LanServiceAdapter.instance.announceRoom(room);

// 4. Client：加入房间
await LanServiceAdapter.instance.sendJoinRequest(
  hostDeviceId: hostDeviceId,
  clientAlias: myAlias,
);

// 5. 创建游戏 Session（Host 收到 Client 后）
final session = LanServiceAdapter.instance.createGameSession(
  peerDeviceId: clientDeviceId,
  state: gameStateNotifier,
);
// Session 自动同步 state 到对端

// 6. 退出时停止
await LanServiceAdapter.instance.stop();
```

**核心文件**：`reference/lan-game-pattern.md`

### 3.3 Framework 层启动（手动）

```dart
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

final deviceId = await DeviceIdService.load();
await fw.LanFramework.instance.start(fw.FrameworkConfig(
  deviceId: deviceId,
  deviceAlias: 'My Device',
  udpBroadcastEnabled: true,
  udpListenerEnabled: true,
  httpServerEnabled: true,
));
// 启动后必须探测本机 IP
final myIp = await detectLocalIp();
if (myIp != null) fw.LanFramework.instance.setMyIp(myIp);
```

**核心文件**：`reference/framework-integration.md`

## 4. 架构模式详解

### 4.1 本地模式：ViewModel + State + Event

**本质**：单向数据流 + 纯函数 reducer。

```
Event → dispatch() → reduce(state, event) → newState → UI rebuild
                     ↑                              │
                     └── engine mutation ────────────┘
```

**三要素**：

| 角色 | 文件 | 说明 |
|------|------|------|
| `LocalMatchState` | `local/local_match_state.dart` | sealed class 枚举所有可能状态 |
| `LocalMatchEvent` | `local/local_match_event.dart` | sealed class 枚举所有用户操作 |
| `LocalViewModel` | `local/local_view_model.dart` | ValueNotifier + reduce() 纯函数 |

**状态转移图**：

```
  ┌──────────┐  LocalStartPressed  ┌──────────┐  undo/reset  ┌──────────┐
  │ LocalIdle│ ──────────────────→ │LocalInGame│ ←────────── │LocalInGame│
  └──────────┘                     └────┬─────┘              └──────────┘
                                        │  game over
                                        v
                                  ┌──────────┐  exit/reset
                                  │LocalFinished│ ──────────→ LocalIdle
                                  └──────────┘
```

**关键规则**：
- `reduce()` 必须是纯函数 —— 不调 `setState`、不发网络、不读 `DateTime.now()`
- 引擎方法（`QuoridorEngine.movePiece`）返回 `null` 表示非法操作，`reduce()` 返回原状态
- `identical(next, value)` 检查避免不必要的通知
- ViewModel extends `ValueNotifier`，天然支持 `ValueListenableBuilder` 绑定

**新游戏适配清单**：
- [ ] 定义 `xxxMatchState` sealed class（idle / inGame / finished）
- [ ] 定义 `xxxMatchEvent` sealed class（start / move / undo / reset / exit）
- [ ] 实现 `xxxViewModel extends ValueNotifier` + `reduce()` 纯函数
- [ ] 引擎方法返回 null 表示非法操作
- [ ] UI 用 `ValueListenableBuilder` 绑定

### 4.2 LAN 模式

#### 4.2.1 分层隔离设计

```
Page (UI) → ViewModel (StateMachine) → ServiceAdapter (LAN Bridge) → LanFramework
```

- **Page**：UI 编排、导航、dispose 生命周期
- **ViewModel**：纯状态机，接收 `LanHostEvent`/`LanClientEvent` 和 `LanRoomEvent`（协议事件）
- **ServiceAdapter**：业务层唯一接触 `localnet` 框架的边界 —— 隔离 `LanFramework.instance`
- **LanFramework**：基础设施（UDP + HTTP + Session）

#### 4.2.2 协议消息设计

**Channel 命名规范**：`surround/<domain>/<action>`

```dart
// lan_channels.dart
static const roomAnnounce = 'surround/room/announce';  // UDP 多播
static const roomJoin     = 'surround/room/join';        // UDP 多播
static const gameState    = 'surround/game/state';       // Session（HTTP）
```

**消息序列化规范**：统一带 `type` 字段做反分发

```dart
// lan_messages.dart 标准模版
sealed class LanRoomEvent {
  String get type;
  Map<String, dynamic> toJson();

  static LanRoomEvent fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'HostRoomAnnounced' => HostRoomAnnounced.fromJson(json),
      'HostRoomClosed'    => HostRoomClosed.fromJson(json),
      'ClientJoinRequested' => ClientJoinRequested.fromJson(json),
      'ClientJoinResult'    => ClientJoinResult.fromJson(json),
      _ => throw FormatException('Unknown type: $t'),
    };
  }
}
```

**通信流程**：
```
Host                          Client
  │                              │
  ├─ UDP 多播 roomAnnounce ──────→  (每 5s 一次周期性心跳)
  │                              │
  │  ←──────── UDP 多播 roomJoin ──┤  (Client 请求加入)
  │                              │
  ├─ UDP 多播 roomJoin (accept) ──→
  │                              │
  ├─ Session gameState ──────────→│  (HTTP 双向同步)
  │  ←──────── Session gameState ─┤
  │                              │
```

**协议事件 → 状态机迁移**：通过 ProtocolBridge 纯函数串联

```dart
// lan_host_protocol_bridge.dart
LanHostState reduceHostProtocol(LanHostState current, LanRoomEvent event) {
  return switch ((current, event)) {
    (HostWaiting(:final room), ClientJoinRequested e) =>
      HostWaiting(room.copyWith(clientId: e.clientDeviceId, clientName: e.clientAlias)),
    (HostInGame(), HostClientLeft()) =>
      HostError('对手掉线', previous: current),
    _ => current,
  };
}

// lan_client_protocol_bridge.dart
LanClientState reduceClientProtocol(LanClientState current, LanRoomEvent event) {
  return switch ((current, event)) {
    (ClientJoining(:final targetRoom), ClientJoinResult(:final accepted)) =>
      accepted ? ClientWaiting(targetRoom) : const ClientIdle(),
    (ClientInGame(), ClientDisconnectedProtocol()) =>
      const ClientDisconnected(),
    _ => current,
  };
}
```

#### 4.2.3 Host/Client 双状态机

**Host 状态机**：

```
  ┌─────────┐  createRoom  ┌──────────┐  clientJoin  ┌──────────┐
  │HostLobby│ ────────────→│HostWaiting│ ────────────→│HostWaiting│
  └─────────┘              └─────┬─────┘  (update room)│ (有client)
                                 │ startGame           │
                                 v                     │
                            ┌──────────┐               │
                      ┌────→│HostCountd│ ←─────────────┘
                      │     │own (3s)  │
                      │     └─────┬─────┘
                      │           │ countdown=0
                      │           v
                      │     ┌──────────┐  move/place
                      │     │HostInGame│ ───────────→ HostInGame
                      │     └────┬─────┘              (new state)
                      │          │ status≠running
                      │          v
                      │     ┌──────────┐  retry
                      │     │HostFinish│ ──────────→ HostCountdown
                      │     │ed       │
                      │     └──────────┘
                      │          │ abort
                      │          v
                      │     ┌──────────┐
                      └─────│HostError │  retry → HostLobby
                            └──────────┘
```

**Client 状态机**：

```
  ┌──────────┐  joinPressed ┌───────────┐  accept  ┌───────────┐
  │ClientIdle│ ────────────→│ClientJoini│ ────────→│ClientWaiti│
  └──────────┘              │ng         │  reject   │ng         │
       ↑                   └───────────┘  →Idle    └─────┬─────┘
       │ reconnect                                         │ hostStartCountdown
       │                                                   v
  ┌──────────┐                                      ┌───────────┐
  │ClientDisc│  deviceLost                           │ClientCoun│
  │onnected  │ ←──────────────────────────           │tdown (3s)│
  └──────────┘           ┌───────────┐               └─────┬─────┘
                      ┌──│ClientInGa │←────────────────────┘
                      │  │me         │  hostStatePushed
                      │  └────┬──────┘
                      │       │ status≠running or moveCommitted
                      │       v
                      │  ┌───────────┐
                      └──│ClientFini│
                         │shed      │
                         └──────────┘
```

**双机一致性策略**：
- Host 是权威端（authoritative）：所有引擎操作在 Host 执行
- Client 的操作提交给 Host，Host 执行后通过 Session 推回给 Client
- 或：双方各自执行引擎操作，通过 Session 同步 state（当前实现方案）
- Session 的 `_suppressSync` 机制防止同步循环

#### 4.2.4 Session 同步

```dart
// 1. 定义 Serializer
class GameStateSerializer implements StateSerializer<ValueNotifier<GameState>> {
  Map<String, dynamic> serialize(ValueNotifier<GameState> notifier) {
    return notifier.value.toJson();
  }

  ValueNotifier<GameState> deserialize(Map<String, dynamic> data, ValueNotifier<GameState> target) {
    final temp = GameState.fromJson(data);
    final rebuilt = QuoridorEngine.replayHistory(temp.history);
    target.value = rebuilt;
    return target;
  }
}

// 2. 使用 Session
final session = LanFramework.instance.createSession<ValueNotifier<GameState>>(
  peerId: peerDeviceId,
  state: gameStateNotifier,
  serializer: const GameStateSerializer(),
  channelName: channelName,
);

// 3. 同步后的 gameState 是最新历史快照
gameStateNotifier.addListener(() {
  // Session 自动同步：listen 到 state 变化 → serialize → HTTP POST → 对端 deserialize
});
```

**Session 同步规则**：
- `serialize()` 序列化完整 state → 对端收到后 `deserialize()` in-place 修改 target
- `target.value = rebuilt` 触发 `ValueNotifier` 通知 → UI 重建
- 引擎 `replayHistory` 通过棋谱重建 adjacency/wallGrid/validMoves
- 同步频率由 `state.addListener` 驱动（state 变化立即同步）
- 初始化时 Host 调用 `session.syncFull()` 发送完整状态

### 4.3 Touch Controller 适配

| 模式 | 工厂 | 说明 |
|------|------|------|
| Local | `LocalTouchControllerFactory` | 标准 TouchController |
| LAN Host | `LanHostTouchControllerFactory(boardSize)` | y 坐标镜像（flipY 棋盘） |
| LAN Client | `LanClientTouchControllerFactory` | 标准 TouchController |

Host 端屏幕翻转后触摸坐标需要镜像，使"点击视觉下方"对应 engine 的 top player：

```dart
class LanHostTouchController extends TouchController {
  final double boardSize;
  LanHostTouchController({required this.boardSize});

  Offset _mirror(Offset p) => Offset(p.dx, boardSize - p.dy);

  @override
  void handleTouchBegan(Offset localPosition, double cellSize, double distance, ...) {
    super.handleTouchBegan(_mirror(localPosition), cellSize, distance, ...);
  }
  // handleTouchMoved / handleTouchEnded 同样镜像
}
```

### 4.4 Relay（WS）模式详解

> 自 2026-07 引擎重构后新增。完整 spec 在 `docs/superpowers/specs/2026-07-20-engine-refactor-design.md`。

#### 4.4.1 为什么需要 Relay 模式

| 场景 | LAN 模式 | Relay 模式 |
|------|---------|----------|
| 同 WiFi、同子网 | ✅ 直接 P2P | ✅ 也行（不必要） |
| 不同网络（跨 NAT / 跨地域） | ❌ UDP 不可达 | ✅ 走中继服务器 |
| 朋友输入房间号即开打 | ❌ 没房间号概念 | ✅ 6 位数字 |
| 需要中继服务器 | ❌ 不需要 | ✅ **必需** |

**关键不变量**：业务层 `LanServiceAdapter` API 表面零变化；切到 Relay 只需换 `FrameworkConfig`：

```dart
// LAN（默认）：
await LanServiceAdapter.instance.start(myAlias: 'Alice');

// Relay：
// （需要先扩展 LanServiceAdapter.start 接收 relayUrl；当前仅 FrameworkConfig 支持，
//  业务侧接入是后续 task，不在本 skill scope）
await LanFramework.instance.start(FrameworkConfig(
  transportKind: TransportKind.relay,
  relayUrl: 'https://relay.example.com',
  deviceId: deviceId,
  deviceAlias: 'Alice',
));
```

#### 4.4.2 Relay 模式架构

```
Host Client                Relay Server                Guest Client
    │                          │                            │
    │ 1. POST /rooms           │                            │
    │ {deviceId, alias}        │                            │
    ├─────────────────────────→│                            │
    │ ← 201 {roomCode, wsUrl}  │                            │
    │                          │                            │
    │ 2. WS connect wsUrl      │                            │
    │   (IOWebSocketChannel)   │                            │
    ├═══════════════════════════>│                            │
    │  ↓ 双向多路复用帧          │  （按 room 转发）          │
    │                          │                            │
    │                          │ 3. POST /rooms/{code}/join│
    │                          │    {deviceId, alias}       │
    │                          │ ←─────────────────────────┤
    │                          │ → 200 {roomCode, wsUrl}   │
    │                          │                            │
    │                          │ 4. WS connect wsUrl       │
    │ ←═══════════════════════════│══════════════════════════>│
    │  ↓ 中继转发                │                            │
```

#### 4.4.3 数据结构 — TransportFrame

所有传输后端（UDP/HTTP/WS）都封装成 `TransportFrame`：

```dart
class TransportFrame {
  const TransportFrame({
    required this.channelName,        // 虚拟通道名
    required this.sourceDeviceId,     // 来源 deviceId
    required this.payload,            // base64 编码业务数据
    required this.timestamp,
  });

  final String channelName;
  final String sourceDeviceId;
  final Uint8List payload;
  final DateTime timestamp;

  Map<String, dynamic> toJson();  // JSON 序列化（WS 用文本帧）
  factory TransportFrame.fromJson(Map<String, dynamic> json);
}
```

**关键设计**：WS 用**文本帧**传 JSON（不是二进制），因为：
- `WebSocketChannel.sink.add(...)` 在 Flutter web 上只支持文本
- JSON 便于服务端用任何语言解析
- 字段集足够小，base64 payload 没有显著开销

#### 4.4.4 关键类与职责

| 类 | 路径 | 职责 |
|----|------|------|
| `RelayDiscovery` | `discovery/relay_discovery.dart` | HTTP 短调用：`POST /rooms` / `GET /rooms/{code}` / `POST /rooms/{code}/join` |
| `WsTransport` | `transport/ws_transport.dart` | 单 WS 连接 → 双向 `TransportFrame` 解析；发送把帧编码 JSON 文本 |
| `RelayChannel` | `transport_channel/relay_channel.dart` | `TransportChannel` 的 WS 后端实现；按 `channelName` 路由入站帧 |
| `FrameworkRelayCore` | `framework/framework_relay_core.dart` | 编排：Discovery + WsTransport + RelayChannel + 共用 DeviceManager/ChannelManager/SessionManager |

#### 4.4.5 多路复用原理

单条 WS 连接承载多个虚拟通道，**靠 `channelName` 字段在客户端路由**：

```
Host WS conn                        Guest WS conn
  │                                       │
  ├─ frame{channelName="chat"}            │
  ├═══════════════════════════════════════>│ RelayChannel.watch("chat") → 投递给对应 listener
  │                                       │
  ├─ frame{channelName="session/xxx"}     │
  ├═══════════════════════════════════════>│ RelayChannel.watch("session/xxx") → Session._onMessage
```

服务端只是按 `room_code` **整体转发**——**它不解析 `channelName`**。路由在客户端完成。

#### 4.4.6 房间号生成（房间号 = 发现凭证）

```python
# 服务端等价（Python 2/3 兼容）：
import random, string
ROOM_CODE_LENGTH = 6
rng = random.SystemRandom()
code = "".join(rng.choice(string.digits) for _ in range(ROOM_CODE_LENGTH))
while code in existing_codes:  # 简单查表去重
    code = "".join(rng.choice(string.digits) for _ in range(ROOM_CODE_LENGTH))
```

**为什么 6 位数字**：
- 短好记，朋友输入即可
- 仅数字避免 o/0、l/1 混淆
- 1/10^6 碰撞概率；2 人房间场景下重试 1-2 次必成功

**房间号传递路径**（**不经过服务器**）：
- Host 拿到房间号后，通过 IM / 短信 / 复制粘贴私下发给 Guest
- Guest 拿到房间号后调 `GET /rooms/{code}` 查 `wsUrl`
- 这种"私下交换 + 服务器只验证"的模式避免房间列表暴露

#### 4.4.7 加入 Relay 后端（新建游戏）

接入现有 `LanServiceAdapter` 时，仅需扩展 `start` 接收 `relayUrl`：

```dart
// 业务侧（不破坏现有 LAN API）：
await LanServiceAdapter.instance.start(
  myAlias: 'Alice',
  transportKind: TransportKind.relay,
  relayUrl: 'https://relay.example.com',
);
```

**业务层 0 修改**：`createRoom` / `sendJoinRequest` / `createGameSession` 等方法对 Relay/LAN 内部路由都一致。

#### 4.4.8 Relay 模式 vs LAN 模式：API 等价表

| 业务 API | LAN 内部实现 | Relay 内部实现 |
|---------|------------|---------------|
| `start()` | UDP 监听 + HTTP server | HTTP 控制面 + WS upgrade |
| `watchDevices()` | `LanDiscovery` (UDP) | `RelayDiscovery` (HTTP 短轮询或 push) |
| `announceRoom()` | UDP 多播广播 | `POST /rooms` 一次性 |
| `sendJoinRequest()` | UDP 多播 `room_join` | HTTP `POST /rooms/{code}/join` |
| `createGameSession()` | HTTP `/channel/...` | WS 多路复用帧（channelName=`session/...`） |
| `stop()` | UDP/HTTP 释放 | WS 关闭 + HTTP 释放 |

**业务侧看到的 API 100% 一致**；后端通过 `TransportKind` 路由。

#### 4.4.9 Relay 模式坑点

| # | 错误操作 | 实际后果 | 正确做法 |
|---|---------|---------|---------|
| 16 | 客户端用 `replaceFirst('http', 'ws')` 自己拼 WS URL | `wss://` 双 s、`http://...example.com` 误伤、版本不一致 | **服务端是 wsUrl 唯一权威**；`POST /rooms/{code}/join` 必须返回 wsUrl |
| 17 | WS 帧走二进制 | Flutter Web 不支持二进制帧发送 | **用 JSON 文本帧** + base64 payload |
| 18 | 一个 channel 一条 WS 连接 | 连接数爆炸（频道多时） | **单 WS 多路复用**（`channelName` 路由） |
| 19 | 业务层直接 `import 'localnet/transport/ws_transport.dart'` | 业务耦合框架实现细节 | **通过 `LanServiceAdapter` 调用**（同 LAN 模式约束） |
| 20 | 服务端忽略 `room_code` 隔离 | 跨房间数据泄漏 | 服务端必须按 `room_code` 分桶转发 |
| 21 | 房间不设过期 | 资源耗尽（DOS） | 30 分钟无连接自动清理；host 关房立即删 |
| 22 | 不做心跳 | 客户端关闭页面后房间不清 | 30s ping/pong，90s 超时断开 |
| 23 | 用 HTTP 传游戏状态 | 每次 POST 触发完整 request/response 循环 | **WS 长连接 + 多路复用帧** |

#### 4.4.10 Relay 调试

- 监听 `LanServiceAdapter.watchErrors()` 看整个 Relay 链错误
- `LanFramework.eventBus` 看 RelayRoomCreatedEvent / RelayDisconnectedEvent 等
- 服务器端：务必看 [BACKEND_GUIDE.md](../../.tool/relay-server-stub/BACKEND_GUIDE.md) — 包含完整接口契约 + 案例源码 + Python 测试脚本

## 5. 坑点对照表

### Framework 层坑点

| # | 错误操作 | 实际后果 | 正确做法 |
|---|---------|---------|---------|
| 1 | 每次启动不传 deviceId，让框架生成新 UUID | 对端看到"老设备离线 + 新设备上线" | 启动前从 SharedPreferences 读取或生成并落盘 |
| 2 | 用 `NetworkInterface.list` 不加 fallback | Android 上枚举不到 `wlan0` | 先 `InternetAddress.lookup('dns.google')` 失败再 fallback |
| 3 | 不用 `LanServiceAdapter` 直接 import localnet | 业务层耦合框架实现细节 | 通过 `LanServiceAdapter.instance` 调全部 LAN 操作 |
| 4 | 三项开关全 false 时还调 start | 业务以为在运行，实际什么都没发 | config.load() 加全 false 兜底守卫 |
| 5 | `dispose()` 不 await `stop()` | socket 残留，下次 start 端口占用 | 整条 stop 链 await 化 |
| 6 | HTTP 和 UDP 绑同一个端口 | errno=98 反复出现 | 拆开：HTTP 53317 / UDP 5678 |
| 7 | UDP bind 用 `reusePort: true` | Android/Windows 不支持 | 只用 `reuseAddress: true` |

### LAN 模式坑点

| # | 错误操作 | 实际后果 | 正确做法 |
|---|---------|---------|---------|
| 8 | 用 Session 做聊天流 | Session 是状态同步，无时间序 | 聊天用 `sendTo/watchChannel`；状态共享才用 Session |
| 9 | `msg.payload['alias']` 当昵称 | sendTo 根本没传 alias，回退成 UUID | 用 `msg.sourceDeviceId` 去 `devices` 查当前 alias |
| 10 | ViewModel 里混入网络调用 | 状态机不可测试 | ProtocolBridge 纯函数处理协议事件；ViewModel 只做状态迁移 |
| 11 | LAN 模式下触摸控制器不区分 Host/Client | Host 端翻转后触摸坐标错位 | Host 用 `LanHostTouchController`（y 镜像），Client 用标准 |
| 12 | 多播地址用 `224.0.0.0/24` | 多数家用路由器过滤 | 用 `239.255.255.255`（ADMINSCOPE） |

### 本地模式坑点

| # | 错误操作 | 实际后果 | 正确做法 |
|---|---------|---------|---------|
| 13 | `reduce()` 里调用 `setState` 或 `notifyListener` | 死循环或跨帧更新 | `value = next` 自动触发通知 |
| 14 | 引擎返回 null 时不做检查 | 游戏状态损坏 | 先 `if (result == null) return s;` 短路 |
| 15 | 快速双击"开始" | 创建两个 ViewModel | ViewModel 在 `initState` 创建，`dispose` 释放 |

## 6. 调试指南

### 6.1 本地模式

- `viewModel.value` 始终是 sealed class — switch 穷尽检查所有分支
- `identical(next, value)` 返回 true 表示 reducer 没产生新状态
- 引擎方法返回 null → 操作非法，UI 不应展示确认按钮

### 6.2 LAN 模式

- 监听 `framework.eventBus` 事件看设备生命周期
- `watchMulticast()` 看原始 UDP 数据包
- 双机联调时确保同一 WiFi + 关闭流量节省
- `adb shell ip addr` 确认同子网（详见 reference/discovery-debug.md）

### 6.3 通用

- VS Code 在 `lan_service_adapter.dart` 和 `lan_messages.dart` 设断点
- 在 `PlatformDispatcher.instance.onError` 里兜底日志
- 调整 `broadcastInterval`（默认 3s）加速测试（警告：频率过高会打满网络）

## 7. 参考文件索引

| 文件 | 说明 |
|------|------|
| `reference/architecture-overview.md` | 三层架构详解 + 文件依赖图 |
| `reference/framework-integration.md` | LanFramework 标准接入流程 + 检查清单 |
| `reference/discovery-debug.md` | 设备发现物理网络验证 + socket 生命周期 + logcat 模式 |
| `reference/local-mode-pattern.md` | Local ViewModel + State + Event 完整模式 |
| `reference/lan-game-pattern.md` | LAN 模式：Adapter + Protocol + StateMachine + Session |
| `reference/touch-controller-adapters.md` | 三种 TouchController 工厂适配 |

## 8. 关联文件路径

- 框架门面：`lib/core/localnet/framework/lan_framework.dart`
- 框架配置：`lib/core/localnet/framework/framework_config.dart`
- 框架编排：`lib/core/localnet/framework/framework_lan_core.dart`
- 业务适配层：`lib/core/surround_game/lan/service/lan_service_adapter.dart`
- 协议消息：`lib/core/surround_game/lan/protocol/lan_messages.dart`
- 协议通道：`lib/core/surround_game/lan/protocol/lan_channels.dart`
- Host ViewModel：`lib/core/surround_game/lan/lan_host_view_model.dart`
- Client ViewModel：`lib/core/surround_game/lan/lan_client_view_model.dart`
- Host Bridge：`lib/core/surround_game/lan/lan_host_protocol_bridge.dart`
- Client Bridge：`lib/core/surround_game/lan/lan_client_protocol_bridge.dart`
- Local ViewModel：`lib/core/surround_game/local/local_view_model.dart`
- 状态定义：`lib/core/surround_game/lan/lan_match_state.dart`
- 事件定义：`lib/core/surround_game/lan/lan_match_event.dart`
- 本地状态：`lib/core/surround_game/local/local_match_state.dart`
- 本地事件：`lib/core/surround_game/local/local_match_event.dart`
- Session 序列化：`lib/core/surround_game/lan/serializer/game_state_serializer.dart`
- 触摸控制：`lib/core/surround_game/widgets/touch_controller.dart`
- 触摸工厂接口：`lib/core/surround_game/mode_factory.dart`
- 房间模型：`lib/core/surround_game/lan/game_room.dart`
- 大厅页：`lib/core/surround_game/lan/lan_lobby_page.dart`
- 房间页：`lib/core/surround_game/lan/lan_room_page.dart`
- Host 游戏页：`lib/core/surround_game/lan/lan_host_game_page.dart`
- Client 游戏页：`lib/core/surround_game/lan/lan_client_game_page.dart`
- 本地游戏页：`lib/core/surround_game/local/local_game_page.dart`

### Relay（WS）模式补充路径

- 枚举 `TransportKind`：`lib/core/localnet/transport/transport_kind.dart`
- 抽象发现接口：`lib/core/localnet/discovery/discovery_service.dart`
- 抽象传输通道：`lib/core/localnet/transport_channel/transport_channel.dart`
- Relay 发现（HTTP）：`lib/core/localnet/discovery/relay_discovery.dart`
- WS 多路复用传输：`lib/core/localnet/transport/ws_transport.dart`
- Relay 端 Channel：`lib/core/localnet/transport_channel/relay_channel.dart`
- 统一帧 + JSON：`lib/core/localnet/transport/transport_frame.dart`
- Relay Framework：`lib/core/localnet/framework/framework_relay_core.dart`
- 后端实现指南：`.tool/relay-server-stub/BACKEND_GUIDE.md`
- 后端骨架 Python：`.tool/relay-server-stub/scripts/server.py`
- 后端契约自测：`.tool/relay-server-stub/scripts/test_client.py`
