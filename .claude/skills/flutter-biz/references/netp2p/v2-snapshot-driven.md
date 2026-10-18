---
name: v2-snapshot-driven
description: v2 协议详细参考 — snapshot/快照驱动模型，由 RelaySnapshotTransport 使用。推荐新功能默认走这个版本。排查"晚加入者错过事件""两端不同步""房间状态丢失"等问题时优先读
---

# V2 Snapshot-Driven Protocol

Relay 协议 v2 = snapshot/快照模型。**服务端权威 snapshot，客户端零合并算法**。

> 新功能 / 新业务 / 严格状态同步场景 → 走 v2。  
> LAN 模式保留 v1，不在此 ref 范围。

## 1. 核心架构

```
Biz Layer
  │  RelaySnapshotTransport.createRoom / joinRoom / applyAction
  ▼
RelaySnapshotTransport (前端)
  │  WS 帧 — channelName = "snapshot/<code>" 一次订阅永不过期
  ▼
Relay Server (后端)
  │  Service (单例) 持有 map[code]*RoomState
  │  任何 mutate 自动 version++ + Publish 完整 snapshot JSON
  ▼
所有订阅者（host + guests）
  │  onSnapshot 整体替换本地 state
```

**单源权威**：服务端 snapshot 字段是整个房间状态机。  
**零合并**：客户端不做事件合并、不做 diff——每次推送直接整体替换。

## 2. Snapshot 数据结构

```typescript
type Snapshot = {
  code: string;               // 6 位数字房间号
  host: Player;               // 房主
  players: Player[];          // 已加入的成员（含 host 也可能在 players 中）
  maxPlayers: number;         // 容量上限
  schema: object;             // 业务定义（角色池、地图尺寸等）
  status: 'waiting' | 'playing' | 'ended';
  version: number;            // 单调递增，客户端可用于去重
  custom: object;             // 业务自定义字段（messages / deals / round）
  updatedAt: string;          // RFC3339
}

type Player = {
  deviceId: string;
  alias: string;
  role?: string;              // 业务层分配（卧底 / 平民）
  online: boolean;
  custom?: object;
}
```

**字段归属**：
- 框架字段（必须）：`code`, `host`, `players`, `maxPlayers`, `schema`, `status`, `version`, `custom`, `updatedAt`
- 业务字段（按需写入 `custom`）：聊天消息、发牌、回合数等

## 3. 服务端关键代码（Go）

### 3.1 Snapshot + RoomState — `internal/relay_snapshot/state.go`

```go
type Snapshot struct {
    Code       string                 `json:"code"`
    Host       Player                 `json:"host"`
    Players    []Player               `json:"players"`
    MaxPlayers int                    `json:"maxPlayers"`
    Schema     map[string]interface{} `json:"schema"`
    Status     string                 `json:"status"`
    Version    int                    `json:"version"`
    Custom     map[string]interface{} `json:"custom"`
    UpdatedAt  string                 `json:"updatedAt"`
}

type RoomState struct {
    mu       sync.Mutex
    Snapshot Snapshot
}

type Service struct {
    mu     sync.RWMutex
    rooms  map[string]*RoomState
    codes  *codeGenerator
    tokens map[string]string
}

var defaultSvc *Service  // 单例
```

### 3.2 房间操作

