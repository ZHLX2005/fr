# LocalNet 业务层（v2 标准化案例）

基于 `RelayTransport` pub/sub 的开箱即用聊天支持。

## 使用方式

```dart
// 房主（自定义人数）
await localnetService.createRoom(
  relayUrl: '...',
  alias: '我',
  maxPlayers: 4,
);
localnetService.subscribeRoom(code);
localnetService.events.listen((e) { ... });

// 玩家加入
await localnetService.joinRoom(
  relayUrl: '...',
  alias: '玩家',
  roomCode: code,
);
localnetService.subscribeRoom(code);

// 发消息
await localnetService.sendMessage(text: 'hello');

// 房间内置 UI
LocalnetBizHostPage()
```

## 核心架构

```
localnet_biz/
├── localnet_biz.dart           barrel
├── localnet_discovery_host.dart  全功能 demo 页
├── localnet_message.dart          消息模型
├── localnet_service.dart          房间/消息服务
└── README.md
```

所有通信经 `room/<code>/events` topic，消息用 publish / subscribe，不再依赖 DataLog / scope。
