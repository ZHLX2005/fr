import 'package:flutter/material.dart';
import 'chat_tool.dart';

class ExplainTool extends ChatTool {
  @override
  String get id => 'explain';

  @override
  String get label => '解释';

  @override
  IconData get icon => Icons.psychology;

  @override
  String? get description => '解释概念或术语';
}
