# LocalNet 协议架构文档

基于 LocalSend v2.1 官方源码研究

## 1. 概述

LocalSend 是一个局域网文件传输协议，支持设备发现和文件/消息传输。核心特性：

- **多协议支持**: v1.0 和 v2.1 双版本兼容
- **多发现机制**: UDP 多播 + HTTP 子网扫描
- **安全模型**: TLS 证书指纹作为设备唯一标识
- **后台隔离**: 使用 Isolate 执行网络操作

## 2. 网络拓扑

```
┌─────────────────────────────────────────────────────────────┐
│                      局域网 (LAN)                          │
│                                                          │
│   ┌──────────┐    UDP Multicast     ┌──────────┐         │
│   │ Device A │ ────224.0.0.167─────▶│ Device B │         │
│   │          │◀─────Reply──────────│          │         │
│   └──────────┘     (HTTP)          └──────────┘         │
│        │                                    │             │
│        │         HTTP Scan                 │             │
│        │◀──────────────────────────────────│             │
│        │         (192.168.x.0/24)          │             │
│        │                                    │             │
│        │══════════════╱╲═══════════════════│             │
│        │              ╱  ╲ File Transfer  │             │
│        │             ╱    ╲ (HTTP Upload) │             │
│        └───────────╱──────╲──────────────-┘             │
│                   ╲──────╱                              │
└─────────────────────────────────────────────────────────────┘
```

## 3. 设备发现 (Device Discovery)

### 3.1 UDP 多播发现

**地址**: `224.0.0.167:53317`

LocalSend 在每个网络接口绑定 UDP socket 并加入多播组：

```dart
// 绑定到 anyIPv4:0，系统分配端口
final socket = await RawDatagramSocket.bind(
  InternetAddress.anyIPv4,
  0,
  reuseAddress: true,
  reusePort: true,
);
socket.joinMulticast(InternetAddress('224.0.0.167'));
```

**广播 DTO** (MulticastDto):
```json
{
  "alias": "My Device",
  "version": "2.1",
  "deviceModel": "Pixel 7",
  "deviceType": "mobile",
  "fingerprint": "<sha256-hash>",
  "port": 53317,
  "protocol": "http",
  "download": true,
  "announce": true,
  "announcement": true
}
```

**Announcement vs Register**:
- `announce: true, announcement: true` - 主动广播，自己上线
- `announce: false, announcement: false` - 响应对方广播

### 3.2 HTTP 子网扫描 (Fallback)

当 UDP 多播被防火墙阻止时，LocalSend 使用 HTTP 扫描作为后备发现机制：

**扫描策略**:
- 每 10 秒扫描一次 `192.168.x.0/24` 子网
- 并发限制: 50 个并发请求
- 跳过本机 IP

**端点**: `GET /api/localsend/v2/info?fingerprint=<self-fingerprint>`

```dart
// HTTP 扫描实现
Future<Device?> _httpScan(String ip) async {
  final url = 'http://$ip:$port/api/localsend/v2/info?fingerprint=$deviceId';
  // 尝试 v2，然后 v1
}
```

### 3.3 Register 响应

当收到对方的 announcement 后，设备通过 HTTP POST 回应：

**端点**: `POST /api/localsend/v2/register`

```json
{
  "alias": "My Device",
  "version": "2.1",
  "deviceModel": "Pixel 7",
  "deviceType": "mobile",
  "fingerprint": "<sha256-hash>",
  "port": 53317,
  "protocol": "http",
  "download": true
}
```

## 4. 文件传输协议

### 4.1 传输流程

```
Sender                          Receiver
   │                                │
   │──── POST /prepare-upload ─────▶│  发送文件列表
   │◀─── 200: {sessionId, files} ───│  返回 sessionId 和文件 token
   │                                │
   │──── POST /upload ─────────────▶│  流式上传文件内容
   │   ?fileId=xxx&token=xxx        │  带文件 ID 和 token
   │◀─── 200 (接收完成) ────────────│
   │                                │
   │──── POST /cancel ─────────────▶│  可选：取消传输
   │                                │
```

### 4.2 Prepare Upload

**Sender 发送**:
```json
POST /api/localsend/v2/prepare-upload
{
  "info": {
    "alias": "Sender",
    "fingerprint": "xxx",
    ...
  },
  "files": {
    "<fileId>": {
      "id": "<fileId>",
      "fileName": "photo.jpg",
      "size": 1024000,
      "fileType": "image",
      "hash": "sha256",
      "preview": "base64..."
    }
  }
}
```

**Receiver 返回**:
```json
{
  "sessionId": "<uuid>",
  "files": {
    "<fileId>": "<token>"
  }
}
```

### 4.3 文件上传

**端点**: `POST /api/localsend/v2/upload`

**Query 参数**:
- `fileId`: 文件 ID
- `token`: Receiver 提供的 token
- `sessionId`: v2 必需

**Headers**:
- `Content-Length`: 文件大小
- `Content-Type`: MIME 类型

**Response**: 200 = 成功, 500 = 失败

## 5. 安全模型

### 5.1 证书指纹 (Fingerprint)

LocalSend 使用自签名 TLS 证书，证书的 SHA-256 哈希作为设备唯一标识：

```dart
class StoredSecurityContext {
  final String privateKey;
  final String publicKey;
  final String certificate;
  final String certificateHash;  // SHA-256(certificate)
}
```

**为什么用证书指纹？**
- 不需要集中式 ID 管理
- 每次安装生成新密钥对，保证隐私
- 可用于设备间 TLS 双向认证

### 5.2 协议版本协商

