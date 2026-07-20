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
export 'framework/framework_core.dart';
export 'framework/framework_lan_core.dart';
export 'framework/framework_relay_core.dart';
export 'framework/framework_status.dart';
export 'framework/lan_framework.dart';
export 'framework/exception/framework_exception.dart';

export 'event_bus/event_bus.dart';
export 'event_bus/lan_event.dart';

export 'device/device.dart';
export 'device/device_manager.dart';

export 'discovery/remote_endpoint.dart';
export 'discovery/discovery_service.dart';
export 'discovery/lan_discovery.dart';
export 'discovery/relay_discovery.dart';

export 'channel/channel_message.dart';
export 'channel/send_result.dart';
export 'channel/channel_manager.dart';

export 'connection/connection_quality.dart';
export 'connection/connection_manager.dart';

export 'util/network_util.dart';

export 'transport_service/transport_service.dart';
export 'transport_service/lan_transport_service.dart';
export 'transport_service/relay_transport_service.dart';

export 'transport/transport_kind.dart';
export 'transport/transport_config.dart';
export 'transport/transport.dart';
export 'transport/udp_transport.dart';
export 'transport/http_transport.dart';
export 'transport/transport_frame.dart';
export 'transport/ws_transport.dart';
export 'transport/chat_payload.dart';

export 'transport_channel/transport_channel.dart' hide SendResult;
export 'transport_channel/lan_channel.dart';
export 'transport_channel/relay_channel.dart';
