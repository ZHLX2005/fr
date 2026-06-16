# LocalNet 旧 API（已废弃）

此目录下的 API 已废弃，仅为向后兼容保留。

**新代码请使用 `LanFramework.instance`：**

```dart
import 'package:xiaodouzi_fr/core/localnet/localnet.dart';

final fw = LanFramework.instance;
await fw.start(FrameworkConfig(deviceAlias: 'MyPhone'));
fw.watchDevices().listen((devices) => updateUI(devices));
```

## 迁移对照

| 旧 API | 新 API |
|---|---|
| `localnetService.start()` | `LanFramework.instance.start(FrameworkConfig)` |
| `localnetService.devicesStream` | `LanFramework.instance.watchDevices()` |
| `localnetService.sendMessage(device, text)` | `LanFramework.instance.sendTo(device.id, 'chat', {'text': text})` |
| `discoveryService.onMessageReceived = ...` | `LanFramework.instance.watchChannel('chat').listen(...)` |
| `discoveryService.registerRoute(path, h)` | `LanFramework.instance.sendTo(...)` / `watchChannel(...)` |
| `localnetService.config` | `FrameworkConfig` |

## 清理计划

待业务侧全部迁移到新 API 后（下一轮），此目录将被删除。
