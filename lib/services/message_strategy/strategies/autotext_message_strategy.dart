import 'package:flutter/material.dart';
import '../../../widgets/markdown_renderer_widget.dart';
import '../interfaces/interfaces.dart';
import '../data/autotext_message_data.dart';

/// Strategy for rendering auto-text messages (plain text + automatic markdown)
class AutoTextMessageWidgetStrategy
    extends MessageWidgetStrategy<AutoTextMessageData> {
  @override
  Widget build(BuildContext context, AutoTextMessageData data) {
    return MarkdownRendererWidget(data: data.content);
  }

  @override
  AutoTextMessageData createMockData() => AutoTextMessageData(
    '这是 **autotext** 消息：纯文本内容自动按 Markdown 渲染。\n\n- 支持**粗体**与*斜体*\n- 支持 `行内代码`\n- 支持列表、引用与代码块',
  );
}
