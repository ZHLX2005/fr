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

// 新模块 — Transport + DataLog + Discovery
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

// 遗留兼容 — 已删除：所有旧 framework/event_bus/device/discovery/channel/connection/transport/session/util 类