```go
// 建房
func (s *Service) CreateRoom(host Player, maxPlayers int, schema map[string]interface{}) (*Snapshot, error) {
    if maxPlayers < 2 { maxPlayers = 2 }
    code, _ := s.codes.next(s.codeExists)  // 6 位数字 + 碰撞重试
    snap := Snapshot{
        Code: code, Host: host,
        Players: []Player{host}, MaxPlayers: maxPlayers,
        Schema: schema, Status: "waiting", Version: 1,
        Custom: map[string]interface{}{},
        UpdatedAt: nowISO(),
    }
    s.mu.Lock()
    s.rooms[code] = &RoomState{Snapshot: snap}
    s.tokens[code] = generateToken()
    s.mu.Unlock()
    s.broadcast(code)
    return &snap, nil
}

// 加入
func (s *Service) JoinRoom(code string, guest Player) (*Snapshot, error) {
    if _, ok := s.get(code); !ok { return nil, ErrRoomNotFound }
    s.mutate(code, func(snap *Snapshot) {
        // 同 deviceId 重连：更新 alias + online
        already := false
        for i := range snap.Players {
            if snap.Players[i].DeviceID == guest.DeviceID {
                snap.Players[i].Alias = guest.Alias
                snap.Players[i].Online = true
                already = true
                break
            }
        }
        // 新加入
        if !already {
            if len(snap.Players) >= snap.MaxPlayers { return }
            guest.Online = true
            snap.Players = append(snap.Players, guest)
        }
    })
    s.broadcast(code)
    return s.Snapshot(code)
}

// 退出
func (s *Service) LeaveRoom(code, deviceID string) (*Snapshot, error) {
    s.mutate(code, func(snap *Snapshot) {
        for i, p := range snap.Players {
            if p.DeviceID == deviceID {
                snap.Players = append(snap.Players[:i], snap.Players[i+1:]...)
                break
            }
        }
        if snap.Host.DeviceID == deviceID {
            snap.Status = "ended"
        }
    })
    return s.Snapshot(code)
}

// 业务动作入口（chat 已内置，其他写到 lastAction）
func (s *Service) ApplyAction(code, deviceID, actionType string, payload map[string]interface{}) (*Snapshot, error) {
    s.mutate(code, func(snap *Snapshot) {
        if actionType == "chat" {
            text, _ := payload["text"].(string)
            if text == "" { return }
            msgs, _ := snap.Custom["messages"].([]interface{})
            msgs = append(msgs, map[string]interface{}{
                "from": deviceID, "alias": payload["alias"],
                "text": text, "ts": payload["ts"],
            })
            snap.Custom["messages"] = msgs
            return
        }
        snap.Custom["lastAction"] = map[string]interface{}{
            "type": actionType, "by": deviceID, "payload": payload, "ts": nowISO(),
        }
    })
    s.broadcast(code)
    return s.Snapshot(code)
}
```

### 3.3 mutate + broadcast

```go
// mutate：在锁内改 snapshot，自动 version++ + UpdatedAt 刷新
func (s *Service) mutate(code string, fn func(*Snapshot)) {
    rs, ok := s.get(code)
    if !ok { return }
    rs.mu.Lock()
    defer rs.mu.Unlock()
    fn(&rs.Snapshot)
    rs.Snapshot.Version++
    rs.Snapshot.UpdatedAt = nowISO()
}

// broadcast：推送完整 snapshot JSON 到 snapshot/<code> topic
func (s *Service) broadcast(code string) {
    snap, _ := s.Snapshot(code)
    raw, _ := json.Marshal(snap)
    wrapped, _ := json.Marshal(map[string]interface{}{
        "channelName":    "snapshot/" + code,
        "sourceDeviceId": "",
        "payload":        string(raw),
        "timestamp":      nowISO(),
    })
    relay.Default().Publish("snapshot/"+code, wrapped)
}
```

### 3.4 WS 升级 — `internal/relay_snapshot/transport.go`

```go
func HandleWS(c *gfnet.WebSocketConn, code string) {
    topic := "snapshot/" + code
    ch := relay.Default().Subscribe(topic)
    defer relay.Default().Unsubscribe(topic, ch)

    // ★ 关键：连上立即推一次完整 snapshot 给新订阅者
    if err := pushInitialSnapshot(c, code); err != nil {
        return
    }

    // 启动 goroutine 转发客户端帧 -> publish
    go func() {
        for {
            _, msg, err := c.ReadMessage()
            if err != nil { return }
            relay.Default().Publish(topic, msg)
        }
    }()

    // 主循环：snapshot topic → 客户端
    for msg := range ch {
        if err := c.WriteMessage(websocket.TextMessage, msg); err != nil {
            return
        }
    }
}

func pushInitialSnapshot(c *gfnet.WebSocketConn, code string) error {
    snap, err := Default().Snapshot(code)
    if err != nil { return err }
    raw, _ := json.Marshal(snap)
    wrapped, _ := json.Marshal(map[string]interface{}{
        "channelName":    "snapshot/" + code,
        "sourceDeviceId": "",
        "payload":        string(raw),
        "timestamp":      nowISO(),
    })
    return c.WriteMessage(websocket.TextMessage, wrapped)
}
```

