/// LocalNet 业务接入层 - Demo/旧代码导出入口
///
/// 旧 API（`localnetService` 等）已迁移至此，仍可使用但不推荐。
/// 新代码应使用 `package:xiaodouzi_fr/core/localnet/localnet.dart` 的 [LanFramework.instance]。
library;

export 'localnet_service.dart';
export 'services/config_service.dart';
export 'services/debug_log_service.dart';
export 'models/localnet_config.dart';
export 'models/localnet_constants.dart';
export 'models/localnet_device.dart';
export 'models/localnet_message.dart';

export 'pages/localnet_discover_page.dart';
export 'pages/localnet_chat_page.dart';
export 'pages/localnet_debug_page.dart';
export 'pages/localnet_settings_page.dart';
