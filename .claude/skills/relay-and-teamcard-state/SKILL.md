---
name: relay-and-teamcard-state
description: 当用户要求"无背景继续优化"或"总结互联网房间+团建卡牌当前结构"时触发。一份状态快照，含后端路由、前端 Transport、demo 使用方式。
---

# Relay+TeamCard 架构状态快照（2026-07-22）

> 用途：在新会话 / 新 agent 中快速还原上下文，继续优化 lib/core/localnet/ 后端 relay 与 lib/lab/demos/team_card/。

## 1. 整体目标

| 模块 | 文件 | 角色 |
|------|------|------|
| 后端 relay | `D:/code/a_go/leaning/dev_ctr_hello/internal/relay/` | pub/sub 路由，房间生命周期，事件广播 |
| 后端 DTO | `api/relay/v1/relay.go` | CreateReq/CreateRes/JoinReq/StartReq/PeersReq |
| 前端引擎 | `lib/core/localnet/` | Transport 抽象 + RelayTransport + LanTransport + Discovery widgets |
| 业务 demo | `lib/lab/demos/team_card/` | Master 建房 + 发牌 + 旁观 / Player 收身份 |

## 2. 后端 relay（Go）核心结构

**目录**：`internal/relay/`

### 关键文件

| 文件 | 作用 |
|------|------|
| `relay.go` | Service + Room + Peer + Subscriber + Topic 路由表 + NotifyRoomEvent |
| `transport.go` | HandleWS 升级 + 帧路由（identify / publish by topic） |

### 关键模型

```go
type Room struct {
    Code       string
    Host       Peer
    MaxPlayers int
    Schema     map[string]interface{}
    Token      string  // 当前已**完全移除**（生产服务器已部署无 token 版本）
    Guests     []Peer
    CreatedAt  time.Time
    WsURL      string
}

type Subscriber struct {
    DeviceID string
    Alias    string
    Send     chan []byte  // buffered 64
}

type Service struct {
    rooms  map[string]*Room
    topics map[string]map[string]*Subscriber
}
```

### 关键 API（无 token）

| Method | 用途 | 返回 |
|--------|------|------|
| `Service.CreateRoom(input)` | 建房 | `*CreateRoomOutput{code, wsURL}` |
| `Service.Join(input)` | 加入（不再验证 token） | `*Room` |
| `Service.Peers(code)` | 在线订阅者列表 | `[]PeerInfo` |
| `Service.Subscribe(topic, sub)` | 订阅 topic | void |
| `Service.Publish(topic, frame)` | 广播 frame 到 topic | delivered int |
| `Service.NotifyRoomEvent(code, type, data)` | 服务端发事件（room-created/peer-online/peer-left/peer-joined/room-started） | int |

### HTTP 端点（无需鉴权）

| Method | Path | Body | 返回 |
|--------|------|------|------|
| POST | `/api/v1/relay/rooms` | CreateReq | CreateRes（含 wsURL） |
| GET | `/api/v1/relay/rooms/{code}/peers` | - | `{roomCode, peers:[{deviceId,alias}]}` |
| POST | `/api/v1/relay/rooms/{code}/join` | JoinReq（无 token 必填） | JoinRes |
| POST | `/api/v1/relay/rooms/{code}/start` | StartReq（master 调用广播 room-started） | StartRes |
| WS | `/ws/{code}` | - | upgrade + 帧路由 |

### NotifyRoomEvent 事件类型

| Type | Trigger | 数据字段 |
|------|---------|----------|
| `room-created` | CreateRoom 后 | hostDeviceId, hostAlias, maxPlayers |
| `peer-joined` | JoinRoom 后（HTTP 层） | deviceId, alias, role |
| `peer-online` | WS identify 后 | deviceId, alias |
| `peer-left` | WS 断开 | deviceId |
| `room-started` | StartRoom | hostDeviceId, hostAlias, maxPlayers |
| `chat` | 用户 publish | from, alias, text |
| `log` | RelayMessageNet 用 | data (LogEntry 编码) |

