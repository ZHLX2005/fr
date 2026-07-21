# LocalNet 业务层（标准化案例）

业务层订阅 `Transport.events` 和 `Transport.watchScope` 即可，**零发现、零连接、零配置代码**。

## 接入方式

```dart
// 1. 渲染本地引擎 widget
LanDiscovery().buildPage(
  onPeerSelected: (peer) async {
    // 2. 拿到 transport，订阅事件总线
    final transport = await LanTransport.create();
    await transport.joinScope('chat-${peer.id}');
    localnetService.attach(transport, 'chat-${peer.id}');
  },
)
  ↓ transport.events / watchScope 流式驱动 UI
LocalnetChatPage(scope: scope)  // 订阅 messagesStream
```

## 业务层职责

- **不做**：发现、连接、认证、配置持久化
- **做**：解析 transport 事件 / scope 状态 → 更新本地模型 → 渲染

## 设置

`LocalnetSettingsPage` 是零配置壳 — 仅根据模式渲染对应 Discovery 的 `buildSettingsPage()`：

```dart
fw.LanDiscovery().buildSettingsPage()                    // alias + 多播
fw.RelayDiscovery(relayUrl: ...).buildSettingsPage()     // alias + relayUrl
```

每个 Discovery 内部用 SharedPreferences 私有 key 持久化，biz 不感知。
