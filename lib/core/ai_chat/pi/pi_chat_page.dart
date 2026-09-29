import 'package:flutter/material.dart';

import 'pi_chat_controller.dart';
import 'pi_chat_message.dart';
import 'pi_chat_settings.dart';
import 'pi_chat_settings_page.dart';

/// pi 聊天页 —— 建会话 / 发消息 / SSE 流式渲染 / 历史回读。
///
/// 控制器 [PiChatController] 持有状态；配置来自 [PiChatSettings]
/// （SharedPreferences），消息持久化在 Hive（重启回读即恢复）。
class PiChatPage extends StatefulWidget {
  final PiChatSettings settings;
  final String? initialSessionId;

  const PiChatPage({super.key, required this.settings, this.initialSessionId});

  @override
  State<PiChatPage> createState() => _PiChatPageState();
}

class _PiChatPageState extends State<PiChatPage> {
  late final PiChatController _controller;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = PiChatController(settings: widget.settings);
    _controller.addListener(_onChange);
    _init();
  }

  Future<void> _init() async {
    await _controller.ensureInit();
    final sid = widget.initialSessionId;
    if (sid != null && sid.isNotEmpty) {
      await _controller.openSession(sid);
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
    // 有新消息时滚到底
    if (_scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _controller.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await _controller.send(text);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PiChatSettingsPage(settings: widget.settings),
    ));
    setState(() {}); // 设置可能已变化
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured = _controller.canChat;
    return Scaffold(
      appBar: AppBar(
        title: Text(_controller.sessionId == null
            ? 'pi 聊天（新会话）'
            : 'pi 聊天 · ${_controller.sessionId!.substring(0, 8)}…'),
        actions: [
          IconButton(
            tooltip: '新建会话',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: configured ? () => _controller.newSession() : null,
          ),
          if (_controller.sending)
            IconButton(
              tooltip: '中止',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () => _controller.abort(),
            ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: !configured
          ? _NotConfiguredView(onOpenSettings: _openSettings)
          : Column(
              children: [
                if (_controller.lastError != null)
                  Material(
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.error_outline),
                      title: Text(_controller.lastError!,
                          style: theme.textTheme.bodySmall),
                    ),
                  ),
                Expanded(
                  child: _controller.messages.isEmpty
                      ? Center(
                          child: Text('发一条消息开始对话',
                              style: theme.textTheme.bodySmall),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: _controller.messages.length,
                          itemBuilder: (context, i) =>
                              _Bubble(message: _controller.messages[i]),
                        ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: const InputDecoration(
                              hintText: '发消息…',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _controller.sending ? null : _send,
                          icon: _controller.sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final PiChatMessage message;

  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == 'user';
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = isUser
        ? theme.colorScheme.primaryContainer
        : (message.error != null
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest);
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message.text.isEmpty && message.pending ? '…' : message.text,
              style: theme.textTheme.bodyMedium,
            ),
            if (message.error != null) ...[
              const SizedBox(height: 4),
              Text(message.error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error)),
            ],
            if (!message.done && message.text.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('正在输入…', style: theme.textTheme.labelSmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotConfiguredView extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _NotConfiguredView({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 12),
          Text('尚未配置 pi 服务',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('需要服务地址与 device token', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}
