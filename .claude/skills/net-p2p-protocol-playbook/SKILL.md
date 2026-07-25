---
name: net-p2p-protocol-playbook
description: 当用户提及 Relay/LAN/快照/action 流/net_p2p/net_engine 协议、讨论消息传输层（事件 vs 快照）、新建/重构 P2P 协议、排查"晚加入者错过事件""两端不同步""房间状态丢失""广播丢失"等问题时触发。包含 v1 action/事件驱动（已落地，遗留用法）与 v2 快照驱动（推荐新功能）。
---

# Net-P2P Protocol Playbook

小豆子 fr 项目里 **net_engine / net_p2p** 网络协议层的完整参考。

适用：
- LAN 局域网发现 + HTTP 邀请/接受握手（基于 UDP 多播 + 本地 HTTP server）
- Relay 跨网络房间（基于 HTTP 控制面 + WebSocket 帧）
- 房主权威快照模式（v2）vs 事件流模式（v1）

---

## 1. 何时读哪个 ref

| ref | 何时读取 |
|---|---|
| [[references/v2-snapshot-driven]] | **新功能默认走这个**。需要"晚加入者绝不丢状态""广播完整 state""客户端零合并算法"时。互联网 Relay 模式推荐。 |
| [[references/v1-action-driven]] | 维护/重构老代码时。老 LAN 模式（不需升级到 v2 时）。理解为什么 v2 出现。 |

---

## 2. 协议分层总览

```
┌──────────────────────────────────────────────────────────────┐
│                    Biz Layer (net_p2p)                       │
│  NetP2PPage → NetP2PSnapshotChatPage (v2) 或 NetP2PChatPage  │
│  业务只调 transport.createRoom / joinRoom / applyAction       │
├──────────────────────────────────────────────────────────────┤
│                Transport Layer (net_engine)                  │
│  ┌──────────────┐  ┌──────────────────┐  ┌─────────────────┐ │
│  │  LanTransport │  │  RelayTransport   │  │SnapshotTransport│ │
│  │ UDP + HTTP    │  │ WS + topic pubsub│  │ WS + snapshot   │ │
│  └──────────────┘  └──────────────────┘  └─────────────────┘ │
│  ┌──────────────────────────────────────────────────────────┐│
│  │             LanDiscovery / RelayDiscovery               ││
│  │   (LAN 扫描 + 邀请握手)  (Relay 建房/加入)              ││
│  └──────────────────────────────────────────────────────────┘│
├──────────────────────────────────────────────────────────────┤
│              Backend (/api/v2/relay_snapshot)                │
│  Snapshot 单一权威源 → 任何动作广播完整 snapshot             │
│  WS 连接时立即推一份初始 snapshot                            │
└──────────────────────────────────────────────────────────────┘
```

---

## 3. 核心不变量

| 项 | 不变量 |
|---|--------|
| **房间号** | 6 位数字，0-9，碰撞重试 |
| **deviceId** | 启动时 `${microseconds}-${milliseconds%1000}`（无需持久化：每次会话独立） |
| **房间生命周期** | server-driven TTL 30 分钟（v1）/ 手动清理（v2） |
| **消息序列化** | `channelName` + `sourceDeviceId` + `payload`（JSON 文本帧） |
| **可靠性** | v1: UDP fire-and-forget（LAN）/ WS pub/sub（Relay）；v2: WS snapshot 全量覆盖 |
| **API 路径** | v1: `/api/v1/relay/...`；v2: `/api/v2/relay_snapshot/...` |

---

## 4. 速查 — 在新功能里选哪个版本

| 需求 | 推荐版本 |
|---|---|
| 互联网 Relay 房间（跨网络） | **v2 快照** |
| LAN 局域网对战 | v1 action（lan_transport + LanDiscovery 完整现成） |
| 严格状态同步（团建卡牌发牌、游戏回合） | **v2 快照** |
| 自由聊天 / 临时互动 | v1 action 即可 |
| 新业务从零开始 | **v2 快照**（架构干净） |

---

## 5. 端到端流程对照

