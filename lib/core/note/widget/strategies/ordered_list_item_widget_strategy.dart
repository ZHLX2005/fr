import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_widget_strategy.dart';

class OrderedListItemWidgetStrategy extends BlockWidgetStrategy {
  @override
  Widget build(Block block, BlockCallbacks callbacks) {
    final number = (block.type as OrderedListItemType).number;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$number. ',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Expanded(child: Text(block.content.toPlainText())),
      ],
    );
  }
}
