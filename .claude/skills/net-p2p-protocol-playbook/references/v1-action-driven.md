---
name: v1-action-driven
description: v1 协议详细参考 — action/事件驱动模型（topic pub/sub），由 RelayTransport 内部使用。维护老代码 / 排查"晚加入者错过 peer-joined 事件"问题时读
---

# V1 Action/Event-Driven Protocol

Relay 协议 v1 = topic pub/sub，事件流模型。

> 当前为 net_p2p 的**遗留用法**。LAN 模式保留 v1；Relay 模式新功能走 v2 snapshot。

## 1. 核心架构

```
Biz Layer
  │  transport.createRoom / joinRoom / broadcastScope / watchScope
  ▼
RelayTransport (前端)
  │  WS 帧 {channelName, sourceDeviceId, payload}
  ▼
Relay Server (后端)
  │  topic = "room/<code>/events"
  │  relay.Default().Publish(topic, frame)
  │  任意订阅者收广播
```

**单源 vs 多源**：v1 没有单源——所有订阅者对等地接收事件流。客户端必须自己合并事件还原状态。

## 2. 数据结构

### 2.1 帧格式（TransportFrame）

```json
{
  "channelName": "room/123456/events",
  "sourceDeviceId": "device-abc-123",
  "payload": "<base64 业务 JSON>",
  "timestamp": "2026-07-25T10:00:00Z"
}
```

- `channelName`：业务通道名（v1 通常是 `room/<code>/events`）
- `payload`：base64 字符串；解码后是业务 JSON
- `timestamp`：RFC3339

### 2.2 业务事件类型（channel 内部 payload）

```json
{ "type": "peer-joined", "alias": "Alice", "deviceId": "device-abc-123" }
```

```json
{ "type": "peer-online", "alias": "Alice", "deviceId": "device-abc-123" }
```

```json
{ "type": "peer-left", "deviceId": "device-abc-123" }
```

```json
{
  "type": "room-snapshot",
  "host": {"deviceId": "...", "alias": "..."},
  "guests": [{"deviceId": "...", "alias": "..."}]
}
```

```json
{
  "type": "scope-update",
  "scope": "chat-X-Y",
  "state": {"messages": [...]},
  "from": "device-abc-123"
}
```

## 3. 后端关键代码（Go）

### 3.1 房间存储 — `internal/relay/relay.go`

```go
type Room struct {
    Code      string
    Host      Peer
    Guests    []Peer
    Status    string
    CreatedAt time.Time
}

type Service struct {
    mu     sync.Mutex
    rooms  map[string]*Room
    topics map[string]bool  // 已注册的 topic
}

func (s *Service) CreateRoom(host Peer, maxPlayers int) (*Room, error) {
    code := generateRoomCode()  // 6 位数字，碰撞重试
    s.rooms[code] = &Room{Host: host, Status: "waiting"}
    s.topics[topicFor(code)] = true
    return s.rooms[code], nil
}

func (s *Service) JoinRoom(code string, guest Peer) error {
    // 追加到 Guests
    // 不广播 — 由 controller 在 success 后触发 room-snapshot
}

func (s *Service) NotifyRoomEvent(code, deviceID, eventType string, payload []byte) error {
    // 任意业务事件入口
    // 用 relay.Default().Publish(topic, frame)
}
```

### 3.2 WS 升级 — `internal/relay/transport.go`

```go
func HandleWS(c *gfnet.WebSocketConn, code string) {
    topic := "room/" + code + "/events"
    ch := relay.Default().Subscribe(topic)
    defer relay.Default().Unsubscribe(topic, ch)

    // 启动：立即推一份 room-snapshot 给新订阅者
    snap, _ := relay.Default().Snapshot(code)
    sendFrame(c, topic, snap)

    // 双向 pump
    go func() { /* forward WS -> publish */ }()
    for msg := range ch {
        sendFrame(c, topic, msg)
    }
}
```

### 3.3 HTTP 控制面 — `internal/controller/relay/v1/relay.go`

