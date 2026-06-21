# 设备发现调试 SOP

排查 Android 局域网设备发现（UDP 多播 / mDNS）"两台设备互不发现"问题的标准流程。提取自原 `lan-discovery-debug` 技能。

## 1. 物理网络验证（必做，先于代码检查）

让用户两台设备都执行以下命令：

```bash
# A. 设备所有 IP（看是不是同子网）
adb shell ip addr | grep -E "inet |wlan|rmnet"

# B. 当前活跃网络（看是 WiFi 还是 4G）
adb shell dumpsys connectivity | grep -E "NetworkAgentInfo.*CONNECTED"

# C. 端口监听（看 HTTP/UDP 端口是否真绑上了）
adb shell "cat /proc/net/tcp | awk '\$2 ~ /:D147/ {print}'"   # 53317 = 0xD147
adb shell "cat /proc/net/udp | awk '\$2 ~ /:D147/ {print}'"
adb shell "cat /proc/net/udp | awk '\$2 ~ /:162E/ {print}'"   # 5678 = 0x162E
```

### 判断表

| 设备 A IP | 设备 B IP | 现象 | 根因 | 修法 |
|-----------|-----------|------|------|------|
| `192.168.x.x` wlan0 | `192.168.y.y` wlan0 | 互不发现 | 路由器 AP 隔离 或 不同 SSID | 同 SSID、关 AP 隔离 |
| `192.168.x.x` wlan0 | `10.x.x.x` wlan0 | 互不发现 | 不同子网（少见） | 看路由器 DHCP |
| `192.168.x.x` wlan0 | `10.26.x.x` rmnet0 | 互不发现 | **一台开 4G** | 关 4G 或飞行模式 |
| `192.168.43.1` wlan1 | `192.168.43.191` wlan0 | 互不发现 | **热点+客户端，热点端开 4G** | 热点端关 4G |
| 双方都有 IP | logcat 只收到自己 | 同上 + 路由选错 | Android 路由优先级：4G > WiFi | 关 4G |

## 2. 代码层排查

### 2.1 Android 权限

```xml
<!-- 必加：UDP 多播 -->
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />

<!-- 可选：仅在锁屏/Doze 失效时加 -->
<!-- <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" /> -->
```

⚠️ `MulticastLock` 不需要默认加。普通 `RawDatagramSocket.bind + joinMulticast` 不需要。

### 2.2 多播地址选择

| 地址 | 适用范围 | 是否跨路由器 |
|------|----------|--------------|
| `224.0.0.0/24` (LocalLink) | 仅本子网 | ❌ 多数家用路由器过滤 |
| `239.0.0.0/8` (ADMINSCOPE) | 私有应用 | ✅ 多数路由器转发 |
| `255.255.255.255` (Limited Broadcast) | 同子网 | ❌ 路由器不转发 |
| `224.0.0.251` (mDNS 标准) | mDNS | ✅ 系统级转发 |

**推荐**：先试 `239.255.255.255`，不行再换 mDNS（5353）。

### 2.3 端口拆分

TCP（HTTP/JSON-RPC）和 UDP（多播/广播）必须用不同端口：

- HTTP/JSON-RPC: 53317
- UDP 多播: 5678
- 模拟器中继单播: 53317（与 HTTP 同）

### 2.4 Socket 生命周期

连续 start/stop 报 `errno=98` / `EADDRINUSE` 的典型根因：

```dart
// 修法模板
// 1. bind 加 shared: true
_httpServer = await HttpServer.bind(addr, port, shared: true);

// 2. stop 设为 async + force: true
Future<void> stopHttpServer({bool force = false}) async {
  final server = _httpServer;
  _httpServer = null;
  if (server == null) return;
  await server.close(force: force);  // 必须 await
}

// 3. 整条 stop 链 await 化
Future<void> stop() async {
  await stopHttpServer(force: true);
  // ...
}
```

### 2.5 UI 重入保护

```dart
bool _isStarting = false;
Future<void> _start() async {
  if (_isStarting) return;
  if (/* 已 RUNNING 或 STARTING */) return;
  setState(() => _isStarting = true);
  try { await _service.start(); }
  finally { if (mounted) setState(() => _isStarting = false); }
}
```

## 3. logcat 关键模式

```bash
adb logcat -d | grep -E "I/flutter.*(Discovery|Localnet)"
```

| 日志模式 | 含义 |
|---------|------|
| `★ UDP 收到: "<id>,<port>" (from <IP>)` | 收到多播包，正常 |
| `忽略自己 (同 deviceId)` | 收到自己 loopback，socket OK 但没收到对方 |
| `忽略自己 (同 IP <X>)` | 对方 IP 和自己一样（极少见） |
| `设备加入: <name> (<ip>:<port>)` | HTTP /join 成功 |
| `✗ HTTP 服务器启动失败: errno=98` | 端口冲突 |
| `✗ UDP 监听失败: ...` | 权限或路由问题 |

## 4. 多平台补充

### iOS
- 默认不允许后台 UDP 接收（需开启 Background Modes）
- 锁屏后 30 秒停止接收多播
- 需添加 `NSLocalNetworkUsageDescription` 权限描述

### Desktop
- Linux/macOS/Windows 行为正常
- Windows 防火墙默认拦多播，需要放行

## 5. 降级路径

当所有都查完仍不工作，按此顺序降级：

1. **有限广播** `255.255.255.255`（至少同子网能通）
2. **mDNS/DNS-SD**（用 bonsoir / nsd 库）
3. **中继服务器**（HTTP POST 到中继转发）
4. **手动配对**（用户输入对方 IP — 兜底）

每降一级都在代码注释里写明降级原因。
