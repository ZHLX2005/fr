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
  Widget buildEditor(Block block, BlockCallbacks callbacks, {required Widget textField}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Text('• ', style: TextStyle(fontSize: 16)),
        ),
        Expanded(child: textField),
      ],
    );
  }

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
