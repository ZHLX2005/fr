# NetP2P 业务层（LAN 路径基于 v2 pub/sub；Relay 路径已迁移到 v3 snapshot）

基于 `LanTransport` 和 `RelayV3Transport` 的开箱即用 P2P 聊天。

## 使用方式

```dart
// 直接渲染 NetEngineBizHostPage — 自动处理 LAN/Relay 模式切换
NetEngineBizHostPage()
```

## 核心架构

```
net_p2p/
├── net_p2p.dart                    barrel
├── net_p2p_discovery_host.dart     入口页（LAN 扫描 + Relay 房间 v3）
├── net_p2p_message.dart            消息模型
├── pages/
│   ├── net_p2p_chat_page.dart      通用聊天 UI（LAN）
│   └── net_p2p_snapshot_chat.dart  snapshot 聊天页（v3 Relay）
└── README.md
```

- **LAN 模式**：UDP 多播发现 → HTTP 邀请/接受握手 → scope 广播聊天
- **Relay 模式**：v3 Lua state machine + snapshot 驱动
