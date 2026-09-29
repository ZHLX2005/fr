import 'package:flutter/material.dart';

import 'pi_chat_page.dart';
import 'pi_chat_settings.dart';
import 'pi_chat_settings_page.dart';

/// pi 聊天入口页 —— 给「AI 助手」功能列表用的同步构造壳。
///
/// `HomePage._entries` 的 `AssistantEntry.builder` 是同步的
/// （`Widget Function(BuildContext)`），而 [PiChatSettings] 走
/// SharedPreferences 必须 await 才能拿到。所以这里做一层包装：
/// 同步构造 → initState 里异步 hydrate → 交给 [PiChatPage]。
///
/// 未配置时不用在这里判断 —— [PiChatPage] 自带未配置引导
/// （`_NotConfiguredView` + 去设置按钮），hydrate 完成直接放行即可。
class PiChatEntryPage extends StatefulWidget {
  const PiChatEntryPage({super.key});

  @override
  State<PiChatEntryPage> createState() => _PiChatEntryPageState();
}

class _PiChatEntryPageState extends State<PiChatEntryPage> {
  PiChatSettings? _settings;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    final s = await PiChatSettingsPage.loadDefault();
    if (!mounted) return;
    setState(() => _settings = s);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return PiChatPage(settings: settings);
  }
}
