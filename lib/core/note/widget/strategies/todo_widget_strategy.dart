import 'package:flutter/material.dart';
import '../../core/core.dart';
import '../block_type_info.dart';
import '../block_widget_strategy.dart';

class TodoWidgetStrategy extends BlockWidgetStrategy {
  @override
  List<BlockTypeInfo> get typeInfoList => const [
    BlockTypeInfo(prototype: TodoType(), icon: Icons.check_box_outline_blank, label: '☐', category: BlockTypeCategory.list),
  ];

  @override
  Widget buildEditor(BuildContext context, Block block, BlockCallbacks callbacks, {required Widget textField}) {
    final checked = (block.type as TodoType).checked;
    final theme = Theme.of(context);
    return Row(
      children: [
        GestureDetector(
          onTap: callbacks.onToggleTodo,
          child: Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: checked ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: textField),
      ],
    );
  }

  @override
  Widget build(BuildContext context, Block block, BlockCallbacks callbacks) {
    final checked = (block.type as TodoType).checked;
    final text = block.content.toPlainText();
    final theme = Theme.of(context);
    return Row(
      children: [
        GestureDetector(
          onTap: callbacks.onToggleTodo,
          child: Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: checked ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              decoration: checked ? TextDecoration.lineThrough : null,
              color: checked ? theme.colorScheme.onSurfaceVariant : null,
            ),
          ),
        ),
      ],
    );
  }
}
