# LanFramework 局域网通信框架重构设计

- **日期**：2026-06-15
- **范围**：`lib/core/localnet/` 的**框架结构封装**，使其成为业务无关、可复用的局域网通信框架
- **状态**：已通过 brainstorming 对齐，待用户审阅后进入 writing-plans

---

## 0. 范围与边界（必须先读）

### 0.1 本设计做什么

把 `lib/core/localnet/` 重构为一个**统一的、事件驱动的、可复用的局域网通信框架**（LanFramework），业务侧（chat、游戏、未来其他模块）只需通过统一 API 调用，不感知网络协议细节。

### 0.2 本设计不做什么（明确越界清单）

- ❌ 业务层（chat、围追堵截游戏）真实业务逻辑实现 —— 各自下一轮
- ❌ UI 层（页面、widget）改造 —— 不在本轮
- ❌ 新的传输层（WebSocket、mDNS）—— YAGNI，本轮只 UDP + HTTP
- ❌ 跨会话的状态广播（"业务会话层"）—— 下一轮
- ❌ 持久化存储（业务数据存库）—— 不在本轮
- ❌ 鉴权、加密 —— LAN 场景不引入

### 0.3 接入策略：**双轨制 + 平滑迁移**

- 新框架 `LanFramework` 与现有 `LocalnetService` **并行存在**
- 框架作为**新接入点**，旧代码完全不动（保留在 `_legacy/`）
- 业务侧按需迁移：先迁 chat，再迁游戏
- 不破坏现有功能，每个 commit 都独立可运行

---

## 1. 已对齐的决策

| 决策点 | 选择 |
|---|---|
| 框架封装粒度 | 重组现有代码 + 引入事件总线 + 提供统一 API |
| 业务调用方式 | `LanFramework.instance` 单例 + 统一 API（sendTo/watchChannel/watchDevices） |
| 主从概念 | **无主从**（框架层不引入；P2P 对等架构） |
| 会话概念 | **框架层不维护会话**（业务侧自行组合 channel） |
| 寻址粒度 | **按设备 ID 寻址**（IP:port 框架管） |
| 通道路由 | **业务自定 channel 字符串**（"chat.msg" / "game.move"） |
| 断线处理 | 框架层内置连接质量监控 + 重连调度，业务侧订阅状态 |
| 状态广播 | 框架只管通道收发，**状态广播由业务侧会话对象负责** |
| 与现有代码兼容 | 双轨制（旧 LocalnetService 保留；新 LanFramework 并行） |

---

## 2. 架构分层

```
┌──────────────────────────────────────────────────────────────────────┐
│                    框架入口层（Public API）                            │
│                                                                      │
│    LanFramework.instance                                            │
│    ├─ start(config) / stop()                                        │
│    ├─ watchDevices() / devices                                      │
│    ├─ sendTo(deviceId, channel, payload)                            │
│    ├─ watchChannel(channel)                                         │
│    └─ watchConnectionState(deviceId)                                │
│                                                                      │
│    业务侧只看到这个类，不关心内部结构                                    │
└────────────────┬─────────────────────────────────────────────────────┘
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────────┐
│                       核心编排层（Orchestrator）                      │
│                                                                      │
│    FrameworkCore                                                    │
│    ├─ 启动/停止各子模块                                                │
│    ├─ 维护全局状态机                                                   │
│    ├─ 协调事件流转                                                     │
│    └─ 持有子模块引用                                                   │
└─────┬────────────────┬──────────────────┬─────────────────┬─────────┘
      │                │                  │                 │
      ▼                ▼                  ▼                 ▼
┌──────────┐    ┌────────────┐    ┌─────────────┐    ┌──────────────┐
│事件总线层 │    │ 设备管理层  │    │ 通道管理层   │    │ 连接管理层    │
│EventBus  │    │DeviceMgr   │    │ChannelMgr   │    │ConnMgr       │
│          │    │            │    │             │    │              │
│•emit()   │    │•devices    │    │•sendTo()    │    │•watchState() │
│•on<T>()  │    │•watch()    │    │•watchCh()   │    │•重连调度     │
│•状态查询  │    │•心跳跟踪   │    │•通道路由     │    │•质量监控     │
│          │    │•离线判定   │    │•消息分发     │    │              │
└────┬─────┘    └─────┬──────┘    └──────┬──────┘    └──────┬───────┘
     │                │                  │                  │
     │           UDP  │ 心跳/发现       │ HTTP POST        │ 状态事件
     │                │                  │                  │
     ▼                ▼                  ▼                  ▼
┌──────────────────────────────────────────────────────────────────────┐
│                       传输层（Transport）                             │
│  ┌──────────────────────────┐    ┌──────────────────────────┐       │
│  │   UdpTransport           │    │   HttpTransport          │       │
│  │  • 原始 UDP 多播          │    │  • 原始 HTTP 服务         │       │
│  │  • 原始数据报收发          │    │  • HTTP 客户端发送        │       │
│  │  • 不解析业务             │    │  • 不解析业务             │       │
│  │  • 错误转发给上层          │    │  • 错误转发给上层          │       │
│  └──────────────────────────┘    └──────────────────────────┘       │
└──────────────────────────┬────────────────────┬──────────────────────┘
                           │                    │
                           ▼                    ▼
                  ┌──────────────┐     ┌──────────────┐
                  │ UDP Socket   │     │ HTTP Server  │
                  │ Multicast    │     │ HTTP Client  │
                  └──────────────┘     └──────────────┘
```