### 3.5 HTTP 控制面 — `internal/controller/relay/v2/relay.go`

```go
type ControllerV2 struct{}

func (c *ControllerV2) CreateRoom(r *ghttp.Request) {
    var req struct {
        DeviceID string                 `json:"deviceId"`
        Alias    string                 `json:"alias"`
        MaxPlayers int                  `json:"maxPlayers"`
        Schema   map[string]interface{} `json:"schema"`
    }
    r.Parse(&req)
    snap, err := relay_snapshot.Default().CreateRoom(
        Player{DeviceID: req.DeviceID, Alias: req.Alias},
        req.MaxPlayers, req.Schema,
    )
    if err != nil { r.Response.WriteJsonAndExit(ErrResp(err), 500); return }
    r.Response.WriteJsonAndExit(map[string]any{
        "roomCode": snap.Code,
        "wsUrl":    wsURL(r, snap.Code),
    }, 201)
}

func (c *ControllerV2) JoinRoom(r *ghttp.Request) {
    code := r.Get("code").String()
    var req struct { DeviceID, Alias string }
    r.Parse(&req)
    snap, err := relay_snapshot.Default().JoinRoom(code, Player{DeviceID: req.DeviceID, Alias: req.Alias})
    if err != nil { setStatus(r, err); return }
    r.Response.WriteJsonAndExit(map[string]any{
        "roomCode": snap.Code,
        "wsUrl":    wsURL(r, snap.Code),
    }, 200)
}

func (c *ControllerV2) Action(r *ghttp.Request) {
    code := r.Get("code").String()
    var req struct {
        DeviceID string                 `json:"deviceId"`
        Type     string                 `json:"type"`
        Payload  map[string]interface{} `json:"payload"`
    }
    r.Parse(&req)
    snap, err := relay_snapshot.Default().ApplyAction(code, req.DeviceID, req.Type, req.Payload)
    if err != nil { setStatus(r, err); return }
    r.Response.WriteJsonAndExit(snap, 200)
}

func (c *ControllerV2) Snapshot(r *ghttp.Request) {
    code := r.Get("code").String()
    snap, err := relay_snapshot.Default().Snapshot(code)
    if err != nil { setStatus(r, err); return }
    r.Response.WriteJsonAndExit(snap, 200)
}
```

### 3.6 路由注册 — `internal/cmd/cmd.go`

```go
g := g.Server()
g.Group("/api/v2", func(group *ghttp.RouterGroup) {
    group.Bind(relayv2controller.New())
})
g.GET("/api/v2/relay_snapshot/ws/{code}", func(r *ghttp.Request) {
    relay_snapshot.HandleWS(r.WebSocket, r.Get("code").String())
})
```

### 3.7 错误码映射

```go
// internal/relay_snapshot/errors.go
var (
    ErrRoomNotFound  = errors.New("room not found")       // 404
    ErrRoomFull      = errors.New("room full")             // 409
    ErrMissingField  = errors.New("missing field")         // 400
    ErrInvalidCode   = errors.New("invalid code")          // 400
)

// controller 用 setStatus 映射
func setStatus(r *ghttp.Request, err error) {
    switch {
    case errors.Is(err, relay_snapshot.ErrRoomNotFound):
        r.Response.WriteJsonAndExit(errBody(err), 404)
    case errors.Is(err, relay_snapshot.ErrRoomFull):
        r.Response.WriteJsonAndExit(errBody(err), 409)
    default:
        r.Response.WriteJsonAndExit(errBody(err), 400)
    }
}
```

## 4. 前端关键代码（Dart）

### 4.1 RelaySnapshotTransport — `lib/core/net_engine/relay_snapshot/relay_snapshot_transport.dart`