### NotifyRoomEvent 关键修改（已部署到生产 47.110.80.47:8988）

事件 publish 包装成标准帧格式 `{channelName, sourceDeviceId, payload, timestamp}`，否则 Dart `_onFrame` 检查 `ch == null` 丢弃。

## 3. 前端 localnet 引擎（Dart）

**目录**：`lib/core/localnet/`

### 关键文件

| 文件 | 作用 |
|------|------|
| `transport.dart` | Transport 抽象 + RoomConfig + RoomInfo + RemoteEvent + NodeRole |
| `relay/relay_transport.dart` | RelayTransport 实现：createRoom/joinRoom/subscribe/publish |
| `relay/relay_discovery.dart` | RelayDiscovery widget（LAN 不需要，直接输入房号） |
| `relay/relay_room_chat.dart` | 2人房开箱即用聊天 widget（房主等 → 加入 → 自动切聊天） |
| `lan/lan_transport.dart` | LAN UDP + HTTP 直连（独立实现，不依赖后端） |
| `lan/lan_discovery.dart` | LAN 发现 widget（UDP 多播 + HTTP 三次握手） |
| `pages/localnet_settings_page.dart` | 设置页（relayUrl、multicastPort 等） |
| `http/http_*.dart` | LocalHttpServer（每设备 HTTP server）+ httpPost 客户端 |
| `transport_event.dart` | **已删除**（合并入 transport.dart，避免双重定义） |

### Transport 抽象（v1 + v2 双轨）

```dart
abstract class Transport {
  String get myNodeId;
  int get myCreatedAt;
  NodeRole get myRole;       // unknown | host | client
  String? get peerNodeId;
  NodeRole get peerRole;

  // v2 pub/sub API
  Future<RoomInfo> createRoom(RoomConfig config);
  Future<void> joinRoom(String code, String token);
  Stream<RemoteEvent> subscribe(String topic);
  Future<void> publish(String topic, Map<String, dynamic> payload);
  Future<void> unsubscribe(String topic);
  Future<void> connect();
  Future<void> close();

  // v1 scope API（标记 @Deprecated 但保留供旧代码）
  Future<void> joinScope(String scope);
  // ... etc
}
```

### RoomConfig / RoomInfo

```dart
class RoomConfig {
  int maxPlayers;          // 默认 2
  Map<String, dynamic> schema;
  bool canStartBeforeFull;
  int autoStartThreshold;
}
class RoomInfo {
  String code, hostNodeId, token; int maxPlayers;
}
```

**注意**：token 已从后端移除，但 RoomInfo 还保留 token 字段（兼容旧代码）。dart 端 joinRoom 传空字符串即可。

## 4. TeamCard Demo

**目录**：`lib/lab/demos/team_card/`

### 文件结构

| 文件 | 行数 | 作用 |
|------|------|------|
| `const_team_card.dart` | ~30 | AliasPrefs（SharedPreferences 持久化别名） + kRelayUrl |
| `team_card_types.dart` | ~120 | RoleDef / CardInfo / kBuiltinPresets / CustomPresetPrefs / roleColor |
| `team_card_master.dart` | ~700 | MasterView（建房+配置+发牌+查看全部） |
| `team_card_player.dart` | ~150 | PlayerView（加入+收身份） |
| `team_card_demo.dart` | ~50 | 入口（DemoPage 注册 + 路由） |

### Master 流程

```dart
final t = await fw.RelayTransport.create(relayUrl: kRelayUrl, alias: _alias);
final info = await t.createRoom(fw.RoomConfig(
  maxPlayers: _roomCapacity,           // 动态计算：master参与=_totalCount，旁观=_totalCount+1
  schema: {'roles': [...]},
  canStartBeforeFull: true,           // 未满也允许开始
));
_sub = t.subscribe('room/${info.code}/events').listen((ev) {
  // 处理 peer-joined/peer-online/peer-left 事件
});
```

### Player 流程

