import 'package:flutter/material.dart';
import '../../core/type/type.dart';
import '../../core/models/block.dart';
import '../block_widget_strategy.dart';

class BulletListItemWidgetStrategy extends BlockWidgetStrategy {
  @override
  Widget build(Block block, BlockCallbacks callbacks) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ', style: TextStyle(fontSize: 16)),
        Expanded(child: Text(block.content.toPlainText())),
      ],
    );
  }
}
