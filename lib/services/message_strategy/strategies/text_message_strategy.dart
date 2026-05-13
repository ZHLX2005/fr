import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/text_message_data.dart';

/// Strategy for rendering plain text messages
class TextMessageWidgetStrategy extends MessageWidgetStrategy<TextMessageData> {
  // Static const cache for identical text
  static final _cache = <String, Text>{};

  @override
  Widget build(BuildContext context, TextMessageData data) {
    // Use cached const Text widget if available
    return _cache.putIfAbsent(
      data.text,
      () => Text(data.text),
    );
  }

  @override
  TextMessageData createMockData() => TextMessageData('这是一条普通的纯文本消息，直接显示内容。');
}
