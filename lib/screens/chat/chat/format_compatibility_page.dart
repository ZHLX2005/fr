import 'package:flutter/material.dart';
import '../../../widgets/markdown_renderer_widget.dart';
import '../../../widgets/html_renderer_widget.dart';

/// 格式兼容性测试页面
/// 展示各种消息格式的渲染效果，布局与 AgentChatPage 相同
class FormatCompatibilityPage extends StatelessWidget {
  const FormatCompatibilityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            CircleAvatar(
              radius: 16,
              child: Icon(Icons.format_align_left, size: 18),
            ),
            SizedBox(width: 8),
            Text('Format 测试'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: const [
                _FormatMessageBubble(
                  label: '纯文本',
                  content: '这是一条普通的纯文本消息，直接显示内容。',
                ),
                _FormatMessageBubble(
                  label: 'Markdown 粗体/斜体',
                  content: '**粗体文本** 和 *斜体文本*\n\n~~删除线~~',
                ),
                _FormatMessageBubble(
                  label: 'Markdown 代码块',
                  content: '''```dart
void main() {
  print("Hello");
}
```''',
                ),
                _FormatMessageBubble(
                  label: 'Markdown 列表',
                  content: '''1. 第一步操作
2. 第二步操作
3. 第三步操作

- 无序列表项
- 子项''',
                ),
                _FormatMessageBubble(
                  label: 'Markdown 表格',
                  content: '''| 名称 | 数量 | 价格 |
|------|------|------|
| 苹果 | 10 | \$5 |
| 香蕉 | 5 | \$3 |''',
                ),
                _FormatMessageBubble(
                  label: 'Markdown 引用块',
                  content: '''> 这是一段引用文本
> 可以用来引用他人说的话''',
                ),
                _FormatMessageBubble(
                  label: 'Markdown 混合格式',
                  content: '''**标题**: 混合格式示例

1. 首先，创建一个 `变量`
2. 然后调用 `print()` 输出

> 注意: 这是一个重要提示''',
                ),
                _FormatMessageBubble(
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
                _FormatMessageBubble(
                  label: '错误消息',
                  content: '❌ 发生错误: 无法连接到服务器',
                  isError: true,
                ),
                SizedBox(height: 80),
              ],
            ),
          ),
          _buildHintBar(),
        ],
      ),
    );
  }

  Widget _buildHintBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey[100],
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.grey),
          SizedBox(width: 8),
          Text(
            '以上为各种格式的渲染效果展示',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _FormatMessageBubble extends StatelessWidget {
  final String label;
  final String content;
  final bool useHtml;
  final bool isError;

  const _FormatMessageBubble({
    required this.label,
    required this.content,
    this.useHtml = false,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(left: 12, bottom: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.95,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isError
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.zero,
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: isError
                  ? Text(
                      content,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    )
                  : useHtml
                      ? HtmlRendererWidget(data: content)
                      : MarkdownRendererWidget(data: content),
            ),
          ),
        ],
      ),
    );
  }
}
