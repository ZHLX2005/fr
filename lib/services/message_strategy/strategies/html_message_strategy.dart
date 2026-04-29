import 'package:flutter/material.dart';
import '../../../widgets/html_renderer_widget.dart';
import '../interfaces/interfaces.dart';
import '../data/html_message_data.dart';

/// Strategy for rendering HTML messages
class HtmlMessageWidgetStrategy extends MessageWidgetStrategy<HtmlMessageData> {
  @override
  Widget build(BuildContext context, HtmlMessageData data) {
    return HtmlRendererWidget(data: data.content);
  }

  @override
  HtmlMessageData createMockData() => HtmlMessageData('''<h1>HTML 测试数据</h1>

<p>这是一个<strong>完整的 HTML 示例</strong>，包含多种标签：</p>

<h2>文本格式</h2>

<ul>
  <li><b>粗体文字</b> - 用于强调</li>
  <li><i>斜体文字</i> - 用于轻量强调</li>
  <li><u>下划线文字</u> - 用于标记</li>
  <li><s>删除线</s> - 用于标记过时内容</li>
  <li><code>行内代码</code> - 用于代码片段</li>
</ul>

<h2>代码块</h2>

<pre><code class="language-dart">class HtmlMessageData implements IMessageData {
  final String content;

  HtmlMessageData(this.content);

  @override
  String get type => 'html';

  void render() {
    print('Hello HTML!');
  }
}</code></pre>

<h2>表格</h2>

<table border="1">
  <tr><th>名称</th><th>类型</th></tr>
  <tr><td>文本</td><td>text</td></tr>
  <tr><td>Markdown</td><td>markdown</td></tr>
  <tr><td>HTML</td><td>html</td></tr>
</table>

<h2>引用块</h2>

<blockquote>
  这是一段引用文本<br>
  可以跨越多行<br>
  通常用于引用他人言论
</blockquote>

<h2>链接</h2>

<p><a href="https://flutter.dev">Flutter 官网</a></p>

<hr>

<p><i>测试数据结束</i></p>''');
}
