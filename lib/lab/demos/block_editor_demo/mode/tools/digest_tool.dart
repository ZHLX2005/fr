import 'package:flutter/material.dart';
import 'chat_tool.dart';

class DigestTool extends ChatTool {
  @override
  String get id => 'digest';

  @override
  String get label => '摘要';

  @override
  IconData get icon => Icons.article;

  @override
  String? get description => '提取关键信息';
}
