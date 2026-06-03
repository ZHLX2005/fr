import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import '../../../core/note/note_root_scope.dart';
import '../../../services/media_service.dart';
import 'state.dart';


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
  bool _pendingRefresh = false;

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
      // 不同 block → 全量替换
      _controller.text = widget.block.content.toPlainText();
    } else if (!_focusNode.hasFocus) {
      // 同一 block 但不是正在编辑 → 安全同步 controller
      final newText = widget.block.content.toPlainText();
      if (newText != _controller.text) {
        _controller.text = newText;
      }
    }
    // 正在编辑时（hasFocus）不碰 controller，由 onChanged 全权管理

    if (!oldWidget.isSelected && widget.isSelected) {
      // 延迟到 build 完成后再聚焦，确保 TextField 已挂载
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNode.requestFocus();
        // 焦点就绪后再通知平台弹出键盘
        _focusNode.addListener(_onFocusChangeToShowKeyboard);
      });
    }
  }

  /// 当 FocusNode 获得焦点后，通知平台弹出软键盘。
  void _onFocusChangeToShowKeyboard() {
    if (_focusNode.hasFocus) {
      _focusNode.removeListener(_onFocusChangeToShowKeyboard);
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
  }

  /// 安排一帧后刷新 UI（通知 toolbar 等）。
  /// 用 _pendingRefresh 防止同一帧内多次调度。
  void _scheduleRefresh() {
    if (_pendingRefresh) return;
    _pendingRefresh = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingRefresh = false;
      if (mounted) widget.editorState.refresh();
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChangeToShowKeyboard);
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
                      context,
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
          widget.editorState.deleteBlock(silent: true);
          _scheduleRefresh();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !ml) {
          final newType = widget.block.type.onEnterType;
          if (newType != null) {
            widget.editorState.addBlockWithType(newType, silent: true);
          }
          _scheduleRefresh();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space && _controller.text.isEmpty) {
          widget.editorState.switchToChat();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        focusNode: _focusNode,
        controller: _controller,
        maxLines: ml ? null : 1,
        style: NoteRootScope.of(context).noteRoot.textStyleFor(widget.block, context) ?? const TextStyle(fontSize: 14),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        textInputAction: TextInputAction.newline,
        contextMenuBuilder: _buildContextMenu,
        onChanged: (value) {
          if (!ml && value.endsWith('\n')) {
            widget.editorState.updateContent(widget.block.id, value.trimRight(), silent: true);
            final newType = widget.block.type.onEnterType;
            if (newType != null) {
              widget.editorState.addBlockWithType(newType, silent: true);
            }
            _syncControllerFromState();
            _scheduleRefresh();
            return;
          }
          // 软键盘按空格（空白 block 触发对话框）
          if (value.length == 1 && (value == ' ' || value == ' ')) {
            _controller.text = '';
            widget.editorState.switchToChat();
            return;
          }
          // 静默更新状态（数据已保存到磁盘，但不触发 notifyListeners）
          widget.editorState.updateContent(widget.block.id, value, silent: true);
          // 如果发生了类型转换，controller 需要同步转换后的内容
          _syncControllerFromState();
          // 延迟到下一帧再刷新 UI（toolbar 等），不打断当前输入连接
          _scheduleRefresh();
        },
      ),
    );
    return NoteRootScope.of(context).noteRoot.buildEditor(
      context,
      widget.block,
      textField: textField,
      onToggleTodo: () => widget.editorState.toggleTodo(widget.block.id),
    );
  }

  /// 从 EditorState 读取当前 block 的实际 content 并同步到 _controller。
  /// 仅在 onChanged 内调用：类型转换后 content 已变但 _controller 还是旧值。
  void _syncControllerFromState() {
    final blocks = widget.editorState.blocks;
    final idx = blocks.indexWhere((b) => b.id == widget.block.id);
    if (idx < 0) return;
    final actualText = blocks[idx].content.toPlainText();
    if (_controller.text != actualText) {
      _controller.value = TextEditingValue(
        text: actualText,
        selection: TextSelection.collapsed(offset: actualText.length),
      );
    }
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
          noteRoot.createBlock(
            const ParagraphType(),
            content: RichText.text(selectedText),
            properties: {'originalBlockId': widget.block.id},
          );
          widget.editorState.switchToChat();
          // 引用由 ChatBar 内部处理，当前简化直接触发切换
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
