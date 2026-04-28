import 'package:flutter/material.dart';
import '../../../widgets/markdown_renderer_widget.dart';
import '../../../widgets/html_renderer_widget.dart';

/// 格式兼容性测试页面
/// 展示各种消息格式的渲染效果，布局与 AgentChatPage 相同
class FormatCompatibilityPage extends StatefulWidget {
  const FormatCompatibilityPage({super.key});

  @override
  State<FormatCompatibilityPage> createState() => _FormatCompatibilityPageState();
}

class _FormatCompatibilityPageState extends State<FormatCompatibilityPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  final List<_FormatMessage> _messages = [];
  int _responseIndex = 0;

  // 预定义的响应示例
  final List<_FormatExample> _examples = [
    _FormatExample(
      label: '纯文本',
      content: '这是一条普通的纯文本消息，直接显示内容。',
    ),
    _FormatExample(
      label: 'Markdown 粗体/斜体',
      content: '**粗体文本** 和 *斜体文本*\n\n~~删除线~~',
    ),
    _FormatExample(
      label: 'Markdown 代码块',
      content: '''```dart
void main() {
  print("Hello");
}
```''',
    ),
    _FormatExample(
      label: 'Markdown 列表',
      content: '''1. 第一步操作
2. 第二步操作
3. 第三步操作

- 无序列表项
- 子项''',
    ),
    _FormatExample(
      label: 'Markdown 表格',
      content: '''| 名称 | 数量 | 价格 |
|------|------|------|
| 苹果 | 10 | \$5 |
| 香蕉 | 5 | \$3 |''',
    ),
    _FormatExample(
      label: 'Markdown 引用块',
      content: '''> 这是一段引用文本
> 可以用来引用他人说的话''',
    ),
    _FormatExample(
      label: 'Markdown 混合格式',
      content: '''**标题**: 混合格式示例

1. 首先，创建一个 `变量`
2. 然后调用 `print()` 输出

> 注意: 这是一个重要提示''',
    ),
    _FormatExample(
      label: 'HTML 格式',
      content: '''<p>这是 <strong>粗体</strong> 和 <em>斜体</em></p>

<ul>
  <li>列表项 1</li>
  <li>列表项 2</li>
</ul>

<blockquote>引用块</blockquote>

<code>行内代码</code>''',
      useHtml: true,
    ),
  ];

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

  void _handleSend(String content) async {
    if (content.trim().isEmpty) return;

    // 添加用户消息
    setState(() {
      _messages.add(_FormatMessage(
        content: content,
        isMe: true,
      ));
    });

    _inputController.clear();
    await _scrollToBottom();

    // 模拟 AI 响应（循环展示不同格式）
    await Future.delayed(const Duration(milliseconds: 500));
    final example = _examples[_responseIndex % _examples.length];
    _responseIndex++;

    setState(() {
      _messages.add(_FormatMessage(
        content: example.content,
        isMe: false,
        label: example.label,
        useHtml: example.useHtml,
      ));
    });

    await _scrollToBottom();
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
                    '格式渲染演示',
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
                _responseIndex = 0;
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
              '输入文本，查看不同格式的渲染效果',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Text(
              '快捷示例：',
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
                  text: 'Markdown 粗体',
                  onTap: () => _handleSend('**粗体文本**'),
                ),
                _QuickReply(
                  text: 'Markdown 列表',
                  onTap: () => _handleSend('1. 第一项\n2. 第二项'),
                ),
                _QuickReply(
                  text: 'HTML 格式',
                  onTap: () => _handleSend('<strong>粗体</strong> 和 <em>斜体</em>'),
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
                  hintText: '输入文本测试格式...',
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

class _FormatMessage {
  final String content;
  final bool isMe;
  final String? label;
  final bool useHtml;

  _FormatMessage({
    required this.content,
    required this.isMe,
    this.label,
    this.useHtml = false,
  });
}

class _FormatExample {
  final String label;
  final String content;
  final bool useHtml;

  _FormatExample({
    required this.label,
    required this.content,
    this.useHtml = false,
  });
}

class _FormatMessageBubble extends StatelessWidget {
  final _FormatMessage message;
  final bool isMe;

  const _FormatMessageBubble({
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
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (message.label != null)
              Container(
                margin: const EdgeInsets.only(left: 12, bottom: 4),
                child: Text(
                  message.label!,
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
                      message.content,
                      style: TextStyle(
                        color: isMe ? Colors.white : theme.colorScheme.onSurface,
                      ),
                    )
                  : message.useHtml
                      ? HtmlRendererWidget(data: message.content)
                      : MarkdownRendererWidget(data: message.content),
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
