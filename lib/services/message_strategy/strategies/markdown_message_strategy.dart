import 'package:flutter/material.dart';
import '../../../widgets/markdown_renderer_widget.dart';
import '../interfaces/interfaces.dart';
import '../data/markdown_message_data.dart';

/// Strategy for rendering Markdown messages
class MarkdownMessageWidgetStrategy extends MessageWidgetStrategy<MarkdownMessageData> {
  @override
  String get type => 'markdown';

  @override
  Widget build(BuildContext context, MarkdownMessageData data) {
    return MarkdownRendererWidget(data: data.content);
  }

  @override
  MarkdownMessageData createMockData() => MarkdownMessageData('''**粗体文本** 和 *斜体文本*

~~删除线~~

```dart
void main() {
  print("Hello");
}
```''');
}
