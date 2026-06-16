---
name: lan-framework-builder
description: 当用户要求"用 LanFramework 做局域网发现/通信"、"基于 localnet 框架写 xxx"、"用 framework 同步两个设备的状态"、"局域网聊天/发现怎么接入"、"两台设备互联"时触发。封装 xiaodouzi_fr 项目里 LanFramework 的标准接入流程，覆盖设备发现、点对点消息、状态同步、IP 探测、deviceId 持久化、常见坑点。
---

# LanFramework 接入工作流

在 `xiaodouzi_fr`（Flutter/Dart）项目里使用 `LanFramework` 实现局域网通信的标准流程。

## 1. 框架定位（一句话）

**LanFramework = UDP 多播发现 + HTTP 点对点消息 + 事件总线 + Session 状态同步**。
门面单例 `LanFramework.instance`，业务侧唯一接触点。

## 2. 触发场景（什么时候用这个 skill）

- 局域网内多设备发现（不需要服务器、不需要配 IP）
- 设备间点对点文本消息 / 命令 / 通知
- 两台设备之间**状态共享**（棋盘、协同白板、共享计数器）
- 替代手写 UDP/TCP socket、避开 STUN/打洞

**不适合**的场景：跨网段、需要公网中继、TCP 长连接流式音视频、严格时序保证。

## 3. 标准接入流程（按序执行）

### Step 1: 启动框架

```dart
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

// ⚠️ 必须从 SharedPreferences 加载持久化的 deviceId（首次启动生成并落盘）
// 详见「坑点 1」
final deviceId = await DeviceIdService.load();

final config = fw.FrameworkConfig(
  deviceId: deviceId,                         // 持久化的 deviceId
  deviceAlias: 'My Device',                   // 显示名
  port: 53317,                                // HTTP 通道端口
  udpBroadcastEnabled: true,                  // 主动广播（被发现）
  udpListenerEnabled: true,                   // 接收其他设备广播
  httpServerEnabled: true,                    // HTTP 接收（必开）
  broadcastInterval: Duration(seconds: 3),    // 心跳间隔
  deviceTimeout: Duration(seconds: 15),       // 离线判定阈值
);

await fw.LanFramework.instance.start(config);
```

**检查点**：启动后 `LanFramework.instance.status == FrameworkStatus.running`。

### Step 2: 探测本机 IP（必须在 start 之后）

```dart
// Android 上 NetworkInterface.list 经常枚举不全，必须用 DNS 反查
Future<String?> detectLocalIp() async {
  try {
    final addrs = await InternetAddress.lookup('dns.google')
        .timeout(Duration(seconds: 2));
    for (final a in addrs) {
      final ip = a.address;
      if (ip.isNotEmpty && ip != '0.0.0.0') return ip;
    }
  } catch (_) {}
  // 回退：枚举网络接口
  try {
    for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (ip.isNotEmpty && ip != '0.0.0.0' &&
            (ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.'))) {
          return ip;
        }
      }
    }
  } catch (_) {}
  return null;
}

final myIp = await detectLocalIp();
if (myIp != null) fw.LanFramework.instance.setMyIp(myIp);
```

### Step 3: 订阅设备列表

```dart
fw.LanFramework.instance.watchDevices().listen((devices) {
  // 收到的 List<Device>：deviceId / alias / ip / port / lastSeen
  // 同一 deviceId 会被合并，重复 add 自动覆盖
});
```

### Step 4: 发送消息（按 deviceId 寻址）

```dart
final result = await fw.LanFramework.instance.sendTo(
  targetDeviceId,
  'chat',                    // channel 名，业务自定义
  {'text': 'hello'},         // 纯数据载荷，不要塞身份字段
);
```

### Step 5: 接收消息

```dart
fw.LanFramework.instance.watchChannel('chat').listen((msg) {
  // msg.sourceDeviceId — 发送方身份（用这个查 deviceRegistry 取 alias）
  // msg.payload — sendTo 时传的 Map
  // 不要用 msg.payload['alias'] — 那是脏字段，sendTo 根本没传
});
```

### Step 6: 退出时停止

```dart
await fw.LanFramework.instance.stop();
```

## 4. 两种使用模式速查

### 模式 A：流式消息（聊天、命令、通知）

- 用 `sendTo` + `watchChannel`
- 业务自己按 `peerId` 维护 `Map<String, List<Message>>` 分桶
- 别名用 `LanFramework.instance.devices` 查当前最新，**不要**从 payload 取

### 模式 B：状态同步（棋盘、白板、计数器）

