# LocalNet 引擎重构设计 Spec

> **状态**：待用户审阅
> **创建日期**：2026-07-20
> **作者**：brainstorming session
> **关联 skill**：`.claude/skills/lan-local-playbook/`

## 1. 目标与不变式

### 1.1 目标

让 `LanFramework` 在保留现有局域网能力的同时，新增"互联网房间"模式——两台在不同网络的设备，通过**房间号（room code）**发现彼此，通过**中继服务器**双向同步状态。

### 1.2 不变式（硬约束）

1. **业务层零变化**：`LanServiceAdapter` 及其所有调用方（surround_game、jungle_chess）一行不动
2. **现有 LAN 模式行为不变**：UDP/HTTP P2P 路径完全保留
3. **发现与传输解耦**：发现通道（UDP 多播 / HTTP 控制面）独立于传输通道（HTTP P2P / WS 转发）
4. **接口与实现分离**：新增抽象 `DiscoveryService` / `TransportChannel`，让 LanCore / RelayCore 可以互换

### 1.3 新增依赖

- `web_socket_channel: ^2.4.0`（纯 Dart，仅客户端；不实现服务器）

## 2. 整体架构

```
┌──────────────────────────────────────────────────────────┐
│                  业务层 (零变化)                            │
│  surround_game / jungle_chess → LanServiceAdapter        │
└────────────────────┬─────────────────────────────────────┘
                     │  watchDevices / watchChannel /
                     │  createSession / sendMulticast
┌────────────────────┴─────────────────────────────────────┐
│              LanFramework (facade, 新增 transportKind)   │
│  start({transportKind: lan | relay, relayUrl?, ...})     │
└────────────────────┬─────────────────────────────────────┘
                     │
   ┌─────────────────┼─────────────────────┐
   │                 │                     │
┌──┴─────────┐ ┌─────┴──────┐ ┌───────────┴──────────┐
│ Framework- │ │ Framework- │ │ Framework-RelayCore  │
│ LanCore    │ │ LanCore    │ │ (新增)               │
└──┬─────────┘ └─────┬──────┘ └───────────┬──────────┘
   │                 │                     │
   UDP/HTTP P2P    UDP/HTTP P2P      HTTP控制 + WS传输
   (现)            (现)              (新)
```

**关键决策**：把现在的 `FrameworkCore` 重命名为 `FrameworkLanCore`，新增 `FrameworkRelayCore`，通过 `transportKind` 选择激活哪一个；两者对外暴露完全相同的接口（deviceManager / channelManager / sessionManager / eventBus）。

## 3. 核心抽象层（接口重构）

### 3.1 TransportKind

```dart
// 新增 lib/core/localnet/transport/transport_kind.dart
enum TransportKind { lan, relay }
```

### 3.2 DiscoveryService

```dart
// 新增 lib/core/localnet/discovery/discovery_service.dart
abstract interface class DiscoveryService {
  /// 启动发现（LAN：绑定 UDP socket；Relay：HTTP POST /discover）
  Future<void> start();

  /// 停止发现
  Future<void> stop();

  /// 已发现的远端设备列表
  List<RemoteEndpoint> get endpoints;

  /// 设备变化流
  Stream<List<RemoteEndpoint>> watch();

  /// 主动探测（如 Relay：HTTP POST /probe）
  Future<void> probe();
}
```

### 3.3 TransportChannel

```dart
// 新增 lib/core/localnet/transport_channel/transport_channel.dart
abstract interface class TransportChannel {
  /// 打开逻辑通道（LAN：HTTP 连接；Relay：WS 子协议）
  Future<void> open({required String channelName, required String remoteDeviceId});

  /// 发送消息
  Future<SendResult> send(String channelName, Uint8List data);

  /// 接收消息流
  Stream<TransportFrame> watch(String channelName);

  /// 关闭
  Future<void> close();
}
```

### 3.4 帧结构

```dart
// 新增 lib/core/localnet/transport/transport_frame.dart
class TransportFrame {
  final String channelName;
  final String sourceDeviceId;
  final Uint8List payload;
  final DateTime timestamp;
}
```

### 3.5 RemoteEndpoint

```dart
// 新增 lib/core/localnet/discovery/remote_endpoint.dart
class RemoteEndpoint {
  final String deviceId;
  final String alias;
  final String address;          // LAN: "192.168.1.5:53317" / Relay: "ws-session-xxx"
  final TransportKind kind;
  final DateTime lastSeen;
}
```

