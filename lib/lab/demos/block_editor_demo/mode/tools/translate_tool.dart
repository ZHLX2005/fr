import 'package:flutter/material.dart';
import 'chat_tool.dart';

class TranslateTool extends ChatTool {
  @override
  String get id => 'translate';

  @override
  String get label => '翻译';

  @override
  IconData get icon => Icons.translate;

  @override
  String? get description => '将内容翻译为中文';
}
