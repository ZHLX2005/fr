import 'package:flutter/material.dart';
import '../../core/type/type.dart';
import '../../core/models/block.dart';
import '../block_widget_strategy.dart';

class HeadingWidgetStrategy extends BlockWidgetStrategy {
  @override
  Widget build(Block block, BlockCallbacks callbacks) {
    final level = (block.type as HeadingType).level;
    final text = block.content.toPlainText();
    final sizes = [28.0, 22.0, 18.0, 16.0, 14.0, 13.0];
    return Text(
      text,
      style: TextStyle(
        fontSize: sizes[level.clamp(1, 6) - 1],
        fontWeight: FontWeight.bold,
        height: 1.3,
      ),
    );
  }
}
