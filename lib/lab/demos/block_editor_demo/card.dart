import 'package:flutter/material.dart';
import '../../../core/note/core/block.dart';
import '../../../core/note/core/block_type.dart';
import 'state.dart';
import 'renderer.dart';

class BlockCard extends StatefulWidget {
  final Block block;
  final int index;
  final bool isSelected;
  final EditorState editorState;

  const BlockCard({
    super.key,
    required this.block,
    required this.index,
    required this.isSelected,
    required this.editorState,
  });

  @override
  State<BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends State<BlockCard> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.content.toPlainText());
  }

  @override
  void didUpdateWidget(BlockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.id != widget.block.id) {
      // 选中的 block 切换了，直接替换
      _controller.text = widget.block.content.toPlainText();
    } else {
      // 同一 block，检查外部是否有变更
      final newText = widget.block.content.toPlainText();
      if (newText != _controller.text) {
        _controller.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: widget.isSelected ? Colors.blue.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(4),
        border: widget.isSelected
            ? Border.all(color: Colors.blue.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 2),
              child: Icon(Icons.drag_handle, size: 16, color: Colors.grey[400]),
            ),
          ),
          GestureDetector(
            onTap: () => widget.editorState.select(widget.block.id),
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 4),
              child: Icon(_typeIcon(widget.block.type), size: 14, color: Colors.grey[400]),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => widget.editorState.select(widget.block.id),
              child: widget.isSelected && !widget.block.type.containerOnly
                  ? _buildTextField()
                  : renderBlockContent(widget.block),
            ),
          ),
          if (widget.isSelected) ...[
            _typeDropdown(context),
            const SizedBox(width: 4),
            _deleteButton(context),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField() {
    return TextField(
      controller: _controller,
      style: textStyleForType(widget.block) ?? const TextStyle(fontSize: 14),
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: (value) => widget.editorState.updateContent(widget.block.id, value),
    );
  }

  Widget _typeDropdown(BuildContext context) {
    return PopupMenuButton<BlockType>(
      tooltip: '切换类型',
      icon: Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[500]),
      onSelected: (type) => widget.editorState.toggleType(type),
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
      onPressed: () => widget.editorState.deleteBlock(),
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