### 2.1 各层职责边界

| 层 | 职责 | 不该做什么 |
|---|---|---|
| **入口层（Public API）** | 对业务侧暴露的接口 | 不实现细节 |
| **编排层（Core）** | 启动/停止/协调/状态机 | 不实现各模块具体逻辑 |
| **事件总线层** | 统一事件发射/订阅 | 不感知业务事件含义 |
| **设备管理层** | 设备列表维护、心跳、离线判定 | 不发送业务数据 |
| **通道管理层** | 业务消息路由、HTTP 通道分发 | 不维护业务状态 |
| **连接管理层** | 连接质量监控、重连调度 | 不发送业务数据 |
| **传输层** | 字节收发 | 不解析协议 |

### 2.2 隔离规则

- 业务侧只能 `import LanFramework`，不能直接 import 任何内部模块
- 传输层不感知业务事件类型
- 事件总线不感知业务事件类型（仅作为通用分发管道）
- 通道名是字符串，由业务侧自行约定，框架不预定义

---

## 3. 目标目录树

```
lib/core/localnet/
│
├── localnet.dart                    # 公共导出入口（只 export framework + pages）
│
├── framework/                       # 【新】框架核心层
│   ├── lan_framework.dart           # 框架门面 (单例)
│   ├── framework_core.dart          # 核心编排器（启动/停止/协调）
│   ├── framework_config.dart        # 框架配置（替代原 LocalnetConfig）
│   ├── framework_status.dart        # 框架状态枚举
│   └── exception/                   # 框架异常
│       └── framework_exception.dart
│
├── event_bus/                       # 【新】事件总线层
│   ├── lan_event.dart               # 事件类型定义 (sealed class)
│   ├── device_event.dart            # 设备相关事件
│   ├── channel_event.dart           # 通道相关事件
│   ├── connection_event.dart        # 连接状态事件
│   ├── service_event.dart           # 服务生命周期事件
│   └── event_bus.dart               # 事件总线实现（单例）
│
├── device/                          # 【新】设备管理层
│   ├── device.dart                  # 设备数据模型
│   ├── device_manager.dart          # 设备管理器
│   └── device_registry.dart         # 设备表（deviceId → ip:port 映射）
│
├── channel/                         # 【新】通道管理层
│   ├── channel_manager.dart         # 通道管理器
│   ├── channel_message.dart         # 通道消息数据模型
│   └── send_result.dart             # 发送结果
│
├── connection/                      # 【新】连接管理层
│   ├── connection_manager.dart      # 连接状态管理
│   ├── connection_quality.dart      # 连接质量评级
│   └── reconnect_strategy.dart      # 重连策略（指数退避）
│
├── transport/                       # 【新】传输层
│   ├── transport.dart               # Transport 抽象基类
│   ├── udp_transport.dart           # UDP 多播传输
│   ├── http_transport.dart          # HTTP 服务/客户端传输
│   └── transport_config.dart        # 传输配置（端口、地址等）
│
├── pages/                           # 【保留】UI 层（demo/debug，本轮不动）
│   ├── localnet_discover_page.dart
│   ├── localnet_chat_page.dart
│   ├── localnet_debug_page.dart
│   └── localnet_settings_page.dart
│
└── _legacy/                         # 【保留·标记 deprecated】旧代码
    ├── README.md                    # 迁移指南
    ├── localnet_service.dart        # 旧单例
    ├── discovery_service.dart       # 旧发现服务
    ├── message_service.dart         # 旧消息服务
    ├── config_service.dart          # 旧配置服务
    └── models/                      # 旧数据模型
        ├── localnet_config.dart
        ├── localnet_constants.dart
        ├── localnet_device.dart
        └── localnet_message.dart
```

