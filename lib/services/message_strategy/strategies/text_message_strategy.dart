import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/text_message_data.dart';

/// Strategy for rendering plain text messages
class TextMessageWidgetStrategy extends MessageWidgetStrategy<TextMessageData> {
  @override
  String get type => 'text';

  @override
  Widget build(BuildContext context, TextMessageData data) {
    return Text(data.text);
  }
}
