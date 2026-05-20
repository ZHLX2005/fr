---
name: webrtc-infrastructure
description: 当用户要求实现 WebRTC 视频通话、设计 P2P 实时通信系统、搭建 WebRTC 信令基础设施、实现音视频传输或 DataChannel 数据传输时触发。提供从信令协议设计到移动端优化的完整架构指南。
---

# WebRTC 视频电话基础设施与结构设计

## 核心原则

**先信令后媒体，控制面与数据面分离。**

WebRTC 的 P2P 连接依赖信令服务器完成初始握手，信令是"控制面"，媒体/DataChannel 是"数据面"。设计时必须：

1. **信令先行** — 先定义消息协议，再实现媒体交换
2. **Trickle ICE** — ICE candidate 逐条发送，而非等待收集完成
3. **状态驱动** — RTCPeerConnection 的连接状态决定业务状态
4. **分而治之** — 信令、媒体、数据传输各自独立模块

## 触发条件

当用户说以下内容时触发：

- "实现 WebRTC 视频通话"
- "设计 WebRTC 信令系统"
- "WebRTC P2P 通信架构"
- "搭建实时音视频基础设施"
- "DataChannel 文件传输"
- "视频电话功能设计"
- "WebRTC 移动端优化"

## 工作流程

### Step 1: 设计信令协议

定义核心消息类型（参考 `flutter_webrtc_server/pkg/signaler/signaler.go`）：

| 消息类型 | 方向 | 用途 |
|---------|------|------|
| `new` / `join` | Client → Server | 注册 peer，获取在线列表 |
| `offer` | Caller → Server → Callee | 转发 SDP offer |
| `answer` | Callee → Server → Caller | 转发 SDP answer |
| `candidate` | Both → Server → Peer | 转发 ICE candidate |
| `bye` | Either → Server → Both | 结束会话 |
| `leave` | Server → Client | Peer 离线通知 |
| `keepalive` | Both | 心跳保活 |

信令消息格式：
```json
{
  "type": "offer",
  "data": {
    "from": "peer-id",
    "to": "peer-id",
    "session_id": "caller-callee",
    "description": { "sdp": "...", "type": "offer" }
  }
}
```

### Step 2: 实现信令服务器

**职责**：Peer 注册、Session 跟踪、消息转发、TURN 凭证发放

```go
// 核心数据结构
type Signaler struct {
    peers    map[string]Peer    // peer-id → Peer
    sessions map[string]Session // session-id → Session
    turn     *turn.TurnServer
}

// 消息处理逻辑
switch request.Type {
case New:
    s.peers[info.ID] = Peer{conn, info}
    s.NotifyPeersUpdate(s.peers)
case Offer, Answer, Candidate:
    peer := s.peers[negotiation.To]
    s.Send(peer.conn, request) // 直接转发
case Bye:
    // 向会话双方发送 bye
}
```

**TURN 凭证生成**（REST API 规范）：
```go
turnUsername := fmt.Sprintf("%d:%s", timestamp, user)
hmac := hmac.New(sha1.New, []byte(sharedKey))
hmac.Write([]byte(turnUsername))
turnPassword := base64.StdEncoding.EncodeToString(hmac.Sum(nil))
// TTL 默认 86400s，存入 ExpiredMap 自动清理
```

### Step 3: 实现客户端信令层

使用事件总线解耦信令与业务：

```dart
// Dart (Flutter)
_socket?.onMessage = (message) {
  onMessage(_decoder.convert(message));
};

void onMessage(mapData) {
  switch (mapData['type']) {
    case 'offer':  _handleOffer(data); break;
    case 'answer': _handleAnswer(data); break;
    case 'candidate': _handleCandidate(data); break;
    // ...
  }
}
```

```typescript
// TypeScript (Socket.io + EventBus)
this.socket.onAny((event, payload) => {
  this.bus.emit(event, payload);
});
this.bus.on(SERVER_EVENT.SEND_OFFER, this.onReceiveOffer);
this.bus.on(SERVER_EVENT.SEND_ICE, this.onReceiveIce);
```

**连接状态管理**：
```typescript
enum ConnectionState { READY, CONNECTING, CONNECTED }
// 使用 Promise 等待连接建立
private connectedPromise: PromiseWithResolve<void>;
public isConnected() { return this.connectedPromise; }
```

### Step 4: 建立 RTCPeerConnection

**ICE Servers 配置**：
```javascript
const iceServers = [
  { urls: ['stun:stun.l.google.com:19302'] },
  {
    urls: ['turn:host:port'],
    username: '...',
    credential: '...'
  }
];
```

