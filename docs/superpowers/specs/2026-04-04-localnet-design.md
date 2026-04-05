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

## UDP 广播监听工作流程

### 启动流程

```
startUdpListener()
  └─> _startUdpListenerInternal()
        ├─> RawDatagramSocket.bind(anyIPv4, 53317, reuseAddress: true, reusePort: true)
        ├─> _udpSocket.joinMulticast(224.0.0.167)
        └─> _udpSocket.listen((event) {
              if (event == RawSocketEvent.read) {
                _handleUdpDatagram(datagram)
              }
            })
```

### 数据处理流程

```
_handleUdpDatagram(datagram)
  ├─> utf8.decode(datagram.data) → "deviceId,port"
  ├─> 解析 deviceId 和 port
  ├─> if (senderId == deviceId) 忽略自己
  ├─> _addDevice(senderId, alias, senderIp, senderPort)
  └─> _sendHttpJoin(senderIp, senderPort)
        └─> HTTP POST /join to senderIp:senderPort
```

### 消息格式

UDP 广播消息格式：`"deviceId,port"`（纯文本，逗号分隔）

### 关键配置

| 配置项 | 值 |
|--------|-----|
| 多播地址 | 224.0.0.167 |
| 多播端口 | 53317 |
| Socket 选项 | reuseAddress: true, reusePort: true |

### 状态标志

```dart
bool get isUdpListenerRunning => _udpSocket != null;
```

### 注意事项

- UDP 监听独立于 UDP 广播工作
- 关闭 UDP 监听后不再接收多播包
- 清理定时器仅在开启至少一个网络功能时运行

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
