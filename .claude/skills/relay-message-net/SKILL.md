---
name: relay-message-net
description: Relay (WS) 模式下的消息互通开发参考 — 引擎层 + 业务层 + UI 层的完整链路
---
# Relay MessageNet 开发参考

xiaodouzi_fr 项目里基于 WebSocket 中继的跨网络消息通讯全链路。

## 1. 架构总览

```
┌─────────────────────────────────────────────────────┐
│                    Lab Demo (UI)                      │
│     lib/core/localnet_biz/pages/                     │
│  ┌─────────────────┐  ┌────────────────────────┐    │
│  │ LocalnetDiscover  │  │   RelayChatPage        │    │
│  │   Page             │  │   (relay聊天页)        │    │
│  │  · _RelayPanel    │  └────────────────────────┘    │
│  │  · _buildDeviceList│                               │
│  └────────┬─────────┘                                │
│           │                              Biz Layer    │
├───────────┼─────────────────────────────────────────┤
│           v                                          │
│     LocalnetService (localnet_service.dart)           │
│  ┌──────────────────────────────────────────────┐   │
│  │ · sendMessage(  ) : auto-dispatch by mode     │   │
│  │ · createRelayRoom() / joinRelayRoom()        │   │
│  │ · sendRelayMessage() / leaveRelayRoom()      │   │
│  │ · _connectWs() / _disconnectWs()             │   │
│  │ · _onRelayChatFrame()                        │   │
│  └──────────┬───────────────────────────────────┘   │
│             │                                        │
├─────────────┼───────────────────────────────────────┤
│             v                   Engine Layer         │
│  lib/core/localnet/                                  │
│  ┌─────────┐ ┌──────────┐ ┌──────────────┐          │
│  │RelayDisc│ │WsTransport│ │RelayChannel │          │
│  │  overy   │ │  (WS帧)   │ │ (多路复用)   │          │
│  │ HTTP控制  │ │           │ │             │          │
│  └────┬────┘ └────┬─────┘ └──────┬───────┘          │
│       │           │              │                  │
│       v           v              v                  │
│  lib/api/goframe/room/room_endpoint.dart             │
│       (HTTP 调用统一入口，不走 ApiClient 拦截器链)      │
└─────────────────────────────────────────────────────┘
```

## 2. 什么时候用这个 Skill

| 场景                        | 参考章节   |
| --------------------------- | ---------- |
| 新增 Relay 模式 API 端点    | §3.1, §6 |
| 创建/加入房间流程           | §4.1      |
| 发送和接收 Relay 消息       | §4.2      |
| 调试 Host 收不到 Guest 消息 | §5 Bug 3  |
| 排查 LAN/Relay 消息互串     | §5 Bug 1  |
| `sendMessage` 自动分派    | §3.2      |
| Provider 注入 RoomEndpoint  | §6.3      |

## 3. 核心设计决策

### 3.1 为什么 RoomEndpoint 不走 ApiClient 拦截器链

Relay 中继服务器响应的 JSON 格式是 `{roomCode, wsUrl}`（扁平结构），
而 GoFrame 后端是 `{code, message, data}` 包裹格式 — 两者完全不兼容。

→ RoomEndpoint 自持 `http.Client`（等同于 github/notion 端点模式）。

### 3.2 sendMessage 自动分派

```dart
Future<bool> sendMessage(LocalnetDevice target, String content) async {
  if (config.config.mode == MessageNetMode.relay) {
    return sendRelayMessage(content);   // → WsTransport.send(TransportFrame)
  }
  return _fw.sendTo(target.id, 'chat', {'text': content});  // → LAN sendTo
}
```

### 3.3 共享消息桶 (LAN/Relay 隔离)

| 模式  | peerId (桶 key)                     | 说明                    |
| ----- | ----------------------------------- | ----------------------- |
| LAN   | `deviceId`（对端的真实 deviceId） | 每个 device 一个独立桶  |
| Relay | `'relay:${roomCode}'`             | Host/Guest 共享同一个桶 |

→ `_onRelayChatFrame` 收到帧后路由到 `_relayPeerId` 桶
→ `_subscribe()` 仅在 LAN 模式订阅 `_fw.watchChannel('chat')`

## 4. 关键流程

### 4.1 创建房间 (Host)

