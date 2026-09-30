/// pi 聊天模块 —— 接入 nx-as(pi-web) 的移动端对话。
///
/// 结构：
/// - `pi_chat_settings.dart`            配置（SharedPreferences：地址/token/cwd/模型）
/// - `pi_chat_settings_page.dart`       设置页（配置完全在 App 内设置 + 连通测试）
/// - `pi_chat_message.dart`             消息模型（Hive typed）
/// - `pi_chat_message_repository.dart`  消息仓库（Hive + StorageRegistry）
/// - `pi_chat_controller.dart`          控制器（历史回读/发消息/流式/中止/删除）
/// - `pi_chat_page.dart`                聊天页
/// - `pi_chat_entry_page.dart`          入口壳（给 AI 助手列表用的同步构造）
///
/// API 层在 `lib/api/pi/`（按 api-module-auth 规范）。
///
/// 接入方式（[PiChatEntryPage] 已挂到 `screens/chat/home_page.dart` 的
/// `_entries`，正常点列表即可进入）：
/// ```dart
/// final settings = await PiChatSettingsPage.loadDefault();
/// Navigator.push(context, MaterialPageRoute(
///   builder: (_) => PiChatPage(settings: settings),
/// ));
/// ```
library;

export 'pi_chat_controller.dart';
export 'pi_chat_entry_page.dart';
export 'pi_chat_message.dart';
export 'pi_chat_message_repository.dart';
export 'pi_chat_page.dart';
export 'pi_chat_settings.dart';
export 'pi_chat_settings_page.dart';
export 'pi_chat_ui.dart';
export 'pi_session_list_page.dart';
