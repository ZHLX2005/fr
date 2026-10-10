// 注册会形成循环依赖的导航 Page builder（在 main 里 bootstrapLab 之后调用）。

import '../../screens/settings/app_settings_page.dart';
import 'nav_builder_registry.dart';

void registerNavBuilders() {
  registerNavBuilder('core-settings', (_) => const AppSettingsPage());
}
