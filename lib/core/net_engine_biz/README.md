# NetEngine 业务层（v2 标准化案例）

基于 `RelayTransport` pub/sub 的开箱即用聊天支持。

## 使用方式

```dart
// 房主（自定义人数）
await netEngineService.createRoom(
  relayUrl: '...',
  alias: '我',
  maxPlayers: 4,
);
netEngineService.subscribeRoom(code);
netEngineService.events.listen((e) { ... });

// 玩家加入
await netEngineService.joinRoom(
  relayUrl: '...',
  alias: '玩家',
  roomCode: code,
);
netEngineService.subscribeRoom(code);

// 发消息
await netEngineService.sendMessage(text: 'hello');

// 房间内置 UI
NetEngineBizHostPage()
```

## 核心架构

```
net_engine_biz/
├── net_engine_biz.dart           barrel
├── net_engine_discovery_host.dart  全功能 demo 页
├── net_engine_message.dart          消息模型
├── net_engine_service.dart          房间/消息服务
└── README.md
```

所有通信经 `room/<code>/events` topic，消息用 publish / subscribe，不再依赖 DataLog / scope。
