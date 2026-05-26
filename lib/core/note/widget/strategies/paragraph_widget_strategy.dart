import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_widget_strategy.dart';

class ParagraphWidgetStrategy extends BlockWidgetStrategy {
  @override
  Widget build(Block block, BlockCallbacks callbacks) {
    return Text(block.content.toPlainText());
  }
}
