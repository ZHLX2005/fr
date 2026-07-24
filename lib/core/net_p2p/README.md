# NetP2P 业务层（v2 标准化案例）

基于 `RelayTransport` / `LanTransport` pub/sub 的开箱即用 P2P 聊天。

## 使用方式

```dart
// 直接渲染 NetEngineBizHostPage — 自动处理 LAN/Relay 模式切换
NetEngineBizHostPage()
```

## 核心架构

```
net_p2p/
├── net_p2p.dart                    barrel
├── net_p2p_discovery_host.dart     入口页（LAN 扫描 + Relay 房间）
├── net_p2p_message.dart            消息模型
├── net_p2p_service.dart            房间/消息服务（Relay 专用）
├── pages/
│   └── net_p2p_chat_page.dart      通用聊天 UI
└── README.md
```

- **LAN 模式**：UDP 多播发现 → HTTP 邀请/接受握手 → scope 广播聊天
- **Relay 模式**：HTTP 建房/加入 → WS 订阅 → publish 聊天