```go
type ControllerV1 struct{}

func (c *ControllerV1) CreateRoom(r *ghttp.Request) {
    var req struct{ DeviceID, Alias string; MaxPlayers int }
    r.Parse(&req)
    snap, _ := relay.Default().CreateRoom(Peer{...}, req.MaxPlayers)
    r.Response.WriteJsonAndExit(map[string]any{
        "roomCode": snap.Code,
        "wsUrl":    wsURL(r, snap.Code),
    }, 201)
}

func (c *ControllerV1) JoinRoom(r *ghttp.Request) {
    code := r.Get("code").String()
    var req struct{ DeviceID, Alias string }
    r.Parse(&req)
    snap, _ := relay.Default().JoinRoom(code, Peer{...})
    // 关键：success 后广播 room-snapshot 给所有订阅者
    relay.Default().NotifyRoomEvent(code, host.DeviceID, "room-snapshot", buildSnap(snap))
    r.Response.WriteJsonAndExit(map[string]any{
        "roomCode": snap.Code,
        "wsUrl":    wsURL(r, snap.Code),
    }, 200)
}

func (c *ControllerV1) NotifyEvent(r *ghttp.Request) {
    code := r.Get("code").String()
    var req struct{ DeviceID, Type string; Payload json.RawMessage }
    r.Parse(&req)
    relay.Default().NotifyRoomEvent(code, req.DeviceID, req.Type, req.Payload)
}
```

## 4. 前端关键代码（Dart）

### 4.1 RelayTransport — `lib/core/net_engine/relay/relay_transport.dart`

```dart
class RelayTransport {
  final String relayUrl;
  final String alias;
  final String deviceId;
  late WebSocketChannel _ws;
  late StreamSubscription _sub;
  final _roomCtrls = <String, StreamController<RelayFrame>>{};

  Future<RelayRoom> createRoom({int maxPlayers = 2}) async {
    final resp = await http.post(Uri.parse('$relayUrl/api/v1/relay/rooms'), body: ...);
    final j = jsonDecode(resp.body);
    await _connect(j['wsUrl'] as String);
    return RelayRoom(code: j['roomCode'], transport: this);
  }

  Future<RelayRoom> joinRoom(String code) async {
    final resp = await http.post(Uri.parse('$relayUrl/api/v1/relay/rooms/$code/join'), body: ...);
    final j = jsonDecode(resp.body);
    await _connect(j['wsUrl'] as String);
    return RelayRoom(code: code, transport: this);
  }

  void joinScope(String scope) {
    _send({
      'channelName': 'subscribe',
      'sourceDeviceId': deviceId,
      'payload': jsonEncode({'scope': scope}),
    });
  }

  void broadcastScope(String scope, Map<String, dynamic> state) {
    _send({
      'channelName': 'publish',
      'sourceDeviceId': deviceId,
      'payload': jsonEncode({'scope': scope, 'state': state}),
    });
  }

  Stream<Map<String, dynamic>> watchScope(String scope) {
    final ctrl = _roomCtrls.putIfAbsent(
      scope,
      () => StreamController<Map<String, dynamic>>.broadcast(),
    );
    return ctrl.stream;
  }
}
```

### 4.2 RelayRoomWidget — `lib/core/net_engine/relay/relay_room_widget.dart`

```dart
class RelayRoomWidget {
  Widget buildPage({
    required void Function(RelayTransport, String code) onRoomReady,
  }) {
    return _RelayRoomWidgetInternal(...);
  }
}

class _RelayRoomWidgetInternal extends StatefulWidget {
  void _subscribe() {
    final sub = widget.transport.watchScope('room/${code}/events').listen((event) {
      final type = event['type'];
      switch (type) {
        case 'peer-joined':
          // 追加到 onlineAliases
          break;
        case 'peer-left':
          // 移除
          break;
        case 'room-snapshot':
          // 整体替换 onlineAliases
          break;
      }
    });
  }
}
```

### 4.3 NetP2PChatPage — `lib/core/net_p2p/pages/net_p2p_chat_page.dart`

```dart
class _NetP2PChatPageState extends State<NetP2PChatPage> {
  @override
  void initState() {
    super.initState();
    // ⚠️ 必须先 joinScope，再 watchScope + broadcastScope
    widget.transport.joinScope(widget.scope);
    widget.transport.watchScope(widget.scope).listen(_onEvent);
    widget.transport.broadcastScope(widget.scope, initialState);
  }
}
```

## 5. 端到端流程 — v1 Relay 加入房间

