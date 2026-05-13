import 'package:flutter/material.dart';
import '../../../widgets/markdown_renderer_widget.dart';
import '../interfaces/interfaces.dart';
import '../data/markdown_message_data.dart';

/// Strategy for rendering Markdown messages
class MarkdownMessageWidgetStrategy extends MessageWidgetStrategy<MarkdownMessageData> {
  @override
  Widget build(BuildContext context, MarkdownMessageData data) {
    return MarkdownRendererWidget(data: data.content);
  }

  @override
  MarkdownMessageData createMockData() => MarkdownMessageData('''# Markdown 测试数据

这是一个**完整的 Markdown 示例**，包含多种格式：

## 文本格式

- **粗体文字** 用于强调
- *斜体文字* 用于轻量强调
- ~~删除线~~ 用于标记过时内容
- `行内代码` 用于代码片段

## 代码块

```dart
class MarkdownMessageData implements IMessageData {
  final String content;

  MarkdownMessageData(this.content);

  @override
  String get type => 'markdown';

  void render() {
    print('Hello Markdown!');
  }
}
```

## 列表

1. 第一项
2. 第二项
3. 第三项

- 无序列表项 A
- 无序列表项 B
- 无序列表项 C

## 引用

> 这是一段引用文本
> 可以跨越多行
> 通常用于引用他人言论

## 链接

[Flutter 官网](https://flutter.dev)

---

*测试数据结束*''');
}
