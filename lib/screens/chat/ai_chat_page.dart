import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/ai_chat_provider.dart';
import '../../models/ai_chat_message.dart';
import '../../widgets/markdown_renderer_widget.dart';
import 'ai_chat_settings_page.dart';

/// AI 聊天页面
class AIChatPage extends StatefulWidget {
  final String title;

  const AIChatPage({
    super.key,
    this.title = 'AI 聊天',
  });

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _scrollToBottom() async {
    if (_scrollController.hasClients) {
      await Future.delayed(const Duration(milliseconds: 100));
      final position = _scrollController.position;
      if (position.maxScrollExtent.isFinite) {
        _scrollController.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Future<void> _handleSend(String content) async {
    if (content.trim().isEmpty || _isSending) return;

    final aiProvider = context.read<AIChatProvider>();

    // 检查是否配置了 API Key
    if (!aiProvider.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先配置 API Key'),
          action: SnackBarAction(
            label: '去设置',
            onPressed: () => _openSettings(),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    _inputController.clear();

    // 发送消息
    await aiProvider.sendMessage(content.trim());

    await _scrollToBottom();

    if (mounted) {
      setState(() {
        _isSending = false;
      });
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AIChatSettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.smart_toy,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(fontSize: 16),
                  ),
                  Consumer<AIChatProvider>(
                    builder: (context, provider, _) {
                      if (provider.isLoading) {
                        return const Text(
                          '思考中...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        );
                      }
                      return Text(
                        provider.isConfigured ? '已连接' : '未配置',
                        style: TextStyle(
                          fontSize: 12,
                          color: provider.isConfigured ? Colors.green : Colors.orange,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'AI 设置',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') {
                _showClearDialog();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Text('清空聊天记录'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<AIChatProvider>(
              builder: (context, aiProvider, child) {
                final messages = aiProvider.messages;

                if (messages.isEmpty) {
                  return _buildEmptyState(aiProvider);
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: messages.length + (aiProvider.isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    // 如果正在加载，显示加载指示器
                    if (aiProvider.isLoading && index == messages.length) {
                      return const _LoadingIndicator();
                    }

                    final message = messages[index];
                    return _MessageBubble(
                      message: message,
                      isMe: message.role == 'user',
                    );
                  },
                );
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AIChatProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              Icons.smart_toy,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'AI 聊天助手',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            provider.isConfigured
                ? '开始你的对话吧'
                : '请先配置 API Key',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.5),
                ),
          ),
          if (!provider.isConfigured) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings),
              label: const Text('去设置'),
            ),
          ],
          const SizedBox(height: 24),
          // 快捷提示
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _QuickReply(
                text: '你好',
                onTap: () => _handleSend('你好'),
              ),
              _QuickReply(
                text: '帮我写首诗',
                onTap: () => _handleSend('帮我写一首关于春天的诗'),
              ),
              _QuickReply(
                text: '解释一下AI',
                onTap: () => _handleSend('请简单解释一下什么是人工智能'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                decoration: InputDecoration(
                  hintText: '发送消息...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (value) => _handleSend(value),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: _isSending
                    ? null
                    : () => _handleSend(_inputController.text),
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: const Text('确定要清空所有聊天记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<AIChatProvider>().clearMessages();
              Navigator.pop(context);
            },
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AIChatMessage message;
  final bool isMe;

  const _MessageBubble({
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.95,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isLoading)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isMe ? Colors.white : theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '思考中...',
                    style: TextStyle(
                      color: isMe
                          ? Colors.white70
                          : theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              )
            else if (isMe)
              Text(
                message.content,
                style: TextStyle(
                  color: isMe
                      ? Colors.white
                      : theme.colorScheme.onSurface,
                ),
              )
            else
              MarkdownRendererWidget(
                data: message.content,
              ),
          ],
        ),
      ),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('AI 正在思考...'),
          ],
        ),
      ),
    );
  }
}

class _QuickReply extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _QuickReply({
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