```dart
final t = await fw.RelayTransport.create(relayUrl: kRelayUrl, alias: alias);
await t.joinRoom(code, '');  // 无 token
_sub = t.subscribe('room/$code/events').listen((ev) {
  // 处理 deal 事件
  if (ev.payload['type'] == 'deal') {
    final myRole = assignments[t.myNodeId];
  }
});
```

### 关键 UI 状态

| 状态 | 含义 |
|------|------|
| `_myRole: 'host'` | master 建房后自己也是玩家 |
| `_myRole: 'guest'` | master 仅旁观 |
| `_roomCapacity` | master参与=总数，旁观=总数+1 |
| `_needed` | 还需要几个玩家 |
| `_dealt` | 是否已发牌 |
| `_showAllCards` | 旁观时是否展示全部身份 |

### 预选方案（kBuiltinPresets）

| 名称 | 配置 |
|------|------|
| 谁是卧底(4/6/8人) | 卧底×N, 平民×M |
| 狼人杀(6/8/12人) | 狼×N, 预言家×1, 女巫×1, 村民/守卫/猎人 |

### 自定义预设持久化

- Key: `team_card.alias`（用户名）
- Key: `team_card.custom_presets`（自定义角色配置 JSON）

## 5. 关键经验教训

### 已修复 bug

1. **Token 移除** —— `Service.Join()` 当 token 为空时跳过校验，前端 joinRoom 传 ''
2. **NotifyRoomEvent 帧格式** —— 必须包 `{channelName, sourceDeviceId, payload, timestamp}`，否则 Dart 端 ch==null 丢弃
3. **applyRemote merge 而非 replace** —— DataLog 状态合并
4. **putIfAbsent 而非覆盖** —— joinScope 保留已存在 DataLog
5. **HTTP 兜底** —— 每 3 秒 `fetchPeers()` 弥补事件漏失

### 坑点

- 双 `TransportEvent` 类导致 APK 编译失败（已删除 transport_event.dart）
- 同一 transport 多次 attach 会互相覆盖（adapter 改用实例 per-page 而非全局单例）
- WS identify 后再发 `peer-online` 事件（解决 master 收不到事件问题）
- 房号 6 位数字唯一即可，token 是冗余（已废弃）

## 6. 后续优化方向

### 短期

- [ ] TeamCard demo UI 进一步美化（frontend-design 原则）
- [ ] RelayRoomChatWidget 加入文件/图片传输
- [ ] 后端 Peer disconnect 立即清理（不依赖 TTL）

### 中期

- [ ] LAN 模式也支持 RelayRoomChatWidget 形式
- [ ] 多玩家房（>2）支持（团建卡牌已是基础架构）
- [ ] Schema 校验（按 schema 验证发牌 payload）

### 长期

- [ ] WebRTC P2P 模式（绕过 relay server）
- [ ] 持久化聊天记录（SQLite/SharedPreferences）
- [ ] 端到端加密（基于 schema 自动协商密钥）

## 7. 快速测试指令

```bash
# 启动后端
cd D:/code/a_go/leaning/dev_ctr_hello
go build -o /tmp/relay.exe ./main.go && /tmp/relay.exe &

# 端到端 Python 模拟（已写好）
cd D:/code/a_go/leaning/dev_ctr_hello/.tool/team-card-tester
venv/Scripts/python.exe scripts/simulate.py --players 3

# Flutter 编译
cd D:/code/a_dart/prj/fr
flutter analyze lib/
```

## 8. 部署信息

- **后端生产地址**：`http://47.110.80.47:8988`（已部署无 token + 帧格式修复版本）
- **CI 部署**：`Deploy File Server` workflow（main 分支 push 触发）
- **WS 升级端点**：`ws://47.110.80.47:8988/ws/{code}`

## 8. 何时读 ref

| ref | 何时读取 |
| --- | --- |
| [[engine-usage-inconsistencies]] | 迁移业务层到 v2 / 修不匹配 / 重构 localnet_biz / 长期 v1 清理 |

## 引用索引
