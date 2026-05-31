import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_type_info.dart';
import '../block_widget_strategy.dart';

class QuoteWidgetStrategy extends BlockWidgetStrategy {
  @override
  List<BlockTypeInfo> get typeInfoList => const [
    BlockTypeInfo(prototype: QuoteType(), icon: Icons.format_quote, label: '"', category: BlockTypeCategory.text),
  ];

  @override
  Widget buildEditor(BuildContext context, Block block, BlockCallbacks callbacks, {required Widget textField}) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
        ),
      ),
      padding: const EdgeInsets.only(left: 8),
      child: textField,
    );
  }

  @override
  Widget build(BuildContext context, Block block, BlockCallbacks callbacks) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
        ),
      ),
      padding: const EdgeInsets.only(left: 8),
      child: Text(block.content.toPlainText()),
    );
  }
}
