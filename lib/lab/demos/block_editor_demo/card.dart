import 'package:flutter/material.dart';
import '../../../core/note/core/block.dart';
import '../../../core/note/core/block_type.dart';
import 'state.dart';
import 'renderer.dart';

class BlockCard extends StatefulWidget {
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
                  : renderBlockContent(
                      widget.block,
                      onToggleTodo: () => widget.editorState.toggleTodo(widget.block.id),
                    ),
            ),
          ),
          if (widget.isSelected) ...[
            IconButton(
              icon: Icon(Icons.close, size: 16, color: Colors.grey[400]),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () => widget.editorState.deleteBlock(),
              tooltip: '删除块',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField() {
    return TextField(
      controller: _controller,
      maxLines: null,
      style: textStyleForType(widget.block) ?? const TextStyle(fontSize: 14),
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: (value) => widget.editorState.updateContent(widget.block.id, value),
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
