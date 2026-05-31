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
  Widget buildEditor(BuildContext context, Block block, BlockCallbacks callbacks, {required Widget textField}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('• ',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Expanded(child: textField),
      ],
    );
  }

  @override
  Widget build(BuildContext context, Block block, BlockCallbacks callbacks) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• ',
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Expanded(
          child: Text(
            block.content.toPlainText(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
          ),
        ),
      ],
    );
  }
}
