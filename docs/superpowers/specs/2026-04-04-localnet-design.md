# LocalNet MVP Design

## 概述

简化版 LocalSend：局域网设备发现 + 文本消息传输

## 架构

### 组件
- **LocalnetService** - 单例，整合发现和消息服务
- **DiscoveryService** - UDP 多播广播/监听
- **MessageService** - HTTP 服务器 + 消息收发

### 协议
1. UDP 多播广播 (224.0.0.167:53317)，每3秒一次
2. 收到广播后回复 HTTP register
3. 消息通过 HTTP POST 发送

## 页面

### 发现页 (LocalnetDiscoverPage)
- 本机设备卡片
- 在线设备列表
- 点击设备跳转聊天页

### 聊天页 (LocalnetChatPage)
- AppBar: 设备别名 + 返回
- 消息气泡列表
- 输入框 + 发送按钮

## 文件结构
```
lib/core/localnet/
├── localnet_service.dart
├── pages/
│   ├── localnet_discover_page.dart
│   └── localnet_chat_page.dart
├── models/
│   ├── localnet_device.dart
│   └── localnet_message.dart
└── services/
    ├── discovery_service.dart
    └── message_service.dart
```

## 依赖
- network_info_plus (已有)
- 无需新增依赖
