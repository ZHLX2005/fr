/// LocalNet biz 服务 — 业务层只使用 transport 事件驱动
///
/// 业务层不再自己维护发现/连接/UI — 全部委托 localnet 的 widget。
/// 通过订阅 [Transport.events] 和 [Transport.watchScope] 接收数据驱动。
library;

export 'localnet_discovery_host.dart';
export 'pages/localnet_chat_page.dart';
export 'pages/localnet_debug_page.dart';
export 'pages/localnet_settings_page.dart';
export 'models/localnet_config.dart';
export 'models/localnet_constants.dart';
export 'models/localnet_device.dart';
export 'models/localnet_message.dart';