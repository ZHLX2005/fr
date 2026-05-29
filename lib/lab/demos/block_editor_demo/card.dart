import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import '../../../core/note/note_root_scope.dart';
import '../../../services/media_service.dart';
import 'state.dart';
import 'message_dialog.dart';

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
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.content.toPlainText());
    _focusNode = FocusNode();
    if (widget.isSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(BlockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.id != widget.block.id) {
      _controller.text = widget.block.content.toPlainText();
    } else {
      final newText = widget.block.content.toPlainText();
      if (newText != _controller.text) {
        _controller.text = newText;
      }
    }
    if (!oldWidget.isSelected && widget.isSelected) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
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
          Expanded(
            child: GestureDetector(
              onTap: () => widget.editorState.select(widget.block.id),
              child: widget.isSelected && !widget.block.type.containerOnly && widget.block.type is! ImageType
                  ? _buildTextField()
                  : NoteRootScope.of(context).noteRoot.renderBlock(
                      widget.block,
                      onToggleTodo: () => widget.editorState.toggleTodo(widget.block.id),
                      onTapAddImage: widget.block.type is ImageType
                          ? () => _showAddImageDialog()
                          : null,
                    ),
            ),
          ),
          // 选中态指示器（占位保持布局对齐）
          if (widget.isSelected) const SizedBox(width: 24),
        ],
      ),
    ),
    );
  }

  Widget _buildTextField() {
    final ml = widget.block.type.multiline;
    final textField = Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace && _controller.text.isEmpty) {
          widget.editorState.deleteBlock();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !ml) {
          final newType = widget.block.type.onEnterType;
          if (newType != null) {
            widget.editorState.addBlockWithType(newType);
          }
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space && _controller.text.isEmpty) {
          _showMessageDialog();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        focusNode: _focusNode,
        controller: _controller,
        maxLines: ml ? null : 1,
        style: NoteRootScope.of(context).noteRoot.textStyleFor(widget.block) ?? const TextStyle(fontSize: 14),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        textInputAction: TextInputAction.newline,
        contextMenuBuilder: _buildContextMenu,
        onChanged: (value) {
          if (!ml && value.endsWith('\n')) {
            widget.editorState.updateContent(widget.block.id, value.trimRight());
            final newType = widget.block.type.onEnterType;
            if (newType != null) {
              widget.editorState.addBlockWithType(newType);
            }
            return;
          }
          // 软键盘按空格（空白 block 触发对话框）
          if (value.length == 1 && (value == ' ' || value == ' ')) {
            _controller.text = '';
            _showMessageDialog();
            return;
          }
          widget.editorState.updateContent(widget.block.id, value);
        },
      ),
    );
    return NoteRootScope.of(context).noteRoot.buildEditor(
      widget.block,
      textField: textField,
      onToggleTodo: () => widget.editorState.toggleTodo(widget.block.id),
    );
  }

  Future<void> _showMessageDialog({Map<String, dynamic>? quoteData}) async {
    final noteRoot = NoteRootScope.of(context).noteRoot;
    await MessageDialog.show(
      context,
      serializedBlock: noteRoot.serializeBlock(widget.block),
      quoteData: quoteData,
    );
  }

  Widget _buildContextMenu(BuildContext context, EditableTextState editableTextState) {
    final items = List<ContextMenuButtonItem>.from(
      editableTextState.contextMenuButtonItems,
    );
    final value = editableTextState.textEditingValue;
    if (value.selection.isValid && !value.selection.isCollapsed) {
      items.add(ContextMenuButtonItem(
        label: '引用',
        onPressed: () {
          final selectedText = value.text.substring(
            value.selection.start,
            value.selection.end,
          );
          final noteRoot = NoteRootScope.of(context).noteRoot;
          final quotedBlock = noteRoot.createBlock(
            const ParagraphType(),
            content: RichText.text(selectedText),
            properties: {'originalBlockId': widget.block.id},
          );
          _showMessageDialog(quoteData: noteRoot.serializeBlock(quotedBlock));
        },
      ));
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
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

}
