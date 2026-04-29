import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/text_message_data.dart';

/// Strategy for rendering plain text messages
class TextMessageWidgetStrategy extends MessageWidgetStrategy<TextMessageData> {
  @override
  Widget build(BuildContext context, TextMessageData data) {
    return Text(data.text);
  }

  @override
  TextMessageData createMockData() => TextMessageData('这是一条普通的纯文本消息，直接显示内容。');
}