### 3.1 现有文件去向

| 现存文件 | 处理 | 去向 / 说明 |
|---|---|---|
| `localnet.dart` | **改** | 改为只 `export 'framework/lan_framework.dart'`，保留 pages 导出 |
| `localnet_service.dart` | **移动** | → `_legacy/localnet_service.dart`，加 `@Deprecated` 注释 |
| `services/discovery_service.dart` | **移动** | → `_legacy/discovery_service.dart`，加 `@Deprecated` |
| `services/message_service.dart` | **移动** | → `_legacy/message_service.dart`，加 `@Deprecated` |
| `services/config_service.dart` | **移动** | → `_legacy/config_service.dart`，加 `@Deprecated` |
| `services/localnet_message_service.dart` | **删除** | 重复实现（与 message_service 功能重叠） |
| `services/debug_log_service.dart` | **保留** | 仅 framework 内部使用（仍由 `lan_framework.dart` import） |
| `models/localnet_config.dart` | **移动** | → `_legacy/models/localnet_config.dart` |
| `models/localnet_constants.dart` | **拆分** | 网络常量 → `transport/transport_config.dart`；协议常量 → `framework/framework_config.dart` |
| `models/localnet_device.dart` | **移动** | → `device/device.dart`（字段结构调整） |
| `models/localnet_message.dart` | **删除** | 业务消息概念废弃；框架不维护业务消息，由 channel 传输 Map 替代 |
| `pages/*` | **保留** | UI 不在本轮 |

---

## 4. 框架统一 API（核心契约）

```dart
/// 局域网通信框架（单例）
class LanFramework {
  static final LanFramework instance = LanFramework._();
  
  // ============ 生命周期 ============
  Future<void> start(FrameworkConfig config);
  Future<void> stop();
  FrameworkStatus get status;
  Stream<FrameworkStatus> watchStatus();
  
  // ============ 设备发现 ============
  /// 当前所有发现的设备
  List<Device> get devices;
  
  /// 设备列表变化事件（整个列表）
  Stream<List<Device>> watchDevices();
  
  /// 单个设备事件（加入/离开/更新）
  Stream<DeviceEvent> watchDeviceEvents();
  
  // ============ 业务通道 ============
  /// 向指定设备发送业务消息
  /// [channel] 是业务自定的字符串（如 "chat.msg"、"game.move"）
  /// [payload] 是任意 JSON 可序列化的 Map
  Future<SendResult> sendTo(
    String targetDeviceId,
    String channel,
    Map<String, dynamic> payload,
  );
  
  /// 订阅某个 channel 的所有消息（多设备发来的都收）
  Stream<ChannelMessage> watchChannel(String channel);
  
  // ============ 连接状态 ============
  /// 判断某设备当前是否在线
  bool isOnline(String deviceId);
  
  /// 订阅某设备的连接状态变化
  Stream<ConnectionStateEvent> watchConnectionState(String deviceId);
  
  // ============ 配置热更新 ============
  Future<void> updateConfig(FrameworkConfig newConfig);
}
```

### 4.1 设计原则

- **不出现"会话"概念** —— 框架只管"通道"
- 业务侧自行决定"哪些通道的哪些事件构成一次会话"
- 设备 ID 是寻址单位（不是 IP:port，IP:port 由框架内部映射）
- channel 是逻辑概念，框架内部用 HTTP POST 实现

---

## 5. 数据模型