```
Host                                Guest                          Server
  │                                    │                              │
  │ POST /api/v1/relay/rooms           │                              │
  ├──────────────────────────────────────────────────────────────────>│
  │ <──── 201 {roomCode, wsUrl}         │                              │
  │                                    │                              │
  │ WS connect wsUrl                   │                              │
  ├═══════════════════════════════════════════════════════════════════>│
  │ <═ server 推 room-snapshot(只有 host)                              │
  │                                    │                              │
  │                                    │ POST /api/v1/relay/rooms/X/join
  │                                    ├──────────────────────────────>│
  │                                    │ <──── 200 {roomCode, wsUrl}   │
  │                                    │                              │
  │                                    │ WS connect wsUrl             │
  │                                    ├═══════════════════════════════>│
  │                                    │ <═ room-snapshot(host+guest) ═│
  │ <─ server 推 room-snapshot(host+guest) ── 广播给所有订阅者 ──────── │
  │                                    │                              │
  │ 发消息：POST /api/v1/relay/rooms/X/events                          │
  │ {type: "scope-update", scope, state}                              │
  ├──────────────────────────────────────────────────────────────────>│
  │                                    │ <════════════════════════════│
  │                                    │  ← 收到 scope-update          │
  │                                    │  → DataLog.applyRemote        │
  │                                    │  → watchScope 通知 UI          │
```

## 6. v1 的核心弱点

### 6.1 晚加入者错过事件

事件 `peer-joined` 在 guest 连 WS **之前** 发出 → guest 永远看不到这条事件 → guest 觉得"房间里没人"。

**v1 缓解**：服务端 WS 升级时立即推一份 `room-snapshot`。但 `room-snapshot` 只在特定时机（JoinRoom 后）触发，**业务状态变化不触发**。

### 6.2 业务状态需要双向同步

聊天页用 `scope-update` 传递业务 state — 但**只有发起方在本地 DataLog**，对端收到的 update 没有完整历史。

**v1 缓解**：靠 `DataLog.applyRemote` 合并 + `_scopeCtrls[scope]` 缓存；但 DataLog 的 merge 逻辑是 v1 自己维护的，bug 多。

### 6.3 relay scope 名拼接 bug

```dart
// 错：scope 会被 joinScope 自动追加 "/events"
transport.joinScope('room/$code/events');
// 实际发送的 channelName = "subscribe room/$code/events/events"

// 对：传裸 room scope，让 joinScope 自动拼
transport.joinScope('room/$code');
```

## 7. v1 与 v2 的 API 对照

| 业务需求 | v1 | v2 |
|---|---|---|
| 创建房间 | `POST /api/v1/relay/rooms` | `POST /api/v2/relay_snapshot/rooms` |
| 加入房间 | `POST /api/v1/relay/rooms/{code}/join` | `POST /api/v2/relay_snapshot/rooms/{code}/join` |
| 业务动作 | `POST /api/v1/relay/rooms/{code}/events` (自定义 type) | `POST /api/v2/relay_snapshot/rooms/{code}/action` (内置 type) |
| WS endpoint | `wss://.../api/v1/relay/ws/{code}` | `wss://.../api/v2/relay_snapshot/ws/{code}` |
| 推送内容 | `peer-joined` / `peer-left` / `scope-update` / `room-snapshot` | **全量 snapshot** (一次替换整个 state) |
| 晚加入者保障 | 部分（只 room-snapshot，业务 state 不推） | **完整**（WS 连接即收到完整 snapshot） |
| 客户端复杂度 | 高（要合并事件 + 还原状态） | **零**（整体替换 state） |

## 8. v1 的适用场景

- LAN 模式（LanTransport **不**走 v1 — 它走 UDP scope-update，**结构相似**但底层不同）
- 老 Relay 房间 / 老 chat 功能
- 不需要严格状态同步的临时互动

## 9. 关键文件索引

| 文件 | 内容 |
|---|---|
| 后端 `internal/relay/relay.go` | v1 房间存储 |
| 后端 `internal/relay/transport.go` | v1 WS 升级 |
| 后端 `internal/controller/relay/v1/relay.go` | v1 HTTP 控制面 |
| 前端 `lib/core/net_engine/relay/relay_transport.dart` | v1 客户端 transport |
| 前端 `lib/core/net_engine/relay/relay_room_widget.dart` | v1 大厅页 |
| 前端 `lib/core/net_p2p/pages/net_p2p_chat_page.dart` | v1 聊天页 |