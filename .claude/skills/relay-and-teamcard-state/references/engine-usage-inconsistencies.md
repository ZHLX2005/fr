# 引擎使用不一致性审计

> 记录 localnet_biz / surround_game / jungle_chess / 团建卡牌 demo / RelayRoomChatWidget
> 五个调用方对 `fw.Transport` 抽象的不同使用方式，作为后续统一迁移的待办清单。
>
> 创建于 2026-07-22。

## 1. 一致性矩阵

| 调用方                        | 路径                    | `createRoom`      | `joinRoom`   | `subscribe('room/<code>/events')` | `publish` | v1 旧 API                                |
| ----------------------------- | ----------------------- | ------------------- | -------------- | ----------------------------------- | ----------- | ---------------------------------------- |
| team_card/team_card_master    | lib/lab/demos           | ✅`fw.RoomConfig` | n/a            | ✅                                  | ✅          | ❌                                       |
| team_card/team_card_player    | lib/lab/demos           | n/a                 | ✅`code, ''` | ✅                                  | n/a         | ❌                                       |
| RelayRoomChatWidget           | lib/core/localnet/relay | ✅ host             | ✅ guest       | ✅                                  | ✅          | ❌                                       |
| surround_game/lan_lobby       | lib/core/surround_game  | ⚠️ 半新           | ⚠️ 半新      | ❌                                  | ❌          | ❌（adapter 自包）                       |
| jungle_chess/lan/lan_lobby    | lib/core/jungle_chess   | ❌                  | ❌             | ❌                                  | ❌          | ✅`joinScope('peers')`                 |
| localnet_biz/localnet_service | lib/core/localnet_biz   | ❌                  | ❌             | ❌                                  | ❌          | ✅`watchScope/broadcastScope/getScope` |

## 2. 5 个核心不一致点

### 2.1 jungle_chess 完全走 v1 旧 API

```dart
// lib/core/jungle_chess/lan/lan_lobby_page.dart:62-63
final transport = await fw.LanTransport.create();
await transport.joinScope('peers');
```

- **问题**：使用 v1 `LanTransport.joinScope('peers')`，未用 v2 `createRoom`/`joinRoom`+token
- **影响**：与 v2 pub/sub 模型不兼容，无法享受新引擎的事件广播能力
- **修复方向**：迁移到 v2 `RelayTransport` + `createRoom(fw.RoomConfig(maxPlayers: 2))`

### 2.2 surround_game 半新半旧（自包 adapter）

```dart
// lib/core/surround_game/lan/relay_lobby_page.dart:41
Future<void> _onPeerSelected(fw.DiscoveredPeer peer, fw.RelayTransport transport, {required bool isHost}) async {
  ...
  await adapter.createRoom(room);
  ...
}
```

- **问题**：用 v2 `RelayTransport` 拿 transport，但**自己包了**一层 `lan_service_adapter.dart` 维护 `getScope/broadcastScope/syncGameState`
- **影响**：与 v2 直接 `subscribe('room/.../events')` 模型重复，重复了引擎能力
- **修复方向**：删除自实现的 `lan_service_adapter.dart`，直接走 `t.subscribe('room/$code/events')` + `t.publish` 同步游戏状态

### 2.3 localnet_biz 完全 v1 旧 API

```dart
// lib/core/localnet_biz/localnet_service.dart
_chatSub = transport.watchScope(scope).listen(_onScopeUpdate);
_evtSub = transport.events.listen(_onTransportEvent);
...
t.broadcastScope(scope!);
...
log.merge({'messages': list}, localNodeId: t.myNodeId);
t.broadcastScope(scope);
```

- **问题**：还在用 v1 的 "看 scope 状态"模式（`getScope('messages')` + `broadcastScope`）
- **影响**：与 v2 pub/sub 模型不兼容，且 `localnet_service` 实质是 **过时的 chat demo**，不是生产级 transport 抽象
- **修复方向**：把 `localnet_biz` 重写为 v2 — 提供 `MessageNet.subscribe(transport, roomCode, topic)` 模式
- **优先级**：⚠️ 最高 — 是最严重的 v1 残留

### 2.4 team_card 完全 v2 正确

```dart
// lib/lab/demos/team_card/team_card_master.dart:116
final t = await fw.RelayTransport.create(relayUrl: kRelayUrl, alias: _alias);
final info = await t.createRoom(fw.RoomConfig(
  maxPlayers: _roomCapacity,
  schema: {'roles': [...]},
  canStartBeforeFull: true,
));
_sub = t.subscribe('room/${info.code}/events').listen((ev) { ... });
```

- **状态**：✅ 正确 — 完全走 v2 标准流程
- **可作为统一规范参考**

### 2.5 RelayRoomChatWidget 也完全 v2

```dart
// lib/core/localnet/relay/relay_room_chat.dart
final t = await fw.RelayTransport.create(relayUrl: widget.relayUrl, alias: widget.myAlias);
final info = await t.createRoom(fw.RoomConfig(maxPlayers: 2, ...));
_sub = t.subscribe('room/$info.code/events').listen((ev) { ... });
await t.publish('room/$code/events', {'type': 'chat', 'from': _myNodeId, ...});
```

- **状态**：✅ 正确 — 2 人房开箱即用，方案清晰

## 3. 统一方向

### 3.1 短期（1 小时内）

1. **surround_game 删除 `lan_service_adapter.dart`**：直接用引擎的 `createRoom/joinRoom` + `subscribe/publish`
2. **jungle_chess 迁移 v2**：跟 surround_game 一样用 `fw.RelayTransport`
3. **localnet_biz service 重写**：从 `MessageNet.attach(transport, scope)` 改为 `MessageNet.subscribe(transport, roomCode, topic)` 模式

### 3.2 中期

- 抽 `LocalnetRoomService`（v2 模式）出来，surround_game / jungle_chess 都调它
- 统一"建 2 人房 + 自动接 chat"的 high-level API

### 3.3 长期

- 引擎 v1 deprecated 完全删除
  - `Transport.joinScope / leaveScope / getScope / watchScope / broadcastScope / sendEvent` → 删除
  - `DataLog` class → 删除（v2 不再需要 scope 状态，最终一致由 pub/sub 替代）
- `Transport` 抽象瘦身到只保留 v2 方法

## 4. `LanTransport` 该不该保留？

- **保留**。它仍用于 LAN 模式（UDP 发现 + HTTP 直连），但只是引擎实现细节
- 业务层只看到 `Transport` 抽象，不知道底层是 LAN 还是 Relay
- 关键区分：`LanTransport` 是 `Transport` 的实现，不是 API 入口

## 5. 何时统一？

- 短期（1 小时内）：surround_game 删 adapter，jungle_chess 迁移 v2，localnet_biz 改写 service
- 中期：把 `LocalnetRoomService`（v2 模式）抽出来
- 长期：v1 deprecated 完全删除

## 6. 验证清单

- [ ] 5 个调用方都改用 v2 统一 API
- [ ] `Transport` 抽象只剩 v2 方法
- [ ] `DataLog` class 标记 deprecated
- [ ] flutter analyze lib/ 0 error
- [ ] 后端 `NotifyRoomEvent` 包装帧格式修复已部署

---

> 此文档是后续迁移的待办清单。每次统一后，更新「一致性矩阵」与「不一致点」两节。