### 3.6 现有抽象的复用

- `Device` 类保留（业务层依赖），但 `DeviceManager` 内部改用 `RemoteEndpoint` 作底层
- `ChannelManager.sendTo(deviceId, channel, payload)` / `watchChannel(channel)` 签名不变，内部委托给 `TransportChannel`
- `Session` / `SessionManager` 一行不动（已经在 ChannelManager 之上）

## 4. 数据流

### 4.1 创房流程

```
Host Client                Relay Server                Other Clients
    │                          │                            │
    │ 1. POST /rooms           │                            │
    │ {alias, deviceId}        │                            │
    ├─────────────────────────→│                            │
    │                          │ 生成 roomCode (6位数字)    │
    │                          │ 写入 rooms 表              │
    │ ← 201 {roomCode, ws_url} │                            │
    │                          │                            │
    │ 2. WS connect ws_url     │                            │
    │ subprotocol: roomCode    │                            │
    ├─────────────────────────→│                            │
    │                          │ 注册 ws-session            │
    │ 3. POST /rooms/{code}/   │                            │
    │    advertise             │                            │
    │ {alias, deviceId}        │                            │
    ├─────────────────────────→│ 触发 room_announce         │
    │                          │ ──── WS broadcast ────→   │
    │                          │   (所有订阅了该 room 的    │
    │                          │    client 收到)            │
```

### 4.2 加房流程

```
Client                    Relay Server                    Host Client
  │                            │                              │
  │ POST /rooms/{code}/join    │                              │
  │ {alias, deviceId}          │                              │
  ├──────────────────────────→ │                              │
  │                            │ 验证 code 存在               │
  │                            │ 触发 join_request 广播      │
  │                            │ ──── WS broadcast ────→     │
  │ ← 200 {ws_url_peer}        │ ← (Host 选择 accept/reject)│
  │                            │                              │
  │ WS connect ws_url_peer     │                              │
  ├──────────────────────────→ │                              │
```

### 4.3 游戏状态同步

完全复用现 `Session` 机制——`LanFramework.createSession` 内部委托给 `TransportChannel.send(channel='session/...', payload)`，对端 `TransportChannel.watch(channel)` 收到后投递给 `Session._onMessage`。**业务层零感知**。

## 5. RelayCore 实现要点

### 5.1 文件结构（新增）

```
lib/core/localnet/
├── transport/
│   ├── transport.dart            (现 — 保留)
│   ├── udp_transport.dart        (现 — 仅 LanCore 用)
│   ├── http_transport.dart       (现 — LanCore 用 + RelayCore HTTP 控制面复用)
│   ├── ws_transport.dart         (新 — RelayCore 传输面)
│   ├── transport_kind.dart       (新 — enum)
│   └── transport_frame.dart      (新 — 帧结构)
├── discovery/
│   ├── discovery_service.dart    (新 — 抽象)
│   ├── lan_discovery.dart        (新 — LAN 实现，封装现 UDP 多播)
│   └── relay_discovery.dart      (新 — Relay 实现，HTTP 短调用)
├── transport_channel/
│   ├── transport_channel.dart    (新 — 抽象)
│   ├── lan_channel.dart          (新 — LAN 实现，封装现 HTTP P2P)
│   └── relay_channel.dart        (新 — Relay 实现，WS 多路复用)
├── framework/
│   ├── lan_framework.dart        (现 — 改为门面分发到 LanCore/RelayCore)
│   ├── framework_core.dart       (现 — 重命名为 framework_lan_core.dart)
│   ├── framework_relay_core.dart (新)
│   ├── framework_config.dart     (现 — 新增 relayUrl/roomCode 字段)
│   └── ...
```

### 5.2 FrameworkConfig 扩展

```dart
class FrameworkConfig {
  const FrameworkConfig({
    // ... 现字段
    this.transportKind = TransportKind.lan,   // 新
    this.relayUrl,                              // 新：例如 'https://relay.example.com'
    this.relayHttpPath = '/api/v1',             // 新
    this.relayWsPath = '/ws',                   // 新
  });
}
```

### 5.3 LanFramework.start 分发

```dart
Future<void> start(FrameworkConfig config) async {
  _config = config;
  if (config.transportKind == TransportKind.lan) {
    _core = FrameworkLanCore(...);
  } else {
    _core = FrameworkRelayCore(...);
  }
  await _core.start();
}
```

### 5.4 FrameworkRelayCore 内部

