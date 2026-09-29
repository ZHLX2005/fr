import 'dart:async';

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
/// **健壮性约定（踩过白屏的坑，别简化）**：
/// 1. hydrate 有**超时**——平台通道异常时 await 可能永不返回，界面会永远转圈，
///    用户看到的就是「空白」。超时后必须出错误页。
/// 2. hydrate **抛异常**时出错误页 + 重试按钮，而不是让 `_settings` 永远为 null。
/// 3. 任何状态下都必须渲染出**可见内容**（加载指示 / 内容 / 错误页），禁止白屏。
class PiChatEntryPage extends StatefulWidget {
  /// hydrate 超时（默认 8s）。测试可注入更短的值。
  final Duration hydrateTimeout;

  /// 配置加载器（默认走 SharedPreferences）。
  /// 测试注入可抛出/可挂起的实现，用来验证错误态与超时态。
  final Future<PiChatSettings> Function()? settingsLoader;

  const PiChatEntryPage({
    super.key,
    this.hydrateTimeout = const Duration(seconds: 8),
    this.settingsLoader,
  });

  @override
  State<PiChatEntryPage> createState() => _PiChatEntryPageState();
}

enum _EntryPhase { loading, ready, failed }

class _PiChatEntryPageState extends State<PiChatEntryPage> {
  _EntryPhase _phase = _EntryPhase.loading;
  PiChatSettings? _settings;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    if (mounted) {
      setState(() {
        _phase = _EntryPhase.loading;
        _error = null;
      });
    }
    try {
      final loader = widget.settingsLoader ?? PiChatSettingsPage.loadDefault;
      final s = await loader().timeout(widget.hydrateTimeout);
      if (!mounted) return;
      setState(() {
        _settings = s;
        _phase = _EntryPhase.ready;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = '读取配置超时（${widget.hydrateTimeout.inSeconds}s）';
        _phase = _EntryPhase.failed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _phase = _EntryPhase.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _EntryPhase.loading:
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('正在加载 pi 配置…'),
              ],
            ),
          ),
        );
      case _EntryPhase.failed:
        return _EntryErrorView(error: _error, onRetry: _hydrate);
      case _EntryPhase.ready:
        return PiChatPage(settings: _settings!);
    }
  }
}

/// 入口加载失败页：可读的错误信息 + 重试。
///
/// 存在的意义：任何异常都不该只留下一个白屏——用户至少要知道发生了什么、能重试。
class _EntryErrorView extends StatelessWidget {
  final Object? error;
  final Future<void> Function() onRetry;

  const _EntryErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('pi')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('pi 加载失败', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText(
                '$error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => onRetry(),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