```dart
class RelaySnapshotTransport {
  final String relayUrl;
  final String alias;
  final String deviceId = '${microsecondsSinceEpoch}-${ms%1000}';
  final http.Client _http;

  Future<RoomHandle> createRoom({
    int maxPlayers = 2,
    Map<String, dynamic> schema = const {},
  }) async {
    final resp = await _http.post(
      Uri.parse('$relayUrl/api/v2/relay_snapshot/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceId': deviceId, 'alias': alias,
        'maxPlayers': maxPlayers, 'schema': schema,
      }),
    );
    final j = jsonDecode(resp.body);
    final handle = RoomHandle._(
      transport: this, code: j['roomCode'], wsUrl: j['wsUrl'],
      myDeviceId: deviceId,
    );
    await handle.connect();
    return handle;
  }

  Future<RoomHandle> joinRoom(String code) async {
    final resp = await _http.post(
      Uri.parse('$relayUrl/api/v2/relay_snapshot/rooms/$code/join'),
      ...,
    );
    final j = jsonDecode(resp.body);
    final handle = RoomHandle._(transport: this, code: j['roomCode'], wsUrl: j['wsUrl'], myDeviceId: deviceId);
    await handle.connect();
    return handle;
  }
}
```

### 4.2 RoomHandle

```dart
class RoomHandle {
  final RelaySnapshotTransport transport;
  final String code, wsUrl, myDeviceId;
  WebSocketChannel? _ws;
  StreamSubscription? _sub;

  final _snapshotCtrl = StreamController<Snapshot>.broadcast();
  Stream<Snapshot> get snapshots => _snapshotCtrl.stream;
  Snapshot? _latest;
  Snapshot? get latest => _latest;

  Future<void> connect() async {
    final ws = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    _ws = ws;
    ws.sink.add(jsonEncode({
      'channelName': 'identify',
      'sourceDeviceId': myDeviceId,
      'payload': base64Encode(utf8.encode(jsonEncode({'alias': transport.alias}))),
      'timestamp': DateTime.now().toIso8601String(),
    }));
    _sub = ws.stream.listen(_onFrame);
  }

  void _onFrame(dynamic data) {
    if (data is! String) return;
    final env = jsonDecode(data) as Map<String, dynamic>;
    if (env['channelName'] == 'identify' || env['channelName'] == null) return;
    final payloadStr = env['payload'];
    if (payloadStr is! String || payloadStr.isEmpty) return;
    final snap = Snapshot.fromJson(jsonDecode(payloadStr) as Map<String, dynamic>);
    _latest = snap;
    _snapshotCtrl.add(snap);   // ★ 整体替换，不需要合并
  }

  Future<void> applyAction(String type, Map<String, dynamic> payload) async {
    await transport._http.post(
      Uri.parse('${transport.relayUrl}/api/v2/relay_snapshot/rooms/$code/action'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code, 'deviceId': myDeviceId,
        'type': type, 'payload': payload,
      }),
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _ws?.sink.close();
    await _snapshotCtrl.close();
  }
}
```

### 4.3 Snapshot 解析

```dart
class Snapshot {
  final String code;
  final SnapshotPlayer host;
  final List<SnapshotPlayer> players;
  final int maxPlayers;
  final Map<String, dynamic> schema;
  final String status;
  final int version;
  final Map<String, dynamic> custom;

  factory Snapshot.fromJson(Map<String, dynamic> j) {
    final hostJson = (j['host'] as Map?)?.cast<String, dynamic>() ?? const {};
    final playersJson = (j['players'] as List?) ?? const [];
    return Snapshot(
      code: j['code'] ?? '',
      host: SnapshotPlayer.fromJson(hostJson),
      players: playersJson
          .whereType<Map>()
          .map((p) => SnapshotPlayer.fromJson(p.cast<String, dynamic>()))
          .toList(),
      maxPlayers: (j['maxPlayers'] as num?)?.toInt() ?? 2,
      schema: (j['schema'] as Map?)?.cast<String, dynamic>() ?? const {},
      status: j['status'] ?? 'waiting',
      version: (j['version'] as num?)?.toInt() ?? 0,
      custom: (j['custom'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}
```

### 4.4 业务层使用示例

