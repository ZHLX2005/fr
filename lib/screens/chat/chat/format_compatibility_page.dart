import 'package:flutter/material.dart';
import '../../../widgets/markdown_renderer_widget.dart';
import '../../../widgets/html_renderer_widget.dart';

/// 格式兼容性测试页面
/// 展示 Markdown 和 HTML 渲染器 Widget 的效果
class FormatCompatibilityPage extends StatelessWidget {
  const FormatCompatibilityPage({super.key});

  static const String _markdownSample = '''
# 标题一
## 标题二
### 标题三

**这是粗体文本** 和 *这是斜体文本*

~~这是删除线文本~~

- 无序列表项 1
- 无序列表项 2
  - 子项 2.1
  - 子项 2.2

1. 有序列表项
2. 有序列表项
3. 有序列表项

> 这是引用块
> 可以引用他人说的话

[这是一个链接](https://example.com)

`行内代码` 展示

```
代码块
function hello() {
  print("Hello");
}
```

| 表格 | 列1 | 列2 |
|------|-----|-----|
| 行1  | A   | B   |
| 行2  | C   | D   |
''';

  static const String _htmlSample = '''
<h1>HTML 标题一</h1>
<h2>HTML 标题二</h2>
<h3>HTML 标题三</h3>

<p>这是 <strong>粗体文本</strong> 和 <em>斜体文本</em></p>

<p>~~删除线~~ <del>删除线替代</del></p>

<ul>
  <li>无序列表项 1</li>
  <li>无序列表项 2
    <ul>
      <li>子项 2.1</li>
      <li>子项 2.2</li>
    </ul>
  </li>
</ul>

<ol>
  <li>有序列表项</li>
  <li>有序列表项</li>
  <li>有序列表项</li>
</ol>

<blockquote>
  这是引用块<br>
  可以引用他人说的话
</blockquote>

<p><a href="https://example.com">这是一个链接</a></p>

<p><code>行内代码</code> 展示</p>

<pre><code>代码块
function hello() {
  print("Hello");
}</code></pre>

<table>
  <tr><th>表格</th><th>列1</th><th>列2</th></tr>
  <tr><td>行1</td><td>A</td><td>B</td></tr>
  <tr><td>行2</td><td>C</td><td>D</td></tr>
</table>
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('格式兼容性测试'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showFormatInfo(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionTitle(
              title: 'Markdown 渲染器 Widget',
              subtitle: '使用 flutter_markdown',
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            _WidgetDemoCard(
              title: 'Markdown 输入/回复框',
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: SingleChildScrollView(
                  child: MarkdownRendererWidget(data: _markdownSample),
                ),
              ),
            ),
            const SizedBox(height: 32),

            _SectionTitle(
              title: 'HTML 渲染器 Widget',
              subtitle: '使用 flutter_widget_from_html',
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 12),
            _WidgetDemoCard(
              title: 'HTML 输入/回复框',
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: SingleChildScrollView(
                  child: HtmlRendererWidget(data: _htmlSample),
                ),
              ),
            ),
            const SizedBox(height: 32),

            _SectionTitle(
              title: '对比展示',
              subtitle: '同一内容两种格式对比',
              color: Theme.of(context).colorScheme.tertiary,
            ),
            const SizedBox(height: 12),
            _CompareSection(markdownSample: _markdownSample, htmlSample: _htmlSample),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  void _showFormatInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('支持的 Widget'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MarkdownRendererWidget:'),
            SizedBox(height: 4),
            Text('• flutter_markdown 实现'),
            Text('• 支持粗体、斜体、删除线'),
            Text('• 支持代码块、列表、表格'),
            Text('• 支持链接、引用块'),
            SizedBox(height: 12),
            Text('HtmlRendererWidget:'),
            SizedBox(height: 4),
            Text('• flutter_widget_from_html 实现'),
            Text('• 支持大部分 HTML 标签'),
            Text('• 支持内联样式'),
            Text('• 支持链接点击回调'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      ],
    );
  }
}

class _WidgetDemoCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _WidgetDemoCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.input,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _CompareSection extends StatelessWidget {
  final String markdownSample;
  final String htmlSample;

  const _CompareSection({required this.markdownSample, required this.htmlSample});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _WidgetDemoCard(
            title: 'Markdown 格式',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: MarkdownRendererWidget(data: markdownSample),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _WidgetDemoCard(
            title: 'HTML 格式',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: HtmlRendererWidget(data: htmlSample),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