```
peerProtocolVersion = "1.0"  // 向后兼容
protocolVersion = "2.1"      // 当前版本
```

发现时根据对方 `version` 字段选择 v1 或 v2 API：

```dart
String target(Device target) {
  final route = target.version == '1.0' ? v1 : v2;
  return '$_basePath/$route';
}
```

## 6. 后台网络隔离 (Isolates)

### 6.1 为什么用 Isolate？

Flutter 中网络操作在主 isolate 会阻塞 UI。LocalSend 使用 Isolate 执行：
- UDP 多播监听
- HTTP 子网扫描
- 文件上传

### 6.2 Isolate 架构

```
┌─────────────────────────────────────────┐
│           Main Isolate (UI)            │
│                                         │
│  nearbyDevicesProvider                  │
│  └── StartMulticastListener (action)    │
│  └── StartLegacyScan (action)           │
│                                         │
└────────────────┬────────────────────────┘
                 │ SendToIsolateData
                 ▼
┌─────────────────────────────────────────┐
│      Multicast Isolate                  │
│                                         │
│  RawDatagramSocket.bind()               │
│  socket.listen((datagram) { ... })      │
│                                         │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│      HTTP Scan Isolate                  │
│                                         │
│  TaskRunner<Device?>                    │
│  concurrency: 50                         │
│  scan 192.168.x.0/24                     │
│                                         │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│      Upload Isolates (x2)               │
│                                         │
│  HttpClient.postStream()                │
│  with progress callback                 │
│                                         │
└─────────────────────────────────────────┘
```

### 6.3 消息传递

```dart
// 发送任务到 Isolate
connection.sendToIsolate(SendToIsolateData(
  syncState: null,
  data: HttpInterfaceScanTask(...),
));

// 从 Isolate 接收结果
await for (final device in stream) {
  dispatchAsync(RegisterDeviceAction(device));
}
```

## 7. API 端点

### 7.1 设备信息

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/localsend/v1/info` | 获取设备信息 |
| GET | `/api/localsend/v2/info` | 获取设备信息 (v2) |

**Query**: `?fingerprint=<self-id>` - 忽略自己

### 7.2 注册

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/localsend/v1/register` | 注册设备 |
| POST | `/api/localsend/v2/register` | 注册设备 (v2) |

### 7.3 文件传输

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/localsend/v1/prepare-upload` | 准备上传 |
| POST | `/api/localsend/v2/prepare-upload` | 准备上传 (v2) |
| POST | `/api/localsend/v1/upload` | 上传文件 |
| POST | `/api/localsend/v2/upload` | 上传文件 (v2) |
| POST | `/api/localsend/v1/cancel` | 取消传输 |
| POST | `/api/localsend/v2/cancel` | 取消传输 (v2) |

### 7.4 Web 发送

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/` | Web 发送页面 |
| GET | `/main.js` | Web 发送脚本 |
| POST | `/api/localsend/v2/prepare-download` | 准备下载 |

## 8. 数据模型

### 8.1 Device

```dart
class Device {
  String? signalingId;    // 信令服务器 ID
  String? ip;            // IP 地址
  String version;        // 协议版本
  int port;              // 端口
  bool https;            // 是否使用 HTTPS
  String fingerprint;    // 证书指纹
  String alias;          // 设备别名
  String? deviceModel;   // 设备型号
  DeviceType deviceType; // 设备类型
  bool download;         // 是否可下载
  Set<DiscoveryMethod> discoveryMethods;  // 发现方式
}
```

### 8.2 DTO 类型

| DTO | 用途 |
|-----|------|
| `MulticastDto` | UDP 多播广播 |
| `RegisterDto` | HTTP 注册请求 |
| `InfoDto` | 设备信息响应 |
| `PrepareUploadRequestDto` | 准备上传请求 |
| `PrepareUploadResponseDto` | 准备上传响应 |
| `FileDto` | 文件元数据 |
| `ReceiveRequestResponseDto` | Web 接收响应 |

## 9. 实现差异

### 我们的实现 vs LocalSend 官方

| 特性 | LocalSend 官方 | 我们的实现 |
|------|----------------|-----------|
| 发现 | UDP Multicast + HTTP Scan | UDP Multicast + HTTP Scan |
| 文件传输 | 流式上传 + PIN 码 | 仅消息传输 |
| 安全 | TLS 证书指纹 | SHA-256 随机 ID |
| 后台 | Isolate 隔离 | 单 isolate |
| HTTPS | 支持 | 仅 HTTP |
| WebRTC | 支持 (远程设备) | 不支持 |

## 10. 参考文件

### LocalSend 源码

```
.claude/skills/localsend/
├── common/lib/
│   ├── constants.dart              # 协议常量
│   ├── api_route_builder.dart     # API 路由
│   ├── model/
│   │   ├── device.dart            # Device 模型
│   │   └── dto/                   # 数据传输对象
│   └── src/
│       ├── isolate/               # Isolate 架构
│       └── task/
│           ├── discovery/         # 发现任务
│           └── upload/            # 上传任务
└── app/lib/
    └── provider/
        └── network/
            ├── nearby_devices_provider.dart  # 设备发现
            └── server/controller/
                ├── send_controller.dart      # 发送控制
                └── receive_controller.dart   # 接收控制
```

### 我们的实现

```
cmd/localnet/main.go           # Go 客户端实现
lib/core/localnet/
├── services/
│   ├── discovery_service.dart  # Flutter 发现服务
│   └── message_service.dart   # Flutter 消息服务
└── pages/
    ├── localnet_discover_page.dart
    └── localnet_chat_page.dart
```
