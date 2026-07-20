/// LocalNet 局域网通信框架 - 公共导出入口
///
/// 新代码应使用 [LanFramework.instance]：
///
/// ```dart
/// final fw = LanFramework.instance;
/// await fw.start(FrameworkConfig(deviceAlias: 'MyPhone'));
/// fw.watchDevices().listen((devices) => print(devices));
/// await fw.sendTo(otherDeviceId, 'chat', {'text': 'hi'});
/// ```
library;

export 'framework/framework_config.dart';
export 'framework/framework_lan_core.dart';
export 'framework/framework_status.dart';
export 'framework/lan_framework.dart';
export 'framework/exception/framework_exception.dart';

export 'event_bus/event_bus.dart';
export 'event_bus/lan_event.dart';

export 'device/device.dart';
export 'device/device_manager.dart';

export 'channel/channel_message.dart';
export 'channel/send_result.dart';
export 'channel/channel_manager.dart';

export 'connection/connection_quality.dart';
export 'connection/connection_manager.dart';

export 'transport/transport_kind.dart';
export 'transport/transport_config.dart';
export 'transport/transport.dart';
export 'transport/udp_transport.dart';
export 'transport/http_transport.dart';