```dart
// 房主建房
final transport = RelaySnapshotTransport(relayUrl: '...', alias: 'Alice');
final handle = await transport.createRoom(maxPlayers: 2);

// 玩家加入
final transport = RelaySnapshotTransport(relayUrl: '...', alias: 'Bob');
final handle = await transport.joinRoom('123456');

// 订阅 snapshot 流
handle.snapshots.listen((snap) {
  // 整体替换本地状态，UI 自动重绘
});

// 发消息
await handle.applyAction('chat', {
  'from': handle.myDeviceId,
  'alias': handle.transport.alias,
  'text': 'Hello',
  'ts': DateTime.now().toIso8601String(),
});
```

### 4.5 完整聊天页 — `lib/core/net_p2p/pages/net_p2p_snapshot_chat.dart`

```dart
class NetP2PSnapshotChatPage extends StatefulWidget {
  final RoomHandle handle;
  final String myDeviceId;
  final VoidCallback? onLeave;

  @override
  State<NetP2PSnapshotChatPage> createState() => _NetP2PSnapshotChatPageState();
}

class _NetP2PSnapshotChatPageState extends State<NetP2PSnapshotChatPage> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  StreamSubscription<Snapshot>? _sub;
  Snapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.handle.latest;
    _sub = widget.handle.snapshots.listen((snap) {
      if (!mounted) return;
      setState(() => _snapshot = snap);
      _scrollToBottom();
    });
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    await widget.handle.applyAction('chat', {
      'from': widget.myDeviceId,
      'alias': widget.handle.transport.alias,
      'text': text,
      'ts': DateTime.now().toIso8601String(),
    });
  }

  List<_ChatMsg> _extractMessages() {
    final snap = _snapshot;
    if (snap == null) return const [];
    final raw = snap.custom['messages'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((m) => _ChatMsg.fromJson(m.cast<String, dynamic>(), widget.myDeviceId)).toList();
  }

  Widget build(BuildContext context) {
    final snap = _snapshot!;
    final all = <String, SnapshotPlayer>{
      snap.host.deviceId: snap.host,
      for (final p in snap.players) p.deviceId: p,
    };
    final peersMap = <String, String>{
      for (final p in all.values) p.deviceId: p.alias,
    };
    final msgs = _extractMessages();
    return Scaffold(
      appBar: AppBar(title: Text('房间 ${snap.code} · ${snap.status}')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: LobbyParticipants(
            capacity: snap.maxPlayers,
            participants: peersMap,
            slotSize: 56,
          ),
        ),
        Expanded(child: _buildMsgList(msgs)),
        _buildInput(),
      ]),
    );
  }
}
```

## 5. 端到端流程 — v2 Snapshot 加入房间