**呼叫方流程**：
```dart
// 1. 创建 RTCPeerConnection
var pc = await createPeerConnection({...iceServers, 'sdpSemantics': 'unified-plan'});

// 2. 添加本地媒体流
_localStream.getTracks().forEach((track) async {
  _senders.add(await pc.addTrack(track, _localStream));
});

// 3. 收集 ICE candidate 并立即发送
pc.onIceCandidate = (candidate) async {
  _send('candidate', {'to': peerId, 'candidate': {...}});
};

// 4. 创建并发送 Offer
var offer = await pc.createOffer();
await pc.setLocalDescription(offer);
_send('offer', {'to': peerId, 'description': {'sdp': offer.sdp, 'type': offer.type}});
```

**被叫方流程**：
```dart
// 1. 收到 offer，设置 remote description
await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));

// 2. 创建并发送 Answer
var answer = await pc.createAnswer();
await pc.setLocalDescription(answer);
_send('answer', {'to': peerId, 'description': {'sdp': answer.sdp, 'type': answer.type}});
```

**ICE Candidate 缓冲**（关键！）：
```dart
// 如果 pc 尚未创建，先缓冲 candidate
if (session.pc != null) {
  await session.pc?.addCandidate(candidate);
} else {
  session.remoteCandidates.add(candidate);
}
// 待 pc 创建后，一次性添加缓冲的 candidates
session.remoteCandidates.forEach((c) async => await pc.addCandidate(c));
session.remoteCandidates.clear();
```

### Step 5: 媒体流管理

**获取本地媒体**：
```dart
final mediaConstraints = {
  'audio': true,
  'video': {
    'mandatory': {'minWidth': '640', 'minHeight': '480', 'minFrameRate': '30'},
    'facingMode': 'user',
  }
};
var stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
```

**屏幕共享**：
```dart
var stream = await navigator.mediaDevices.getDisplayMedia({'video': true});
// 桌面端需要选择窗口/屏幕
final source = await showDialog<DesktopCapturerSource>(...);
stream = await navigator.mediaDevices.getDisplayMedia({
  'video': {'deviceId': {'exact': source.id}}
});
```

**Camera ↔ Screen 切换**（replaceTrack，零中断）：
```dart
_senders.forEach((sender) {
  if (sender.track!.kind == 'video') {
    sender.replaceTrack(newStream.getVideoTracks()[0]);
  }
});
```

**麦克风静音**：
```dart
_localStream!.getAudioTracks()[0].enabled = !enabled;
```

**SDP 兼容性修复**：
```dart
// profile-level-id=640c1f → 42e032 解决某些编解码器不兼容
sdp = sdp.replaceAll('profile-level-id=640c1f', 'profile-level-id=42e032');
```

### Step 6: DataChannel 数据传输（可选）

**创建 DataChannel**：
```typescript
const channel = connection.createDataChannel("file-transfer", {
  ordered: true,        // 保证顺序
  maxRetransmits: 50,   // 最大重传次数
});
```

**分片传输协议**（参考 `filetransfer_p2p`）：

| 字段 | 大小 | 说明 |
|------|------|------|
| ID | 12B | 文件唯一标识 |
| Sequence | 4B | 分片序号（大端） |
| Payload | 变长 | 实际数据 |

**分片大小限制**：
```typescript
let maxSize = connection.sctp?.maxMessageSize || 64 * 1024;
maxSize = Math.min(maxSize, 256 * 1024); // 上限 256KB
// Firefox 可能返回 1GB，必须限制
```

**背压控制**（防止内存溢出）：
```typescript
while (this.tasks.length) {
  const next = this.tasks.shift();
  if (channel.bufferedAmount >= chunkSize) {
    await new Promise(resolve => {
      channel.onbufferedamountlow = () => resolve(0);
    });
  }
  channel.send(buffer);
}
```

**传输流程**：
```
Sender                    Receiver
  │  FILE_START (id, size, total)  │
  │ ─────────────────────────────> │
  │  FILE_NEXT (id, series=0)      │
  │ <───────────────────────────── │
  │  Binary Chunk [id|seq|data]    │
  │ ─────────────────────────────> │
  │  FILE_NEXT (id, series=1)      │
  │ <───────────────────────────── │
  │  ...                           │
  │  FILE_FINISH (id)              │
  │ <───────────────────────────── │
```

### Step 7: 移动端优化

**后台恢复**（关键！信令断开不重置 RTC）：
```typescript
this.signaling.socket.on("connect", () => {
  // FIX: 移动端后台恢复时，信令重连但 RTC 仍保持
  if (this.instance?.connection.connectionState === "connected") {
    return; // 不创建新实例
  }
  // ...
});
```

**会话去重**（防止标签页复制导致 ID 冲突）：
```typescript
// LRU Session + performance.navigation 检测
const sessionId = getSessionId(); // 从 storage 读取或生成
// socket.io auth 携带 sessionId
io(wss, { transports: ["websocket"], auth: { sessionId } });
```