```dart
/// 设备信息
class Device {
  final String deviceId;     // 设备唯一 ID（框架层分配）
  final String alias;        // 设备名（用户可配置）
  final String ip;           // IP 地址（框架内部维护，不暴露给业务）
  final int port;            // HTTP 端口（框架内部维护）
  final DateTime lastSeen;   // 最后心跳时间（框架内部维护）
  final Map<String, String> extras;  // 扩展字段（如游戏房间信息）
  
  bool get isOnline;         // 心跳是否超时（基于 deviceTimeoutSeconds）
}

/// 通道消息
class ChannelMessage {
  final String sourceDeviceId;   // 谁发的
  final String channel;          // 哪个 channel
  final Map<String, dynamic> payload;  // 业务数据
  final DateTime timestamp;
}

/// 发送结果
class SendResult {
  final bool success;
  final int? statusCode;         // HTTP 状态码
  final String? error;           // 错误信息
  final Duration latency;        // 发送耗时
}

/// 框架配置
class FrameworkConfig {
  final String deviceAlias;              // 设备名
  final int port;                        // HTTP 端口
  final bool httpServerEnabled;          // 是否启用 HTTP 服务
  final bool udpListenerEnabled;         // 是否启用 UDP 监听
  final bool udpBroadcastEnabled;        // 是否启用 UDP 广播
  final Duration broadcastInterval;      // 广播间隔
  final Duration deviceTimeout;          // 设备离线判定时间
  final Duration cleanupInterval;        // 清理定时器间隔
  final String? relayHost;               // 模拟器中继主机
  final int relayPort;                   // 模拟器中继端口
}

/// 框架状态枚举
enum FrameworkStatus {
  init,        // 未初始化
  starting,    // 启动中
  running,     // 运行中
  stopping,    // 停止中
  error,       // 错误状态
}
```

---

## 6. 事件总线契约

```dart
/// 框架事件基类（sealed class）
sealed class LanEvent {
  const LanEvent();
  DateTime get timestamp;
}

/// 设备事件
sealed class DeviceEvent extends LanEvent {
  const DeviceEvent();
  String get deviceId;
}
class DeviceFoundEvent extends DeviceEvent { ... }      // 新设备加入
class DeviceLostEvent extends DeviceEvent { ... }       // 设备超时离线
class DeviceUpdatedEvent extends DeviceEvent { ... }    // 设备信息更新（extras 变化）

/// 通道事件
class ChannelMessageEvent extends LanEvent {
  final ChannelMessage message;
  const ChannelMessageEvent(this.message);
}

/// 连接状态事件
sealed class ConnectionStateEvent extends LanEvent {
  const ConnectionStateEvent();
  String get deviceId;
}
class DeviceOnlineEvent extends ConnectionStateEvent { ... }
class DeviceOfflineEvent extends ConnectionStateEvent { ... }
class DeviceReconnectingEvent extends ConnectionStateEvent { ... }
class DeviceReconnectFailedEvent extends ConnectionStateEvent { ... }

/// 服务生命周期事件
class ServiceStartedEvent extends LanEvent { ... }
class ServiceStoppedEvent extends LanEvent { ... }
class ServiceErrorEvent extends LanEvent { ... }
class ConfigChangedEvent extends LanEvent { ... }

/// EventBus 接口
class EventBus {
  /// 发射事件
  void emit(LanEvent event);
  
  /// 订阅所有事件
  Stream<LanEvent> watchAll();
  
  /// 按类型订阅（语法糖）
  Stream<T> watch<T extends LanEvent>();
  
  /// 销毁
  void dispose();
}
```

### 6.1 事件流示例

```dart
// 业务侧订阅设备变化
framework.watchDeviceEvents().listen((event) {
  switch (event) {
    case DeviceFoundEvent e:
      print('Found: ${e.device.alias}');
    case DeviceLostEvent e:
      print('Lost: ${e.deviceId}');
    case DeviceUpdatedEvent e:
      print('Updated: ${e.device.alias}');
  }
});

// 框架内部发射
eventBus.emit(DeviceFoundEvent(device));
```

---

## 7. 框架内部模块依赖