```dart
// 1. HTTP POST 创建房间
final info = await _relayDiscovery!.createRoom();

// 2. 设置共享桶 id
_relayPeerId = 'relay:${info.roomCode}';

// 3. 连接 WS
await _connectWs(info.wsUrl, role: 'host');
//    内部：WsTransport → RelayChannel.open('chat') → 发送 identify
```

### 4.2 加入房间 (Guest)

```dart
// 1. HTTP GET 加入房间
final result = await _relayDiscovery!.joinRoom(roomCode: code);

// 2. 用同一桶 id
_relayPeerId = 'relay:$roomCode';
_relayPeerAlias = result.host.alias;

// 3. 连接 WS
await _connectWs(result.wsUrl, role: 'guest');
```

### 4.3 连接 WS 并 identify

```dart
Future<void> _connectWs(String wsUrl, {required String role}) async {
  await _disconnectWs();  // 先断开旧连接
  final wsChannel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
  _ws = WsTransport(channel: wsChannel, myDeviceId: ...);
  _relayChannel = RelayChannel(ws: _ws!, myDeviceId: ...);
  await _relayChannel!.open(channelName: 'chat', remoteDeviceId: ...);

  // subscribe chat 帧
  _relayChatSub = _relayChannel!.watch('chat').listen(_onRelayChatFrame);

  // 发送 identify（服务端必须收到才能分配 slot）
  await _ws!.send(TransportFrame(
    channelName: 'identify',
    sourceDeviceId: myDeviceId,
    payload: Uint8List.fromList(utf8.encode(jsonEncode({'role': role}))),
    timestamp: DateTime.now(),
  ));
}
```

### 4.4 发送和接收 Relay 消息

**发送：**

```dart
Future<bool> sendRelayMessage(String content) async {
  final payload = utf8.encode(jsonEncode({
    'text': content,
    'alias': myAlias,
  }));
  await ws.send(TransportFrame(
    channelName: 'chat',
    sourceDeviceId: myDeviceId,
    payload: Uint8List.fromList(payload),
    timestamp: DateTime.now(),
  ));
}
```

**接收：**

```dart
void _onRelayChatFrame(TransportFrame frame) {
  final data = jsonDecode(utf8.decode(frame.payload));
  final content = data['text'];
  final alias = data['alias'] ?? frame.sourceDeviceId;
  final bucketId = _relayPeerId ?? frame.sourceDeviceId;

  _appendMessage(bucketId, LocalnetMessage(
    senderId: frame.sourceDeviceId,
    senderAlias: alias,
    content: content,
    timestamp: frame.timestamp,
  ));
}
```

## 5. 坑点对照表 (Bug 修复经验)

| # | Bug                                 | 根因                                                                                                                                        | 修复方案                                                                                                    |
| - | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| 1 | LAN/Relay 消息互串                  | `_lastPeer` 单变量 + 全局 `_messagesByPeer` 共享；`_subscribe()` 在 Relay 模式也订阅 `watchChannel('chat')` 抛 `UnsupportedError` | Relay 模式用独立`_relayChatSub` 订阅；`_subscribe()` 只在 LAN 模式订阅；消息归桶到各自 `_relayPeerId` |
| 2 | Host 创建房间后不能进聊天页         | `createRelayRoom()` 没设 `_relayPeerId`，`_autoNavigate()` 到 null peer                                                               | 创建房间后立即`_relayPeerId = 'relay:${roomCode}'`                                                        |
| 3 | Host 收不到 Guest 消息              | `_relayPeerId = null` → 消息写入 null 桶 → chat page `watchMessages(null)` 看不到                                                     | Host/Guest 统一用`'relay:${roomCode}'` 共享桶                                                             |
| 4 | `FrameworkRelayCore` 构造参数兼容 | 重构后`httpClient` 换成 `RoomEndpoint`，FrameworkRelayCore 未同步                                                                       | 构造函数参数改为`RoomEndpoint? roomEndpoint`，默认用 `config` 构造                                      |
| 5 | `relayHttpPath` 后端变更          | 后端统一`/api/v1` 前缀后 relay room 路径变为 `/api/v1/relay/rooms`                                                                      | 所有默认值和测试 mock path 同步更新                                                                         |

## 6. API 层 (RoomEndpoint)

### 6.1 RoomEndpoint 位置

```
lib/api/goframe/room/
├── room.dart               ← barrel export
└── room_endpoint.dart      ← RoomEndpoint + 结果/异常类
```

### 6.2 接口定义

