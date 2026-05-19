import 'package:flutter/material.dart';
import '../../../core/note/core/block.dart';
import '../../../core/note/core/block_type.dart';
import 'state.dart';
import 'renderer.dart';

class BlockCard extends StatelessWidget {
  final Block block;
  final bool isSelected;
  final EditorState editorState;

  const BlockCard({
    super.key,
    required this.block,
    required this.isSelected,
    required this.editorState,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => editorState.select(block.id),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(4),
          border: isSelected
              ? Border.all(color: Colors.blue.withValues(alpha: 0.3))
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Icon(_typeIcon(block.type), size: 14, color: Colors.grey[400]),
            ),
            Expanded(child: renderBlockContent(block)),
            if (isSelected) ...[
              _typeDropdown(context),
              const SizedBox(width: 4),
              _deleteButton(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typeDropdown(BuildContext context) {
    return PopupMenuButton<BlockType>(
      tooltip: '切换类型',
      icon: Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[500]),
      onSelected: (type) => editorState.toggleType(type),
      itemBuilder: (_) => const [
        PopupMenuItem(value: BlockType.paragraph, child: Text('段落')),
        PopupMenuItem(value: BlockType.heading, child: Text('标题')),
        PopupMenuItem(value: BlockType.todo, child: Text('待办')),
        PopupMenuItem(value: BlockType.bulletListItem, child: Text('无序列表')),
        PopupMenuItem(value: BlockType.orderedListItem, child: Text('有序列表')),
        PopupMenuItem(value: BlockType.quote, child: Text('引用')),
        PopupMenuItem(value: BlockType.code, child: Text('代码')),
        PopupMenuItem(value: BlockType.callout, child: Text('提示框')),
        PopupMenuItem(value: BlockType.divider, child: Text('分割线')),
      ],
    );
  }

  Widget _deleteButton(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.close, size: 16, color: Colors.grey[400]),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      onPressed: () => editorState.deleteBlock(),
      tooltip: '删除块',
    );
  }

  IconData _typeIcon(BlockType type) {
    return switch (type) {
      BlockType.heading => Icons.title,
      BlockType.todo => Icons.check_box_outline_blank,
      BlockType.bulletListItem => Icons.format_list_bulleted,
      BlockType.orderedListItem => Icons.format_list_numbered,
      BlockType.quote => Icons.format_quote,
      BlockType.code => Icons.code,
      BlockType.divider => Icons.horizontal_rule,
      BlockType.callout => Icons.info_outline,
      _ => Icons.text_fields,
    };
  }
}
