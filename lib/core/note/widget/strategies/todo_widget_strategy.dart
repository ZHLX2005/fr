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
  Widget build(Block block, BlockCallbacks callbacks) {
    final checked = (block.type as TodoType).checked;
    final text = block.content.toPlainText();
    return Row(
      children: [
        GestureDetector(
          onTap: callbacks.onToggleTodo,
          child: Icon(
            checked ? Icons.check_box : Icons.check_box_outline_blank,
            size: 18,
            color: checked ? Colors.blue : Colors.grey,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              decoration: checked ? TextDecoration.lineThrough : null,
              color: checked ? Colors.grey : null,
            ),
          ),
        ),
      ],
    );
  }
}
