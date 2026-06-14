---
name: lan-discovery-debug
description: 排查 Android 局域网设备发现（UDP 多播 / mDNS / NSD / Bonjour）"两台设备互不发现"问题。触发场景：用户报告"局域网搜不到对方"、"设备列表为空"、"UDP 多播不工作"、"NSD 找不到服务"，且已确认在同一 WiFi。
---

# LAN Device Discovery Debug

排查 Android/iOS 局域网设备发现问题的标准 SOP。**先验证物理网络，再动代码**。

## 1. 物理网络验证（必做，5 分钟定位 80% 问题）

让用户**两台设备都执行**以下命令，并把输出贴回来：

```bash
# A. 设备所有 IP（看是不是同子网）
adb shell ip addr | grep -E "inet |wlan|rmnet"

# B. 当前活跃网络（看是 WiFi 还是 4G）
adb shell dumpsys connectivity | grep -E "NetworkAgentInfo.*CONNECTED"

# C. 端口监听（看 HTTP/mDNS 端口是否真绑上了）
adb shell "cat /proc/net/tcp | awk '\$2 ~ /:D147/ {print}'"   # 53317 = 0xD147
adb shell "cat /proc/net/udp | awk '\$2 ~ /:D147/ {print}'"
adb shell "cat /proc/net/udp | awk '\$2 ~ /:162E/ {print}'"   # 5678 = 0x162E
```

**判断表**：

| 设备 A IP | 设备 B IP | 现象 | 根因 | 修法 |
|-----------|-----------|------|------|------|
| `192.168.x.x` wlan0 | `192.168.y.y` wlan0 | 互不发现 | 路由器 AP 隔离 或 不同 SSID | 同 SSID、关 AP 隔离 |
| `192.168.x.x` wlan0 | `10.x.x.x` wlan0 | 互不发现 | 不同子网（少见） | 看路由器 DHCP |
| `192.168.x.x` wlan0 | `10.26.x.x` rmnet0 | 互不发现 | **一台开 4G** | 关 4G 或飞行模式 |
| `192.168.43.1` wlan1 | `192.168.43.191` wlan0 | 互不发现 | **热点 + 客户端，热点端开 4G** | 热点端关 4G |
| 双方都有 IP | logcat 只收到自己 | 同上 + 路由选错 | Android 路由优先级：4G > WiFi | 关 4G |

## 2. 物理层通过后的代码检查

按"问题影响面从大到小"依次排查：

### 2.1 Android 权限

**必加权限**（UDP 多播 + mDNS 场景）：
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

**可选权限**（仅在用户报告锁屏/Doze 失效时加）：
```xml
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
```
- ⚠️ **不要默认加**。`MulticastLock` 是给 mDNS/DNS-SD 库的，不是给普通 UDP 广播的。
- 加了它 → 必须配套写 Kotlin 端 MethodChannel + Dart 端 `MethodChannel.invokeMethod`
- 普通 `RawDatagramSocket.bind + joinMulticast` 不需要

### 2.2 多播地址选择

| 地址 | 适用范围 | 是否跨路由器 |
|------|----------|--------------|
| `224.0.0.0/24` (LocalLink，如 224.0.0.167) | 仅本子网 | ❌ 多数家用路由器过滤 |
| `239.0.0.0/8` (ADMINSCOPE，如 239.255.255.255) | 私有应用 | ✅ 多数路由器转发 |
| `255.255.255.255` (Limited Broadcast) | 同子网 | ❌ 路由器不转发 |
| `224.0.0.251` (mDNS 标准) | mDNS | ✅ 系统级转发 |

**推荐**：先试 `239.255.255.255`，不行再换 mDNS（5353）。

### 2.3 端口拆分（必做）

**TCP（HTTP/JSON-RPC）和 UDP（多播/广播）必须用不同端口**：
- 理论：协议号不同可同端口共存
- 实际：Android 某些 ROM + TIME_WAIT → 各种 errno=98 / EADDRINUSE

**推荐端口分配**：
- HTTP/JSON-RPC: 53317（或用户配置）
- UDP 多播: 5678 或 mDNS 5353
- 模拟器中继单播: 53317（与 HTTP 同 — 中继是"桥接服务"，PC 端和模拟器端需一致）

