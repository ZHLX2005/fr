import 'package:flutter/material.dart';
import '../../../widgets/html_renderer_widget.dart';
import '../interfaces/interfaces.dart';
import '../data/html_message_data.dart';

/// Strategy for rendering HTML messages
class HtmlMessageWidgetStrategy extends MessageWidgetStrategy<HtmlMessageData> {
  @override
  String get type => 'html';

  @override
  Widget build(BuildContext context, HtmlMessageData data) {
    return HtmlRendererWidget(data: data.content);
  }
}
