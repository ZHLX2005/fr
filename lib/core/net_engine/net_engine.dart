/// NetEngine — 数据同步层（公共导出入口）
///
/// 模块结构：
/// - **Transport** 抽象父类：LAN 共性；v3 有专属传输层
/// - **LanDiscovery**：LAN 发现 widget
/// - **RelayV3Transport / RelayV3Widget**：v3 snapshot + Lua 协议
/// - **DataLog**：scope 内最终一致状态（LAN 沿用）
/// - **TransportEvent**：传输层事件总线原语
///
/// 业务层调用：
/// ```dart
/// // 1. 选择发现方式
/// LanDiscovery().buildPage(onPeerSelected: (peer, transport) async {
///   final transport = await LanTransport.create();
///   await transport.joinScope('lobby-${peer.id}');
///   transport.events.where((e) => e.topic == 'xxx').listen(...);
///   transport.watchScope('lobby-${peer.id}').listen((log) {
///     print('state: ${log.state}');
///   });
/// });
/// ```
library;

// 新模块 — Transport + DataLog + Discovery + HTTP
export 'transport.dart';
export 'net_engine_types.dart';

export 'lan/lan_transport.dart';
export 'lan/lan_discovery.dart';

// v3 — Lua state machine + snapshot-driven transport
export 'relay_v3/relay_v3_transport.dart';
export 'relay_v3/relay_v3_widget.dart';

export 'io/udp_socket.dart' hide UdpDatagram;

// HTTP 可靠通信
export 'http/http_server.dart';
export 'http/http_client.dart';
export 'http/http_endpoints.dart';

// 服务 / 页面
export 'services/debug_log_service.dart';
export 'pages/net_engine_debug_page.dart';
export 'pages/net_engine_settings_page.dart';

// Widgets
export 'widgets/participants_grid.dart';

// 遗留兼容 — 已删除：所有旧 framework/event_bus/device/discovery/channel/connection/transport/session/util 类