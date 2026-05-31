import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_type_info.dart';
import '../block_widget_strategy.dart';

class CodeWidgetStrategy extends BlockWidgetStrategy {
  @override
  List<BlockTypeInfo> get typeInfoList => const [
    BlockTypeInfo(prototype: CodeType(), icon: Icons.code, label: '<>', category: BlockTypeCategory.text),
  ];

  @override
  Widget buildEditor(BuildContext context, Block block, BlockCallbacks callbacks, {required Widget textField}) {
    final lang = (block.type as CodeType).language;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lang.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                lang,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          textField,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, Block block, BlockCallbacks callbacks) {
    final lang = (block.type as CodeType).language;
    final text = block.content.toPlainText();
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lang.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                lang,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