### 5.1 LAN 模式（v1）

```
Device A                                       Device B
  │                                               │
  │ ① UDP 多播 broadcastDiscovery (每 2s)         │
  ├──────────────────────────────────────────────>│
  │                                               │
  │ ② UDP discovery 包 → _onDatagram              │
  │   触发 peer-joined-scope event                │
  │   _LanDiscoveryPage 收到 → 显示在 list       │
  │                                               │
  │ ③ 用户点 peer → _sendInvite()                 │
  │   HTTP POST /api/v1/invite                    │
  ├──────────────────────────────────────────────>│
  │                                               │
  │ ④ 对端 HTTP server 接收 → 弹接受/拒绝 UI      │
  │   用户点接受 → HTTP POST /api/v1/accept       │
  ├──────────────────────────────────────────────>│
  │                                               │
  │ ⑤ 双方都触发 _completeHandshake →            │
  │   widget.onPeerSelected(peer, transport)     │
  │   biz 层 joinScope('chat-X-Y')              │
  │   进入 chat 页                                │
  │                                               │
  │ ⑥ 发消息：broadcastScope → UDP scope-update │
  │   对端 _onDatagram 收到 → DataLog.applyRemote│
  │   watchScope 通知 → UI 重绘                    │
```

### 5.2 Relay 模式（v2 快照）

```
Host                                              Guest
  │                                                  │
  │ ① POST /api/v2/relay_snapshot/rooms              │
  │   {deviceId, alias, maxPlayers}                  │
  ├──────────────────────────────> Server           │
  │ <──── 201 {roomCode, wsUrl, token}                │
  │                                                  │
  │ ② WS connect wsUrl (identify 帧)                 │
  ├══════════════════════════════> Server               │
  │   server 立即 pushRoomSnapshot(sub, code)        │
  │ <═══════════════════════════════ snapshot{...}    │
  │                                                  │
  │ ③ Guest: POST /api/v2/relay_snapshot/rooms/X/join│
  │   Server 推 room-snapshot 到所有订阅者           │
  │   (Host 收到快照更新)                            │
  │ <─────────────────────────────────────            │
  │                                                  │
  │ ④ Guest: WS connect wsUrl                        │
  │   server 立即 pushRoomSnapshot(sub, code)        │
  │ <═══════════════════════════════ snapshot{...}    │
  │   ← Guest 现在看到 host + 自己 + version=2       │
  │                                                  │
  │ ⑤ 任意一方发消息：                              │
  │   POST /api/v2/relay_snapshot/rooms/X/action     │
  │   {type:'chat', payload:{text, alias, from}}    │
  ├──────────────────────────────> Server           │
  │   mutate snapshot.custom.messages               │
  │   Broadcast snapshot to all subs                │
  │ <═══════════════════════════════ snapshot{...}    │
  │   Host + Guest 都更新 messages                  │
```

---

## 6. 关键文件路径

### 6.1 后端（Go）

| 文件 | 用途 |
|---|---|
| `internal/relay/relay.go` | v1 房间存储 + topic pub/sub |
| `internal/relay/transport.go` | v1 WS 升级端点 |
| `internal/relay_snapshot/state.go` | **v2 Snapshot + Service 单例** |
| `internal/relay_snapshot/transport.go` | **v2 WS + pushInitialSnapshot** |
| `internal/controller/relay/v1/relay.go` | v1 HTTP 控制面 |
| `internal/controller/relay/v2/relay.go` | **v2 HTTP 控制面** |
| `api/relay/v2/relay.go` | **v2 API 入参/出参定义** |
| `internal/cmd/cmd.go` | 注册 `/api/v2/relay_snapshot/...` 路由 |

### 6.2 前端（Dart）

