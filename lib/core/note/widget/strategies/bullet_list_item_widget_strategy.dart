import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_type_info.dart';
import '../block_widget_strategy.dart';

class BulletListItemWidgetStrategy extends BlockWidgetStrategy {
  @override
  List<BlockTypeInfo> get typeInfoList => const [
    BlockTypeInfo(prototype: BulletListItemType(), icon: Icons.format_list_bulleted, label: '•', category: BlockTypeCategory.list),
  ];

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
