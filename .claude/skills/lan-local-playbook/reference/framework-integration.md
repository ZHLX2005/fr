# Framework 层集成参考

LanFramework 的标准接入流程。提取自原 `lan-framework-builder` 技能。

## 1. 框架定位

**LanFramework = UDP 多播发现 + HTTP 点对点消息 + 事件总线 + Session 状态同步**。

门面单例 `LanFramework.instance`，业务侧唯一接触点。

## 2. 完整接入流程

### Step 1: 启动框架

```dart
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

// 必须从 SharedPreferences 加载持久化的 deviceId
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

### Step 2: 探测本机 IP

必须在 start() 之后调用，否则 `NetworkInterface.list` 可能返回空。

```dart
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
  // List<Device>：deviceId / alias / ip / port / lastSeen
});
```

### Step 4: 发送消息

```dart
final result = await fw.LanFramework.instance.sendTo(
  targetDeviceId,
  'chat',                    // channel 名，业务自定义
  {'text': 'hello'},
);
```

### Step 5: 接收消息

```dart
fw.LanFramework.instance.watchChannel('chat').listen((msg) {
  // msg.sourceDeviceId — 发送方身份
  // msg.payload — sendTo 时传的 Map
  // alias 用 sourceDeviceId 从 devices 查表取
});
```

### Step 6: 退出时停止

```dart
await fw.LanFramework.instance.stop();
```

## 3. 检查清单

```
□ 1. 从 SharedPreferences 加载或生成 deviceId 并落盘
□ 2. 构造 FrameworkConfig，至少开启 httpServerEnabled
□ 3. start() 后检查 status == running
□ 4. 用 InternetAddress.lookup 探测本机 IP 并 setMyIp
□ 5. watchDevices() 订阅设备变化
□ 6. 消息按 (senderId, targetId) 分桶存储
□ 7. 收到消息时用 sourceDeviceId 查 devices 取 alias
□ 8. dispose() / stop() 成对出现
□ 9. 跑通两台真机/模拟器联调（同一 WiFi / 同一网段）
```

## 4. 两种使用模式

### 模式 A：流式消息

- 用 `sendTo` + `watchChannel`
- 业务自己按 `peerId` 维护 `Map<String, List<Message>>` 分桶
- 别名用 `LanFramework.instance.devices` 查当前最新

### 模式 B：状态同步

- 用 `createSession(peerId: x, state: myState, serializer: MySerializer())`
- `state` 必须 extends `Listenable`（ChangeNotifier 最方便）
- `serializer.serialize(state)` → Map / `deserialize(data, target)` in-place 修改
- Session 自动监听 state 变化批量同步
- channel 和 session 命名空间不冲突
