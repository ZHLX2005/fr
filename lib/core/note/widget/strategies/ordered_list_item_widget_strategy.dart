import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_type_info.dart';
import '../block_widget_strategy.dart';

class OrderedListItemWidgetStrategy extends BlockWidgetStrategy {
  @override
  List<BlockTypeInfo> get typeInfoList => const [
    BlockTypeInfo(prototype: OrderedListItemType(), icon: Icons.format_list_numbered, label: '1.', category: BlockTypeCategory.list),
  ];

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