| 方法                            | HTTP | 路径                           | 返回                                               |
| ------------------------------- | ---- | ------------------------------ | -------------------------------------------------- |
| `createRoom(alias, deviceId)` | POST | `/api/v1/relay/rooms`        | `RoomCreateResult{roomCode, wsUrl}`              |
| `joinRoom(roomCode)`          | GET  | `/api/v1/relay/rooms/{code}` | `RoomJoinResult{hostDeviceId, hostAlias, wsUrl}` |

### 6.3 Provider 注入

```dart
final roomEndpointProvider = Provider<RoomEndpoint>((_) {
  return RoomEndpoint(baseUrl: 'http://47.110.80.47:8988');
});
```

### 6.4 调试 / 验证

```bash
# 创建房间
curl -s -X POST http://47.110.80.47:8988/api/v1/relay/rooms \
  -H 'Content-Type: application/json' \
  -d '{"alias":"Tester","deviceId":"test-001"}'

# 加入房间
curl -s http://47.110.80.47:8988/api/v1/relay/rooms/{code}
```

## 7. 关联文件路径

- API 端点：`lib/api/goframe/room/room_endpoint.dart`
- API barrel：`lib/api/goframe/goframe.dart`
- Provider 注入：`lib/api/providers/api_providers.dart`
- Engine 发现：`lib/core/localnet/discovery/relay_discovery.dart`
- WS 传输：`lib/core/localnet/transport/ws_transport.dart`
- 通道复用：`lib/core/localnet/transport_channel/relay_channel.dart`
- Relay Core：`lib/core/localnet/framework/framework_relay_core.dart`
- 框架配置：`lib/core/localnet/framework/framework_config.dart`
- 框架门面：`lib/core/localnet/framework/lan_framework.dart`
- 业务 Service：`lib/core/localnet_biz/localnet_service.dart`
- 业务配置：`lib/core/localnet_biz/models/localnet_config.dart`
- 发现页 UI：`lib/core/localnet_biz/pages/localnet_discover_page.dart`
- 聊天页 UI：`lib/core/localnet_biz/pages/localnet_chat_page.dart`
- Lab 入口：`lib/lab/demos/message_net_demo.dart`
- Probe 验证：`.tool/relay-probe-47/scripts/ws_roundtrip.py`
- 后端指南：`.tool/relay-server-stub/BACKEND_GUIDE.md`

## 8. 错误案例

| 错误操作                                                               | 实际后果                                                     | 正确做法                                      |
| ---------------------------------------------------------------------- | ------------------------------------------------------------ | --------------------------------------------- |
| Host 创建房间后用 deviceId 做 peerId                                   | Guest 的 hostDeviceId 和 host 自己的 deviceId 不同，桶不匹配 | 用`'relay:${roomCode}'` 做共享桶 id         |
| `sendRelayMessage` 本地 echo 写入 `_relayDiscovery!.myDeviceId` 桶 | 发送方在 chat page 看不到自己发的消息                        | 写入`_relayPeerId` 桶                       |
| `_subscribe()` 无条件订阅 `_fw.watchChannel('chat')`               | Relay 模式抛`UnsupportedError`，LAN 消息污染 relay 桶      | `if (mode == lan)` 保护                     |
| `FrameworkRelayCore` 停止时不调 `_roomEndpoint.dispose()`          | http.Client 泄漏                                             | `stop()` 中调用 `_roomEndpoint.dispose()` |
| 测试 mock path 默认`/api/v1/rooms`                                   | `pathPrefix` 默认改为 `/api/v1/relay` 后 mock 404        | 同步更新测试的 handler key                    |
| RoomEndpoint 默认`pathPrefix = '/api/v1'`                            | 后端统一后实际路径为`/api/v1/relay/rooms`                  | 三个地方的默认值全部改为`/api/v1/relay`     |

## 9. 验证清单

- [ ] `flutter analyze` 零 error
- [ ] `flutter test test/localnet/` 全部通过
- [ ] `python scripts/ws_roundtrip.py` WS 回环测试通过
- [ ] 修改默认 pathPrefix 后同步更新了测试 mock
- [ ] 构造函数参数变更后同步更新了所有调用方
- [ ] `_relayPeerId` 初始化发生在 WS 连接之前
- [ ] LAN/Relay 桶使用不同的 key 前缀
- [ ] `_subscribe()` 有 mode guard
- [ ] `dispose()` 链完整（ws → channel → discovery → http client）