| 文件 | 用途 |
|---|---|
| `lib/core/net_engine/localnet.dart` → 改后 `net_engine.dart` | 框架门面 |
| `lib/core/net_engine/lan/lan_discovery.dart` | LAN 发现 + 邀请/接受 UI |
| `lib/core/net_engine/lan/lan_transport.dart` | LAN UDP transport |
| `lib/core/net_engine/relay/relay_room_widget.dart` | v1 大厅 + LobbyParticipants |
| `lib/core/net_engine/relay_snapshot/relay_snapshot_transport.dart` | **v2 Snapshot transport** |
| `lib/core/net_engine/widgets/participants_grid.dart` | LobbyParticipants 圆环 |
| `lib/core/net_p2p/net_p2p_discovery_host.dart` | NetP2PPage（LAN/Relay 模式切换） |
| `lib/core/net_p2p/pages/net_p2p_snapshot_chat.dart` | **v2 快照聊天页** |
| `lib/core/net_p2p/pages/net_p2p_chat_page.dart` | v1 事件聊天页 |

---

## 7. 常见错误案例（来自开发记录）

| # | 错误 | 实际后果 | 正确做法 |
|---|------|---------|---------|
| 1 | `LanTransport._onDatagram` 不处理 `scope-update` | LAN 消息广播发出后对端收不到 | 必须处理 `scope-update`：解析 → `DataLog.applyRemote` → 推送到 `_scopeCtrls` |
| 2 | 业务层调 `broadcastScope` 但之前没 `joinScope` | `_scopes[scope]==null` → 静默 return，消息丢失 | `initState` 先 `joinScope` 再 `watchScope` |
| 3 | 传 `room/X/events` 给 `RelayTransport.joinScope` | 被自动追加成 `room/X/events/events`，scope 名不匹配 | 传 `room/X`，让 joinScope 自动补 `/events` |
| 4 | Relay 模式 guest 看不到 host | `peer-joined` 事件在 guest 连 WS 前发出 | 服务端 WS 升级时**立即**推 `room-snapshot` 给新订阅者 |
| 5 | 客户端只看 `peer-joined` 事件渲染房间 | 错过早期事件 → 房间看起来是空的 | 改为订阅 snapshot 流，每次替换整个 state |
| 6 | 房主把 `peer-joined` 当作加玩家信号 | guest 此时还没连 WS，收不到 | 服务端广播 + 立即给新 WS 推 snapshot |
| 7 | 用 `subscribe(topic)` + 合并流还原状态 | 重复消息、顺序错乱、晚加入者丢消息 | 整体替换 snapshot — 客户端零合并算法 |
| 8 | LAN discovery 不周期广播 `_broadcastDiscovery()` | 同网络设备互相看不到 | `_startScan` 里加 `Timer.periodic(2s)` |
| 9 | discovery UDP 包不带 `alias` | 列表显示 `from.substring(0, 6)` 的截断 UUID | UDP 包 payload 包含 `alias` 字段 |
| 10 | 业务层直接写 `transport.publish('room/$code/events', ...)` 后端 `NotifyRoomEvent` | 两层抽象混用，易丢事件 | 走 `RelaySnapshotTransport.applyAction` — 服务端权威 mutate |

---

## 8. 测试 checklist（开发时勾选）

- [ ] Host 创建 → 看到自己 + LobbyParticipants 圆环
- [ ] Guest 加入 → **Host 看到 Guest + Guest 看到 Host**（双向可见）
- [ ] Guest 加入 → 立即看到完整 snapshot（不是空房间）
- [ ] 任一方发消息 → 对端 < 1s 内看到
- [ ] 任一方断网 → 服务端广播 `peer-left`，对端 UI 更新
- [ ] WS 断连重连 → 重新建立后能立即收到完整 snapshot
- [ ] 房间 30 分钟无连接 → 服务端自动清理

---

## 9. 与 v1 的关系（迁移指南）

**不要试图把 v1 的全部代码"升级"成 v2**——按场景：

| 场景 | 处理 |
|---|---|
| 新功能 / 新业务 | 直接走 v2 |
| LAN 发现 + 邀请握手 | 保留 v1（LanDiscovery + HTTP server 是完整现成实现） |
| 老 Relay 房间 + v1 event 流 | 保留 v1，不动 |
| 团建卡牌发牌（需严格同步） | 迁移到 v2 snapshot |
| 聊天功能 | 任选；v2 更稳 |