```\nHost                                Guest                          Server\n  │                                    │                              │\n  │ POST /api/v2/relay_snapshot/rooms   │                              │\n  ├───────────────────────────────────────────────────────────────────>│\n  │ <──── 201 {roomCode, wsUrl}         │                              │\n  │                                    │                              │\n  │ WS connect wsUrl (identify 帧)      │                              │\n  ├═══════════════════════════════════════════════════════════════════>│\n  │ <═ server pushInitialSnapshot(host)═══════════════════════════════ │\n  │ ← host 立刻看到自己 + version=1                                  │\n  │                                    │                              │\n  │                                    │ POST /api/v2/relay_snapshot/rooms/X/join\n  │                                    ├──────────────────────────────>│\n  │                                    │ <──── 200 {roomCode, wsUrl}   │\n  │                                    │                              │\n  │ ← server broadcast snapshot(host+guest) 广播给所有订阅者 ─────── │\n  │                                    │                              │\n  │                                    │ WS connect wsUrl (identify 帧)│\n  │                                    ├═══════════════════════════════>│\n  │                                    │ <═ server pushInitialSnapshot ═│\n  │                                    │  ← guest 立刻看到 host + guest│\n  │                                    │  ← version=2                │\n  │                                    │                              │\n  │ 发消息：POST /api/v2/relay_snapshot/rooms/X/action                │\n  │ {type:\"chat\", payload: {text, alias, from, ts}}                  │\n  ├───────────────────────────────────────────────────────────────────>│\n  │                                    │                              │\n  │ ← server mutate snapshot.custom.messages + broadcast ──────────── │\n  │ <═════════════════════════════════════════════════════════════════ │\n  │                                    │ <════════════════════════════│\n  │  Host + Guest 都看到新消息                                       │\n```\n\n## 6. v2 核心保证\n\n### 6.1 晚加入者绝不丢状态\n\n`pushInitialSnapshot` 在 WS 升级后**立即**推送完整 snapshot——新订阅者永远不会错过 state。\n\n### 6.2 客户端零合并算法\n\n每次推送整体替换本地 `_latest` + Stream 通知 UI。无 event merging、无 DataLog、无 conflict resolution。\n\n### 6.3 业务状态强一致\n\n`messages` / `deals` / `round` 等业务数据全部在 `snapshot.custom` 中——所有订阅者看到的永远是同一份 state，无最终一致性问题。\n\n### 6.4 内置 chat action\n\n`ApplyAction(code, deviceID, \"chat\", payload)` 自动追加到 `custom.messages`，无需业务层手动维护。\n\n## 7. v2 的取舍\n\n### 7.1 流量\n\nv2 每次状态变化推完整 snapshot。2 人聊天场景下：每个消息推送一次 ~500 字节 snapshot — 流量可忽略。\n\n100 人聊天室 / 每秒 10 条消息：每次推送 ~10KB，1Mbps 带宽够用。\n\n### 7.2 服务端权威\n\n所有 mutate 都在服务端。客户端**不能**本地修改 state。这是有意为之——保证全局一致。\n\n### 7.3 v2 没有 v1 的灵活性\n\nv1 可以自定义事件类型（`peer-joined`、`game-state-update` 等）；v2 的 action 类型由 server 决定（目前只有 `chat` + `lastAction`）。扩展自定义 action 需要修改 server 的 `ApplyAction`。\n\n## 8. 与 NetP2P 业务的接入模式\n\n### 8.1 NetP2PPage — `lib/core/net_p2p/net_p2p_discovery_host.dart`\n\n```dart\nFuture<void> _onSnapshotRelayRoomReady(fw.RelayTransport v1Transport, String code) async {\n    final snap = RelaySnapshotTransport(\n      relayUrl: 'http://47.110.80.47:8988',\n      alias: '我',\n    );\n    final handle = await snap.joinRoom(code);\n    v1Transport.close();  // 关闭旧 v1 transport\n    setState(() {\n      _snapshotTransport = snap;\n      _snapshotRoom = handle;\n      _inSnapshotChat = true;\n    });\n}\n```\n\n### 8.2 业务 UI 完全由 snapshot 驱动\n\n```dart\nStreamBuilder<Snapshot>(\n  stream: handle.snapshots,\n  builder: (ctx, snap) {\n    if (!snap.hasData) return LoadingPage();\n    return ChatPage(snapshot: snap.data!);\n  },\n);\n```\n\nUI 任何状态变化（玩家加入、消息、回合）都通过新 snapshot 触发重绘——无需手动管理订阅/取消订阅。\n\n## 9. 关键文件索引\n\n| 文件 | 内容 |\n|---|---|\n| 后端 `internal/relay_snapshot/state.go` | Snapshot + Service + mutate + broadcast |\n| 后端 `internal/relay_snapshot/transport.go` | WS 升级 + pushInitialSnapshot |\n| 后端 `internal/relay_snapshot/codegen.go` | 6 位数字房间号生成器 |\n| 后端 `internal/relay_snapshot/errors.go` | ErrRoomNotFound / ErrRoomFull 等 |\n| 后端 `internal/controller/relay/v2/relay.go` | HTTP 控制面（Create / Join / Action / Snapshot）|\n| 后端 `api/relay/v2/relay.go` | API 入参/出参定义 |\n| 后端 `internal/cmd/cmd.go` | `/api/v2/relay_snapshot/...` 路由注册 |\n| 前端 `lib/core/net_engine/relay_snapshot/relay_snapshot_transport.dart` | Snapshot transport + RoomHandle |\n| 前端 `lib/core/net_p2p/pages/net_p2p_snapshot_chat.dart` | 完整快照聊天页 |\n| 前端 `lib/core/net_p2p/net_p2p_discovery_host.dart` | LAN/Relay 模式入口 + v2 切换 |\n