- `discoveryService = RelayDiscovery(relayUrl, httpPath)`
- `transportChannel = RelayChannel(relayUrl, wsPath)`
- 把这两个塞给 `DeviceManager` / `ChannelManager` 复用——**后两者行为不变**，只是注入不同的实现

## 6. 错误处理与降级

### 6.1 四类错误

| 错误 | 检测 | 降级 |
|------|------|------|
| Relay 服务器不可达 | HTTP `/discover` 5xx / 超时 | 抛出 `RelayUnreachableError`，业务层选择重试或切回 LAN |
| 房间号无效 | HTTP `/rooms/{code}/join` 404 | 抛出 `RoomNotFoundError`，UI 显示"房间号不存在或已过期" |
| WS 断连 | WS onDone | `TransportChannel.watch` 发 `TransportDisconnectedEvent`，DeviceManager 把对端标 offline；自动重连 3 次后抛 `RelaySessionLostError` |
| 房间已满（2 人） | HTTP `/rooms/{code}/join` 409 | 抛出 `RoomFullError`，UI 提示 |

### 6.2 新增事件（注入到现 EventBus）

- `RelayRoomCreatedEvent {roomCode, wsUrl}`
- `RelayJoinAcceptedEvent {peerDeviceId}`
- `RelayJoinRejectedEvent {reason}`
- `RelayDisconnectedEvent {reason}`
- `RelayReconnectingEvent {attempt}`

## 7. 测试策略

### 7.1 新增测试文件

```
test/localnet/
├── transport/transport_frame_test.dart      (序列化/反序列化)
├── discovery/
│   ├── relay_discovery_test.dart            (用 mock HTTP client 测房间号注册/查询)
│   └── lan_discovery_test.dart              (现 UDP 多播测，包装为 Discovery 接口)
├── transport_channel/
│   ├── relay_channel_test.dart              (用 mock WebSocket 测多路复用)
│   └── lan_channel_test.dart
└── framework/
    ├── framework_relay_core_test.dart       (用 mock Relay 服务测完整流程)
    └── framework_lan_core_test.dart         (现逻辑回归测试)
```

### 7.2 关键测试场景

1. RelayCore 启动后能调到 `LanServiceAdapter.watchDevices()` 拿到对端
2. RelayCore 创建的 Session 能在 mock WS 服务中断线后自动重连
3. 多路复用：同一 WS 连接上同时跑 3 个虚拟 channel，互不干扰
4. 房间号生成：1ms 内 1000 次生成无重复（用单调计数器 + 设备指纹）

## 8. 迁移路径

| 阶段 | 内容 | 兼容性 |
|------|------|--------|
| Phase 0 | 重命名 `FrameworkCore` → `FrameworkLanCore`，引入 `TransportKind` 枚举（默认 `lan`） | 现有代码零变化 |
| Phase 1 | 引入 `DiscoveryService` / `TransportChannel` 抽象，新增 `LanDiscovery` / `LanChannel` 适配器，包装现有 UDP/HTTP 逻辑 | 现有代码零变化 |
| Phase 2 | 引入 `RelayDiscovery` / `RelayChannel` / `FrameworkRelayCore`，加 `relayUrl` 配置项 | 现有代码零变化 |
| Phase 3 | 完整测试覆盖 + `LanServiceAdapter` 入口扩展（用户可选 relay mode） | 现有代码零变化 |
| Phase 4 | 业务层按需接入 relay mode（不在本 spec 范围） | — |

## 9. YAGNI 守护清单

- ❌ 不实现 Relay 服务器本身（仅客户端协议契约）
- ❌ 不实现房间号管理 UI（业务层后续）
- ❌ 不引入 BLE / WebRTC 等其他传输后端（用户未提及）
- ❌ 不实现 NAT 穿透 / ICE（仅标准中继）
- ❌ 不改 `LanServiceAdapter` 公共 API（业务层零变化约束）

## 10. 开放问题

- Q1：房间号生成策略——6 位数字 vs UUID？建议 6 位数字 + 防碰撞重试
- Q2：WS 子协议设计——是用单一 WS 连接多路复用，还是每 channel 一条 WS？建议多路复用
- Q3：auth 机制——中继服务器怎么验证 client 真实加入了某个房间？建议：roomCode + deviceId 签名（共享密钥）— 具体实现留给服务器端
- Q4：是否需要心跳？建议：WS 自带 ping/pong frame，30s 间隔；服务端超时 90s 视为离线