```
┌──────────────────────────────────────────────────────────────────────┐
│                         LanFramework                                │
│                          (门面/单例)                                 │
└─────────────────────┬────────────────────────────────────────────────┘
                      │ 持有
                      ▼
        ┌──────────────────────────┐
        │     FrameworkCore        │
        │     (编排协调)            │
        └─┬────────┬──────────┬────┘
          │        │          │
          ▼        ▼          ▼
    ┌────────┐ ┌────────┐ ┌────────┐
    │Device  │ │Channel │ │Conn    │  ← 业务逻辑层
    │Manager │ │Manager │ │Manager │
    └────┬───┘ └────┬───┘ └────┬───┘
         │          │          │
         │  全部订阅 ▼          │
         │   ┌──────────┐      │
         │   │ EventBus │ ←── 事件总线 (解耦)
         │   └────┬─────┘      │
         │        │            │
         └────────┼────────────┘
                  │
                  ▼
          ┌──────────────────┐
          │   Transport      │  ← 基础设施层
          │  (UDP + HTTP)    │
          └──────────────────┘
                  │
                  ▼
              [系统 Socket]
```

---

## 8. 核心数据流

### 8.1 设备发现流程

```
═══════════════════════════════════════════════════════════════════════════
  设备 A 启动 → 被设备 B 发现 → B 加入 A 的设备列表
═══════════════════════════════════════════════════════════════════════════

[Device A]                                          [Device B]
    │                                                   │
    │  ① UdpTransport 每3秒广播心跳                      │
    │     "deviceA-id,53317"                            │
    │ ─────── UDP Multicast 239.255.255.255:5678 ──────►│
    │                                                   │
    │                                          ② UdpTransport 收到
    │                                          DeviceManager._onDatagram()
    │                                                   │
    │                                          ③ 验证 deviceId
    │                                          ④ ChannelManager.sendHttpJoin()
    │                                                   │
    │                                                   │ HTTP POST /join
    │ ◄───────────────  http://A:53317/join ────────────│
    │                                                   │
    │ ⑤ HttpTransport 收到 /join                         │
    │    ChannelManager._onJoin()                       │
    │    DeviceManager._addDevice(B)                    │
    │                                                   │
    │ ⑥ EventBus.emit(DeviceFoundEvent(B))              │
    │    ↓                                              │
    │    watchDevices() 触发回调                         │
    │    UI 收到 B 的设备信息                             │
    │                                                   │
    │                                          ⑦ 同样在 B 端
    │                                          DeviceManager._addDevice(A)
    │                                          EventBus.emit(DeviceFoundEvent(A))
    │                                                   │
    │                                                   │ UI 收到 A
```

### 8.2 业务数据通道流程

```
═══════════════════════════════════════════════════════════════════════════
  业务模块通过 Channel 发送和接收数据
═══════════════════════════════════════════════════════════════════════════

                        业务侧代码
                            │
            ┌───────────────┼───────────────┐
            ▼               ▼               ▼
   sendTo(B, "chat.msg", {..})    watchChannel("chat.msg")
            │                              │
            ▼                              │
   ┌──────────────────────┐                │
   │ ChannelManager       │                │
   │ ├─ 查 B 的 IP+Port    │                │
   │ ├─ HttpTransport.post │                │
   │ └─ return result     │                │
   └──────────┬───────────┘                │
              │                            │
              │  HTTP POST                 │
              ▼                            │
       [网络传输]                           │
              │                            │
              ▼                            │
   ┌──────────────────────┐                │
   │ HttpTransport 收到    │                │
   │ ├─ 解析 channel 字段  │                │
   │ └─ ChannelManager     │                │
   │    ._onIncoming()     │                │
   └──────────┬───────────┘                │
              │                            │
              │  EventBus.emit(           │
              │    ChannelMessageEvent    │ ──────────►  业务 watchChannel
              │  )                        │              回调触发
              │                            │              收到 {from: A, payload: ...}

═══════════════════════════════════════════════════════════════════════════
  关键：channel 字段由业务侧自己定义（"chat.msg" / "game.move" / "file.transfer"）
  框架不预定义，纯字符串通道路由
═══════════════════════════════════════════════════════════════════════════
```

### 8.3 断线检测流程

```
═══════════════════════════════════════════════════════════════════════════
  心跳超时 → 设备离线
═══════════════════════════════════════════════════════════════════════════

[Device A]                                          [Device B]
    │                                                   │
    │  离线 (断电/退出 app)                               │
    │                                                   │
    │                                                   │ 15秒内未收到 A 的心跳
    │                                                   │ DeviceManager._cleanupTimer()
    │                                                   │ 标记 A 离线
    │                                                   │
    │                                                   │ EventBus.emit(DeviceLostEvent(A))
    │                                                   │ ConnectionManager
    │                                                   │   ._onDeviceLost(A)
    │                                                   │     → emit(DeviceOfflineEvent(A))
    │                                                   │ ↓
    │                                                   │ watchConnectionState(A)
    │                                                   │ 触发回调
    │                                                   │ UI 移除 A + 显示离线
```