### 2.4 socket 生命周期（高频 bug）

**症状**：连续 start/stop 报 `errno=98` / `EADDRINUSE`

**根因**：Dart 里 `_server.close()` 是 `Future`，同步代码不 await → 下次 start 时 socket 还在 TIME_WAIT

**修法模板**：
```dart
// 1. bind 加 shared: true
_httpServer = await HttpServer.bind(addr, port, shared: true);

// 2. stop 改为 async + force: true
Future<void> stopHttpServer({bool force = false}) async {
  final server = _httpServer;
  _httpServer = null;
  if (server == null) return;
  await server.close(force: force);  // 关键：必须 await
}

// 3. 整条 stop 链 await 化
Future<void> stop() async {
  await stopHttpServer(force: true);  // 强制立即释放
  // ...
}
```

### 2.5 UI 重入保护

**症状**：旋转屏幕 / 快速点刷新按钮 → 连续 start 撞 socket

**修法**：
```dart
bool _isStarting = false;
Future<void> _start() async {
  if (_isStarting) return;  // 标志位
  if (_service.serviceState == 'RUNNING' || _service.serviceState == 'STARTING') return;
  setState(() => _isStarting = true);
  try { await _service.start(); }
  finally { if (mounted) setState(() => _isStarting = false); }
}
```

## 3. logcat 必抓字段

让用户贴 logcat 时要求带这些 tag：
```bash
adb logcat -d | grep -E "I/flutter.*(Discovery|Localnet)"
```

**关键模式识别**：
- `★ UDP 收到: "<id>,<port>" (from <IP>)` — 收到多播包
- `忽略自己 (同 deviceId)` — 收到的是自己 loopback（说明 socket OK，但**没收到对方**）
- `忽略自己 (同 IP <X>)` — 对方设备 IP 和自己一样（极少见，可能是 socket 绑错接口）
- `设备加入: <name> (<ip>:<port>)` — HTTP /join 成功（说明 TCP 通了）
- `✓ MulticastLock 已获取` — 如果加了 Kotlin 端才看
- `✗ HTTP 服务器启动失败: errno=98` — 端口冲突
- `✗ UDP 监听失败: ...` — 权限或路由问题

## 4. 多平台补充

### iOS
- iOS 默认不允许后台 UDP 接收（除非 Background Modes 开启）
- 多播包在锁屏 30 秒后停止（NSLocalNetworkUsageDescription 也要加）
- Bonjour 用 `NSNetService`，跟 Android NSD 不兼容；用 bonsoir 库可统一

### Desktop
- Linux/macOS/Windows 多播走 lo/wlan/eth，行为正常
- Windows 防火墙默认拦多播，需要放行

## 5. 错误案例（高频坑）

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 看 bonsoir 仓库用 `MulticastLock` 就照搬 | 改 Kotlin 端 3 处，用户不需要 | 先问用户"是否真遇到锁屏/Doze 问题" |
| 把 HTTP 和 UDP 绑同端口 | errno=98 反复出现 | 拆开：HTTP 53317 / UDP 5678 |
| `_server.close()` 不 await | 下次 start 撞 TIME_WAIT | 整条 stop 链 await 化 |
| `udpListenerEnabled` 默认 true 时没考虑冲突 | 一台设备两个 socket 抢同端口 | 加 UI 重入保护 + 状态机检查 |
| 多播地址用 `224.0.0.167` | 多数家用路由器过滤 | 用 `239.255.255.255` 或 mDNS |
| 看不到对方就改代码 | 实际是物理网络问题 | 先 `adb shell ip addr` 确认同子网 |

## 6. 当所有都查完仍不工作

按这个顺序降级：
1. **有限广播** `255.255.255.255`（不跨路由器，但至少同子网能通）
2. **mDNS/DNS-SD**（用 bonsoir / nsd 库，系统级支持）
3. **中继服务器**（一台设备 HTTP POST 到中继，中继转发到另一台 — 牺牲 P2P 换稳定）
4. **手动配对**（用户输入对方 IP — 兜底）

每降一级都要在代码注释里写明降级原因，便于后续回溯。
