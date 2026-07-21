/// LocalNet — 数据同步层（公共导出入口）
///
/// 新模块结构：
/// - **Transport** 抽象父类：LAN 和 Relay 共性
/// - **LanTransport** / **RelayTransport**：具体实现
/// - **LanDiscovery** / **RelayDiscovery**：发现 widget（**没有抽象**，差异大）
/// - **DataLog**：scope 内最终一致状态
/// - **TransportEvent**：传输层事件总线原语
///
/// 业务层调用：
/// ```dart
/// // 1. 选择发现方式
/// LanDiscovery().buildPage(onPeerSelected: (peer, transport) async {
///   // 2. 创建传输
///   final transport = await LanTransport.create();
///   // 3. 加入 scope（自动全广播同步）
///   await transport.joinScope('lobby-${peer.id}');
///   // 4. 订阅事件总线（数据驱动）
///   transport.events.where((e) => e.topic == 'xxx').listen(...);
///   // 5. 订阅 scope 状态
///   transport.watchScope('lobby-${peer.id}').listen((log) {
///     print('state: ${log.state}');
///   });
/// });
/// ```
library;

// 新模块（导出时主动 hide 旧类同名）
export 'transport.dart';
export 'transport_event.dart';
export 'localnet_types.dart';

export 'lan/lan_transport.dart';
export 'lan/lan_discovery.dart';

export 'relay/relay_transport.dart';
export 'relay/relay_discovery.dart';

export 'io/udp_socket.dart' hide UdpDatagram;

// 服务 / 页面
export 'services/debug_log_service.dart';
export 'pages/localnet_debug_page.dart';
export 'pages/localnet_settings_page.dart';

// 兼容：旧模块 — 用 hide 避免冲突
export 'framework/framework_config.dart';
export 'framework/framework_core.dart';
export 'framework/framework_lan_core.dart';
export 'framework/framework_relay_core.dart';
export 'framework/framework_status.dart';
export 'framework/lan_framework.dart' show LanFramework;
export 'framework/exception/framework_exception.dart';

export 'event_bus/event_bus.dart';
export 'event_bus/lan_event.dart';

export 'device/device.dart';
export 'device/device_manager.dart';

// Discovery 旧类被新类同名覆盖 → 旧 LanDiscovery 用 show，新 LanDiscovery 直接是新的
export 'discovery/discovery_service.dart';
export 'discovery/discovery_event.dart';
export 'discovery/discovery_peer.dart';
export 'discovery/lan_discovery.dart' hide LanDiscovery;
export 'discovery/relay_discovery.dart' hide RelayDiscovery;

export 'channel/channel_message.dart';
export 'channel/send_result.dart';
export 'channel/channel_manager.dart';

export 'connection/connection_quality.dart';
export 'connection/connection_manager.dart';

// Transport 旧基类用 hide
export 'transport/transport.dart' hide Transport;
export 'transport/transport_kind.dart';
export 'transport/transport_config.dart';
export 'transport/udp_transport.dart' hide UdpDatagram;
export 'transport/http_transport.dart';
export 'transport/ws_transport.dart';
export 'transport/transport_frame.dart';
export 'transport/chat_payload.dart';

export 'transport_channel/transport_channel.dart' hide SendResult;
export 'transport_channel/lan_channel.dart';
export 'transport_channel/relay_channel.dart';

// TransportService 旧类 hide TransportEvent
export 'transport_service/transport_service.dart' hide TransportEvent;
export 'transport_service/lan_transport_service.dart';
export 'transport_service/relay_transport_service.dart';

export 'session/session.dart';
export 'session/state_serializer.dart';
export 'util/network_util.dart';