- 用 `createSession(peerId: x, state: myState, serializer: MySerializer())`
- `state` 必须 extends `Listenable`（ChangeNotifier 最方便）
- `serializer` 实现 `StateSerializer<S>`：`serialize(state) -> Map` / `deserialize(data, target) -> target`（**in-place 修改 target，不要替换**）
- Session 自动监听 state 变化批量同步，监听器模式触发 UI 刷新
- channel 命名空间 `session/{peerId}_{hashCode}` 自动隔离，和模式 A 不冲突

**重要**：模式 B 是**状态同步**，不是消息流。没有时间序、没有"消息"概念。

## 5. 坑点对照表（高频错误 + 正确做法）

| # | 错误操作 | 实际后果 | 正确做法 |
|---|---------|---------|---------|
| 1 | 每次启动不传 `deviceId`，让框架生成新 UUID | 对端重连时看到"老 B 离线 + 新 B 上线"两条记录 | 启动前从 SharedPreferences 读取或生成并落盘 |
| 2 | 用 `NetworkInterface.list` 不加 fallback | Android 上枚举不到 `wlan0`，IP 显示 null | 先 `InternetAddress.lookup('dns.google')` 失败再 fallback |
| 3 | 用 `Socket.connect(8.8.8.8).address.address` 取 IP | 返回的是对端地址 `8.8.8.8`（不是本端） | 改用 `InternetAddress.lookup` 反查 |
| 4 | 消息用全局 List 不分桶 | 多个 peer 的聊天页串台 | `Map<peerId, List<Message>>` 分桶 |
| 5 | `msg.payload['alias']` 当昵称 | sendTo 根本没传 alias，回退成 UUID | 用 `msg.sourceDeviceId` 去 `devices` 查当前 alias |
| 6 | 三项开关全 false 时还调 start | start 默默成功，状态 RUNNING，实际啥都没发 | FrameworkCore 已加守卫抛 StateError；config.load() 加全-false 兜底 |
| 7 | `RawDatagramSocket.bind(... reusePort: true)` | Android/Windows 报 `reusePort not supported` | 只用 `reuseAddress: true` 即可 |
| 8 | demo 退出没调 stop | socket 残留，下一次 start errno=98（端口占用） | StatefulWidget.dispose() 里调 `_service.stop()` |
| 9 | 用 session 层做聊天流 | session 是状态同步，没有时间序；同 peer 多 session 会 hashCode 冲突 | 聊天用 `sendTo/watchChannel`；状态共享才用 `createSession` |
| 10 | `dispose()` 里直接关 `StreamController.close()` | 业务还在监听 stream，会收到 close 异常 | stop 先取消订阅，再 close stream |

## 6. 完整接入检查清单

```
□ 1. 从 SharedPreferences 加载或生成 deviceId 并落盘
□ 2. 构造 FrameworkConfig，至少开启 httpServerEnabled
□ 3. start() 后检查 status == running
□ 4. 用 InternetAddress.lookup 探测本机 IP 并 setMyIp
□ 5. watchDevices() 订阅设备变化
□ 6. 消息按 (senderId, targetId) 分桶存储
□ 7. 收到消息时用 sourceDeviceId 查 devices 取 alias
□ 8. StatefulWidget.dispose() 里 stop()
□ 9. 跑通两台真机/模拟器联调（同一 WiFi / 同一网段）
```

## 7. 调试技巧

- `framework_status` stream — 看状态机：`init → starting → running → stopping → init`
- 监听 `framework.eventBus.watch<DeviceFoundEvent/DeviceLostEvent/DeviceUpdatedEvent>()` 看设备生命周期
- `framework.eventBus.watch<ConnectionStateEvent>()` 看设备在线状态变化
- 真机调试时务必同 WiFi，且关闭手机"流量节省"或"随机 MAC"开关
- 防火墙：HTTP 端口（默认 53317）和 UDP 多播（5678）都需放行

## 8. 一句话口诀

> **持久化 deviceId、socket 探 IP、分桶存消息、alias 查表、退出 stop、状态用 session、消息用 channel。**

## 9. 相关文件路径

- 门面：`lib/core/localnet/framework/lan_framework.dart`
- 编排：`lib/core/localnet/framework/framework_core.dart`
- 设备：`lib/core/localnet/device/{device_manager,device_registry}.dart`
- 通道：`lib/core/localnet/channel/channel_manager.dart`
- Session：`lib/core/localnet/session/{session,session_manager,state_serializer}.dart`
- 导出：`lib/core/localnet/localnet.dart`
- 设备 ID 持久化模板：`lib/core/localnet_biz/services/device_id_service.dart`
- 适配层示例（不推荐新代码再用）：`lib/core/localnet_biz/localnet_service.dart`