---

## 9. HTTP 协议设计

### 9.1 现有协议保留

为兼容旧 `_legacy` 代码，框架的 HTTP 服务同时支持新旧两套路径：

| 路径 | 方法 | 用途 | 兼容性 |
|---|---|---|---|
| `/join` | POST | 设备加入（旧协议） | 兼容旧 DiscoveryService |
| `/info` | GET | 设备信息 | 兼容旧 |
| `/message` | POST | 旧消息 | 兼容旧 |
| `/channel/<channel>` | POST | **新协议** - 通道消息 | 仅新框架 |

> **心跳机制**：设备发现心跳仍走 UDP 多播（与现状一致），不新增 HTTP 心跳路径。这样能保持与旧 DiscoveryService 的协议兼容，且 UDP 多播天然适合一对多发现。

### 9.2 新协议消息格式

**通道消息 HTTP Body（JSON）**：

```json
{
  "channel": "chat.msg",
  "payload": {
    "text": "Hello",
    "from": "alice"
  },
  "senderId": "device-uuid-a",
  "timestamp": "2026-06-15T10:30:00Z"
}
```

### 9.3 协议演进策略

- **新协议 `/channel/*` 不影响旧代码**：旧 DiscoveryService 仍按 `/join` 接收，不会被 `/channel/*` 路径干扰
- 旧代码继续工作，新代码用新通道
- 旧代码迁移完成后，下一轮删除旧协议支持

---

## 10. 错误处理

| 错误类型 | 触发场景 | 框架层处理 | 业务侧通知方式 |
|---|---|---|---|
| UDP 端口占用 | 多播地址冲突 | `start()` 返回异常 | `ServiceErrorEvent` |
| HTTP 端口占用 | 重复 bind | `start()` 返回异常 | `ServiceErrorEvent` |
| 设备心跳超时 | 设备下线 | `_cleanupTimer` 标记离线 | `DeviceLostEvent` + `DeviceOfflineEvent` |
| HTTP POST 失败 | 网络不通 | ChannelManager 重试 3 次 | `SendResult(success: false)` + `DeviceOfflineEvent` |
| 协议解析失败 | 收到错误格式数据 | 丢弃 + Debug 日志 | 不通知业务 |
| 配置更新失败 | 保存失败 | 抛出异常 | `updateConfig()` Future 失败 |

---

## 11. 测试策略

### 11.1 单元测试（核心，必做）

- **EventBus**：`emit` 后 `watch<T>()` 收到；`dispose` 后不再发射
- **DeviceManager**：添加/移除/更新设备；离线判定时间正确
- **ChannelManager**：`sendTo` 走通完整路径；`watchChannel` 收到事件
- **Transport**：UDP 收发；HTTP server bind + response；HTTP client POST
- **LanFramework**：`start/stop` 状态机正确；幂等性（重复 start 不报错）

### 11.2 集成测试（建议做）

- **两端通信**：模拟两个 LanFramework 实例（不同 deviceId），验证设备发现 + 通道收发
- **断线重连**：模拟设备离线，验证 `watchConnectionState` 触发 `DeviceOfflineEvent`
- **新协议兼容**：验证旧 `/join` 请求仍然被框架响应

### 11.3 不测的内容

- ❌ 真实网络设备发现（需要两台真机）
- ❌ 模拟器中继（依赖 Android 模拟器）
- ❌ UI 层渲染

### 11.4 测试目录结构

```
test/core/localnet/
├── framework/
│   ├── lan_framework_test.dart
│   └── framework_core_test.dart
├── event_bus/
│   └── event_bus_test.dart
├── device/
│   └── device_manager_test.dart
├── channel/
│   └── channel_manager_test.dart
├── connection/
│   └── connection_manager_test.dart
└── transport/
    ├── udp_transport_test.dart
    └── http_transport_test.dart
```

---

## 12. 迁移与回滚策略

