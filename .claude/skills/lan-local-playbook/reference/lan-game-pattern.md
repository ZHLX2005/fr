# LAN 模式完整参考

围追堵截项目中局域网多人模式的完整架构模式。提取自 `lib/core/surround_game/lan/`。

## 分层设计

```
Page (UI) → ViewModel (StateMachine) → ServiceAdapter (LAN Bridge) → LanFramework
```

每层职责清晰隔离：

| 层 | 职责 | 不做什么 |
|----|------|---------|
| Page | UI 编排、导航、dispose 生命周期 | 不持有 GameState |
| ViewModel | 状态机迁移、引擎操作 | 不直接调 LanFramework |
| ServiceAdapter | 桥接 LanFramework、处理多播/Channel | 不做业务状态 |
| LanFramework | UDP + HTTP + Session 基础设施 | 不做业务逻辑 |

## 协议消息（lan_messages.dart）

```dart
sealed class LanRoomEvent {
  String get type;
  Map<String, dynamic> toJson();

  static LanRoomEvent fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'HostRoomAnnounced' => HostRoomAnnounced(
        room: GameRoom.fromJson(json['room'] as Map),
        hostDeviceId: json['hostDeviceId'] as String,
        hostAlias: json['hostAlias'] as String,
      ),
      'HostRoomClosed' => HostRoomClosed(
        roomId: json['roomId'] as String,
      ),
      'ClientJoinRequested' => ClientJoinRequested(
        clientDeviceId: json['clientDeviceId'] as String,
        clientAlias: json['clientAlias'] as String,
        roomId: json['roomId'] as String,
      ),
      'ClientJoinResult' => ClientJoinResult(
        roomId: json['roomId'] as String,
        clientDeviceId: json['clientDeviceId'] as String,
        accepted: json['accepted'] as bool,
        reason: json['reason'] as String?,
      ),
      _ => throw FormatException('Unknown type: ${json['type']}'),
    };
  }
}
```

## ServiceAdapter（lan_service_adapter.dart）

业务层唯一接触 localnet 的边界。

```dart
abstract class LanServiceAdapter {
  static final LanServiceAdapter instance = _LanServiceAdapterImpl();

  // 生命周期
  Future<void> start({String? myAlias});
  Future<void> stop();
  bool get isRunning;

  // 设备
  Stream<List<Device>> watchDevices();

  // 房间
  Stream<LanRoomEvent> watchRoomEvents();
  Future<void> announceRoom(GameRoom room);
  Future<void> stopRoom(String roomId);

  // 加入
  Future<SendResult> sendJoinRequest({
    required String hostDeviceId, required String clientAlias,
  });
  Future<SendResult> sendJoinAccept({
    required String clientDeviceId, required GameRoom room,
  });

  // Session
  Session<ValueNotifier<GameState>> createGameSession({
    required String peerDeviceId,
    required ValueNotifier<GameState> state,
    String? channelName,
  });

  // 别名
  void updateAlias(String newAlias);
  String get myAlias;
  String get myDeviceId;
}
```

实现关键点：
- `start()` 内启动 LanFramework + 订阅 `roomAnnounce` / `roomJoin` channel
- `announceRoom()` 每 5s 定时器通过 UDP 多播广播房间公告
- `stopRoom()` 广播 `HostRoomClosed` + 取消定时器
- `sendJoinRequest()` 通过 UDP 多播 + `toDeviceId` 过滤（`_fw.sendMulticast`）

## 多播通信实现

```dart
// Adapter 监听两个 channel：
_announceSub = _fw.watchChannel(LanChannels.roomAnnounce).listen(_onRoomAnnounce);
_joinSub = _fw.watchChannel(LanChannels.roomJoin).listen(_onRoomJoin);

// 同时监听多播原始消息：
_multicastSub = _fw.watchMulticast().listen((msg) {
  final key = msg['key'] as String?;
  final payload = msg['payload'] as Map<String, dynamic>?;
  if (payload == null) return;

  if (key == 'room_announce') { /* 房间公告 */ }
  else if (key == 'room_join') {
    // 只关心发给自己的
    if (payload['toDeviceId'] != myDeviceId) return;
    /* 处理加入请求/回应 */
  }
});
```

## 协议事件 → 状态机桥接

View Model 接收两类事件：
1. **用户操作事件**（`LanHostEvent` / `LanClientEvent`）— 通过 `dispatch()` 传入
2. **协议事件**（`LanRoomEvent`）— 通过监听 `watchRoomEvents()` 传入

```dart
// Host ViewModel 内部
void _onRoomEvent(LanRoomEvent event) {
  final next = reduceHostProtocol(value, event);  // 协议 bridge
  if (!identical(next, value)) value = next;
}

void dispatch(LanHostEvent event) {
  final next = reduce(value, event);              // UI 操作 reducer
  if (!identical(next, value)) value = next;
}
```

## Session 同步（game_state_serializer.dart）

```dart
class GameStateSerializer implements StateSerializer<ValueNotifier<GameState>> {
  const GameStateSerializer();

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
```

关键：反序列化使用 `replayHistory` 重建所有派生状态（adjacency / wallGrid / validMoves），不直接传输计算密集型中间数据。

## 设备掉线检测

```dart
// Host 端
void _onDevices(List<Device> devices) {
  final peerId = _peerDeviceId;
  if (peerId == null) return;
  if (!devices.any((d) => d.deviceId == peerId)) {
    _onRoomEvent(HostClientLeft());  // → HostError
  }
}

// Client 端同理发送 ClientDisconnectedProtocol
```

## 关键文件依赖关系

```
lan_lobby_page.dart
  ├── lan_host_view_model.dart
  │     ├── lan_host_protocol_bridge.dart  (协议 → 状态迁移)
  │     └── lan_match_state.dart           (Host 侧状态)
  ├── service/lan_service_adapter.dart     (LAN 桥接器)
  │     └── protocol/lan_messages.dart     (协议消息)
  └── lan_room_page.dart
        ├── lan_host_view_model.dart / lan_client_view_model.dart
        ├── lan_match_state.dart / lan_match_event.dart
        └── lan_client_protocol_bridge.dart
```