**连接状态监听**：
```typescript
connection.onconnectionstatechange = () => {
  if (connection.connectionState === "connected") {
    atoms.set(stateAtom, CONNECTION_STATE.CONNECTED);
  }
  if (["disconnected", "failed", "closed"].includes(connection.connectionState)) {
    atoms.set(stateAtom, CONNECTION_STATE.READY);
  }
};
```

## 寻找指令示例

扫描信令相关代码：
```
Grep: offer | answer | candidate | signaling | RTCPeerConnection
Glob: **/signaling.{go,ts,dart}
```

读取信令服务器核心：
```
Read: pkg/signaler/signaler.go
Read: lib/src/call_sample/signaling.dart
```

读取客户端连接管理：
```
Read: packages/webrtc-im/client/service/webrtc.ts
Read: packages/webrtc-im/client/service/transfer.ts
```

## 适用场景

✅ 一对一视频通话  
✅ 多人会议（需扩展 SFU/MCU）  
✅ P2P 文件传输（DataChannel）  
✅ 屏幕共享  
✅ 实时消息（DataChannel）  
✅ NAT 穿透（STUN/TURN）  
✅ 移动端音视频应用  

❌ 大规模直播（需要 CDN/RTMP，非 WebRTC 强项）  
❌ 纯服务器中转（用 WebSocket 即可，无需 WebRTC）  
❌ 高并发信令（需考虑信令服务器水平扩展）  

## 错误案例

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| ICE candidate 到达时 pc 未创建，直接丢弃 | 部分 candidate 丢失，P2P 连接失败或延迟高 | 使用 remoteCandidates 缓冲列表，待 pc 创建后统一添加 |
| 等待所有 ICE candidate 收集完成再发送 SDP | 连接建立延迟 5-15 秒 | 使用 Trickle ICE，candidate 逐条实时发送 |
| DataChannel 发送不做背压控制 | 大文件传输时内存溢出，浏览器崩溃 | 检查 bufferedAmount，使用 onbufferedamountlow 等待 |
| 移动端切后台时重置 RTC 连接 | 用户返回后需要重新走完整信令流程，体验差 | 信令断开重连时检测 connectionState，connected 则保持 |
| 使用 Plan-B SDP 语义（已废弃） | 新浏览器不兼容，多轨传输异常 | 统一使用 unified-plan |
| 忽略 connectionState 变化 | 断连无法感知，UI 状态与实际脱节 | 监听 onconnectionstatechange，驱动 UI 状态 |
| 分片大小超过 sctp.maxMessageSize | 发送失败或数据截断 | 动态获取 maxMessageSize，上限 256KB |
| 不做 TURN 服务器配置 | 对称 NAT 环境下 30-40% 用户无法 P2P | 部署 TURN 中继，使用 HMAC 凭证验证 |

### 我的犯错记录

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 未缓冲早期 ICE candidate | 连接建立时间从 2s 变为 15s | 始终实现 candidate 缓冲机制 |
| DataChannel 直接发送大文件 | 浏览器内存占用 2GB+ 后崩溃 | 实现分片 + 背压队列 |
| 忽略移动端后台行为 | 用户切回后通话中断 | 信令重连不重置已建立的 RTC |

**常见坑点类型：**

1. **ICE 时序问题** — candidate 和 SDP 的到达顺序不确定
2. **内存管理** — DataChannel 大文件传输的内存泄漏
3. **平台差异** — 移动端 WebView 与桌面端行为不一致
4. **NAT 穿透失败** — 未配置 TURN 导致部分网络无法连通
5. **状态同步** — 多端同时操作导致竞态条件

## 成功标准检查清单

- [ ] 信令协议定义了 new/offer/answer/candidate/bye/leave/keepalive
- [ ] 服务器实现了 Peer 注册、Session 跟踪、消息转发
- [ ] 客户端使用事件总线解耦信令与业务逻辑
- [ ] 实现了 ICE candidate 缓冲机制（remoteCandidates 列表）
- [ ] 使用 Trickle ICE（candidate 逐条发送）
- [ ] RTCPeerConnection 使用 unified-plan
- [ ] 媒体流支持 Camera/Screen 切换（replaceTrack）
- [ ] DataChannel 配置了 ordered 和 maxRetransmits
- [ ] 大文件传输实现了分片（≤256KB）+ 背压控制
- [ ] 移动端后台恢复时信令重连不重置 RTC
- [ ] 监听 onconnectionstatechange 驱动 UI 状态
- [ ] 配置了 STUN + TURN（含凭证生成机制）
- [ ] 实现了心跳保活（keepalive）
