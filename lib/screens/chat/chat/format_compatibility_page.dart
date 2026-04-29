import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../../services/message_strategy/interfaces/interfaces.dart';
import '../../../services/message_strategy/data/data.dart';
import '../../../services/message_strategy/factory/factory.dart';

/// 格式兼容性测试页面
/// 使用策略模式展示各种消息组件
class FormatCompatibilityPage extends StatefulWidget {
  const FormatCompatibilityPage({super.key});

  @override
  State<FormatCompatibilityPage> createState() => _FormatCompatibilityPageState();
}

class _FormatCompatibilityPageState extends State<FormatCompatibilityPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  final List<_DisplayMessage> _messages = [];

  // Mock 数据示例
  final Map<String, IMessageData> _mockData = {
    'text': TextMessageData('这是一条普通的纯文本消息，直接显示内容。'),
    'markdown': MarkdownMessageData('''**粗体文本** 和 *斜体文本*

~~删除线~~

```dart
void main() {
  print("Hello");
}
```'''),
    'html': HtmlMessageData('''<p>这是 <strong>粗体</strong> 和 <em>斜体</em></p>

<ul>
  <li>列表项 1</li>
  <li>列表项 2</li>
</ul>

<blockquote>引用块</blockquote>

<code>行内代码</code>'''),
  };

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

  void _handleSend(String type) async {
    final trimmedType = type.trim().toLowerCase();
    if (trimmedType.isEmpty) return;

    // 检查 Mock 数据是否存在
    if (!_mockData.containsKey(trimmedType)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('不支持的 type: $trimmedType，支持的类型: text, markdown, html'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // 添加用户消息
    setState(() {
      _messages.add(_DisplayMessage(
        type: trimmedType,
        isMe: true,
      ));
    });

    _inputController.clear();
    await _scrollToBottom();

    // 模拟 AI 响应
    await Future.delayed(const Duration(milliseconds: 500));

    final messageData = _mockData[trimmedType]!;
    setState(() {
      _messages.add(_DisplayMessage(
        type: trimmedType,
        isMe: false,
        messageData: messageData,
      ));
    });

    await _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final factory = GetIt.instance<MessageWidgetFactory>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(
                Icons.format_align_left,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Format 测试', style: TextStyle(fontSize: 16)),
                  Text(
                    '策略模式渲染演示',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _messages.clear();
              });
            },
            tooltip: '重置',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return _FormatMessageBubble(
                        message: message,
                        isMe: message.isMe,
                        factory: factory,
                      );
                    },
                  ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
              child: Icon(
                Icons.format_align_left,
                size: 40,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '格式兼容性测试',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '输入 type 名称，查看对应组件渲染效果',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Text(
              '支持的 type：',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _QuickReply(
                  text: 'text',
                  onTap: () => _handleSend('text'),
                ),
                _QuickReply(
                  text: 'markdown',
                  onTap: () => _handleSend('markdown'),
                ),
                _QuickReply(
                  text: 'html',
                  onTap: () => _handleSend('html'),
                ),
              ],
            ),
          ],
        ),
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
                  hintText: '输入 type (text/markdown/html)...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
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
                color: Theme.of(context).colorScheme.secondary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: () => _handleSend(_inputController.text),
                icon: const Icon(Icons.send, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisplayMessage {
  final String type;
  final bool isMe;
  final IMessageData? messageData;

  _DisplayMessage({
    required this.type,
    required this.isMe,
    this.messageData,
  });
}

class _FormatMessageBubble extends StatelessWidget {
  final _DisplayMessage message;
  final bool isMe;
  final MessageWidgetFactory factory;

  const _FormatMessageBubble({
    required this.message,
    required this.isMe,
    required this.factory,
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
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                message.type.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                ),
              ),
              child: isMe
                  ? Text(
                      message.type,
                      style: TextStyle(
                        color: isMe ? Colors.white : theme.colorScheme.onSurface,
                      ),
                    )
                  : message.messageData != null
                      ? factory.create(context, message.messageData!)
                      : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickReply extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _QuickReply({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSecondaryContainer,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
