import 'package:flutter/material.dart';
import '../../../core/note/core/core.dart';
import '../../../services/media_service.dart';
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
    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
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
              child: widget.isSelected && !widget.block.type.containerOnly && widget.block.type is! ImageType
                  ? _buildTextField()
                  : renderBlockContent(
                      widget.block,
                      onToggleTodo: () => widget.editorState.toggleTodo(widget.block.id),
                      onTapAddImage: widget.block.type is ImageType
                          ? () => _showAddImageDialog()
                          : null,
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

  Future<void> _showAddImageDialog() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('输入 URL'),
              onTap: () => Navigator.pop(ctx, 'url'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    switch (result) {
      case 'gallery':
        final path = await MediaService.pickImageFromGallery();
        if (path != null) {
          widget.editorState.updateImageSrc(widget.block.id, path);
        }
      case 'camera':
        final path = await MediaService.takePicture();
        if (path != null) {
          widget.editorState.updateImageSrc(widget.block.id, path);
        }
      case 'url':
        _showUrlDialog();
    }
  }

  Future<void> _showUrlDialog() async {
    final controller = TextEditingController(
      text: (widget.block.type as ImageType).src,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入图片 URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      widget.editorState.updateImageSrc(widget.block.id, result);
    }
  }

  IconData _typeIcon(BlockType type) {
    return switch (type) {
      HeadingType() => Icons.title,
      TodoType() => Icons.check_box_outline_blank,
      BulletListItemType() => Icons.format_list_bulleted,
      OrderedListItemType() => Icons.format_list_numbered,
      QuoteType() => Icons.format_quote,
      CodeType() => Icons.code,
      DividerType() => Icons.horizontal_rule,
      CalloutType() => Icons.info_outline,
      _ => Icons.text_fields,
    };
  }
}
