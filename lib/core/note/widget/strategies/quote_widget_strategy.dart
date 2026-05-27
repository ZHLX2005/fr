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
  Widget buildEditor(Block block, BlockCallbacks callbacks, {required Widget textField}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          margin: const EdgeInsets.only(right: 8),
          color: Colors.grey[400],
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
        Container(
          width: 3,
          margin: const EdgeInsets.only(right: 8),
          color: Colors.grey[400],
        ),
        Expanded(
          child: Text(
            block.content.toPlainText(),
            style: TextStyle(
              color: Colors.grey[700],
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}
