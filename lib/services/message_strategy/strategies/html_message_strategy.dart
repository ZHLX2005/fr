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
  HtmlMessageData createMockData() => HtmlMessageData('''<p>这是 <strong>粗体</strong> 和 <em>斜体</em></p>

<ul>
  <li>列表项 1</li>
  <li>列表项 2</li>
</ul>

<blockquote>引用块</blockquote>

<code>行内代码</code>''');
}
