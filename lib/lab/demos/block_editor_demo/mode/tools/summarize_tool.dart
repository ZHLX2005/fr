import 'package:flutter/material.dart';
import 'chat_tool.dart';

class SummarizeTool extends ChatTool {
  @override
  String get id => 'summarize';

  @override
  String get label => '总结';

  @override
  IconData get icon => Icons.summarize;

  @override
  String? get description => '生成内容总结';
}