### 12.1 迁移顺序（双轨制）

| 步骤 | 内容 | 风险 | 回滚 |
|---|---|---|---|
| 1 | 创建 `framework/` 目录骨架 + LanFramework 单例（空实现） | 0 | 删除目录 |
| 2 | 创建 `event_bus/` + LanEvent 类型 | 0 | 删除目录 |
| 3 | 创建 `transport/` 抽出 UDP/HTTP 传输 | 中 | 旧 DiscoveryService 仍可用 |
| 4 | 创建 `device/` + DeviceManager（基于 transport） | 中 | 同上 |
| 5 | 创建 `channel/` + ChannelManager（基于 transport + device） | 中 | 同上 |
| 6 | 创建 `connection/` + ConnectionManager（基于 device + event） | 低 | 同上 |
| 7 | 完善 `LanFramework` 串联各模块 + FrameworkConfig | 低 | 同上 |
| 8 | 移动旧代码到 `_legacy/`，加 `@Deprecated` | 低 | 旧路径仍 import |
| 9 | 编写测试 + 验证两端通信 | 低 | 旧代码未动 |
| 10 | 更新 `localnet.dart` 导出新 API | 中 | 旧 import 仍可用 |

### 12.2 关键里程碑

- **步骤 7 完成**：LanFramework 单机自洽（只启动不通信也工作）
- **步骤 9 完成**：两端通信 demo 可跑通
- **步骤 10 完成**：业务侧可切换到新 API

### 12.3 旧代码兼容

- 旧 `LocalnetService` / `DiscoveryService` / `MessageService` / `ConfigService` 全部加 `@Deprecated('Use LanFramework instead')` 注释
- 旧 import 路径保留有效（文件移到 `_legacy/` 后，旧 import 仍能找到）
- 不强制业务迁移，业务侧按需切换

---

## 13. 开放问题（留给下一轮 brainstorm）

1. **业务会话层**：框架不维护会话，"业务会话"（如 GameSession）的统一抽象何时引入
2. **状态广播**：业务层状态同步的"唯一真相源"如何架构（主从 vs CRDT vs 事件溯源）
3. **WebSocket**：是否需要引入长连接用于实时推送（目前 HTTP 轮询够用）
4. **mDNS**：是否需要支持跨网段发现（目前 UDP 多播限同网段）
5. **鉴权 / 加密**：局域网场景是否需要简单 PIN 码 / 共享密钥保护
6. **多协议版本**：如何优雅处理协议版本升级（v1 → v2 兼容性策略）

---

## 14. 与现有 `LocalnetService` 对比

```
═══════════════════════════════════════════════════════════════════════════
  旧版（命令式 + 回调）              vs          新版（事件流 + 状态机）
═══════════════════════════════════════════════════════════════════════════

  // 旧版：注入回调                                  // 新版：订阅事件
  discovery.onMessageReceived = (msg) {              framework.watchChannel('chat')
    print(msg);                                        .listen((msg) => print(msg));
  };                                                  
  discovery.onUdpBroadcastReceived = (              framework.watchDevices()
    deviceId, ip, port, extras                        .listen((devices) => updateUI(devices));
  ) { ... };                                          
                                                      
  // 旧版：直接调用服务                                // 新版：调用框架 API
  await localnetService.start();                      await LanFramework.instance.start(cfg);
  await localnetService.sendMessage(B, text);         await LanFramework.instance.sendTo(
                                                        B.deviceId, 'chat', payload
                                                      );
                                                      
  // 旧版：业务侧需要知道内部细节                         // 新版：业务侧只关心 channel
  discovery.registerRoute(                            // 业务只需要"按 channel 收发"
    '/api/game/input', handler                        framework.sendTo(id, 'game.move', ...)
  );                                                  framework.watchChannel('game.move')
                                                          .listen(...);
  
═══════════════════════════════════════════════════════════════════════════
  核心变化：
  ① 内部细节（UDP/HTTP 协议、端口、心跳、清理）→ 全部隐藏在框架内
  ② 业务侧与框架的接触面只有 3 个 API + 事件订阅
  ③ 业务侧不再注入回调、不再注册路由、不再知道 IP:port
  ④ 状态管理统一通过 EventBus 解耦
═══════════════════════════════════════════════════════════════════════════
```
