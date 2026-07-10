import 'dart:async';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import '../../../core/note/note_root_scope.dart';
import '../../../services/media_service.dart';
import 'state.dart';
import 'ai/ai_bar.dart';
import 'ai/ai_conversation.dart' show AiConversationOverlay;
import 'ai/diff_segment.dart';



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

  // 长按检测
  Timer? _longPressTimer;
  Offset? _longPressOrigin;


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
    } else if (!_focusNode.hasFocus) {
      final newText = widget.block.content.toPlainText();
      if (newText != _controller.text) {
        _controller.text = newText;
      }
    }

    if (!oldWidget.isSelected && widget.isSelected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNode.requestFocus();
        _focusNode.addListener(_onFocusChangeToShowKeyboard);
      });
    }
  }

  void _onFocusChangeToShowKeyboard() {
    if (_focusNode.hasFocus) {
      _focusNode.removeListener(_onFocusChangeToShowKeyboard);
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
  }

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
    _longPressTimer?.cancel();
    _longPressTimer?.cancel();
    _focusNode.removeListener(_onFocusChangeToShowKeyboard);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canLongPress = widget.block.type.showQuickDelete;

    Widget content;
    final pendingDiff = widget.editorState.pendingDiffFor(widget.block.id);
    final pendingRemoved = widget.editorState.isBlockPendingRemoved(widget.block.id);
    final pendingNew = widget.editorState.pendingNewBlockIds.contains(widget.block.id);

    if (pendingRemoved) {
      // AI 标记为删除 — 整块置灰、删除线，等待用户接受/拒绝
      content = _buildPendingRemoved(pendingNew ? null : widget.block);
    } else if (pendingDiff != null && pendingDiff.isNotEmpty) {
      // 该 block 有待确认的 AI 修改 — 用 RichText 内联高亮渲染
      content = _buildDiffHighlight(pendingDiff);
    } else if (pendingNew) {
      // AI 新增的 block — 淡绿色背景 + "新增"标签
      content = _buildPendingNew(widget.block);
    } else if (widget.isSelected && !widget.block.type.containerOnly && widget.block.type is! ImageType) {
      content = _buildTextField();
    } else {
      content = NoteRootScope.of(context).noteRoot.renderBlock(
          context,
          widget.block,
          onToggleTodo: () => widget.editorState.toggleTodo(widget.block.id),
          onTapAddImage: widget.block.type is ImageType
              ? () => _showAddImageDialog()
              : null,
        );
    }

    if (canLongPress) {
      content = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerCancel,
          onPointerCancel: _onPointerCancel,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              widget.editorState.hideDeleteMenu();
              widget.editorState.select(widget.block.id);
            },
            child: content,
          ),
        ),
      );
    } else {
      content = GestureDetector(
        onTap: () {
          widget.editorState.hideDeleteMenu();
          widget.editorState.select(widget.block.id);
        },
        child: content,
      );
    }

    final body = Material(
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
            Expanded(child: content),
            if (widget.isSelected) const SizedBox(width: 24),
          ],
        ),
      ),
    );

    // 删除按钮直接渲染在 widget 树里，自然跟随 block 拖拽
    if (canLongPress && widget.editorState.isDeleteMenuShown(widget.block.id)) {
      return Padding(
        // 给顶部负偏移腾出 hit test 空间
        padding: const EdgeInsets.only(top: 38),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 抵消 padding 把 body 放回原位
            Transform.translate(
              offset: const Offset(0, -38),
              child: body,
            ),
            Positioned(
              top: 0,
              right: 4,
              child: _DeletePill(
                onDelete: () {
                  widget.editorState.hideDeleteMenu();
                  widget.editorState.select(widget.block.id);
                  widget.editorState.deleteBlock();
                },
              ),
            ),
          ],
        ),
      );
    }

    return body;
  }

  // === 长按检测 ===

  void _onPointerDown(PointerDownEvent event) {
    // 菜单已显示在任意位置 → 任何点击都关闭
    if (widget.editorState.deleteMenuBlockId != null) {
      widget.editorState.hideDeleteMenu();
      return;
    }
    _longPressOrigin = event.position;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(const Duration(milliseconds: 400), () {
      _longPressOrigin = null;
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      widget.editorState.showDeleteMenu(widget.block.id);
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_longPressOrigin != null &&
        (event.position - _longPressOrigin!).distance > 20) {
      _longPressTimer?.cancel();
      _longPressOrigin = null;
    }
  }

  void _onPointerCancel(PointerEvent event) {
    _longPressTimer?.cancel();
    _longPressOrigin = null;
  }

  // === TextField ===

  Widget _buildTextField() {
    final blockId = widget.block.id;
    final es = widget.editorState;

    // AI Bar 模式
    if (es.isAiBarForBlock(blockId)) {
      return AiBar(
        blockId: blockId,
        isLoading: false,
        onSend: (text) => es.sendAiPrompt(blockId, text),
        onCancel: () => es.deactivateAiBar(),
      );
    }

    // AI 正在加载 — 显示 loading bar inline
    if (es.isAiLoading(blockId)) {
      return AiBar(
        blockId: blockId,
        isLoading: true,
        onSend: (_) {},
        onCancel: () => es.cancelAiRequest(),
      );
    }

    // AI 已返回结果 — 显示结果 inline
    final aiResult = es.getAiResult(blockId);
    if (aiResult != null) {
      return _buildAiResult(context, aiResult);
    }

    final ml = widget.block.type.multiline;
    final textField = Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final blockEmpty = widget.block.content.toPlainText().isEmpty;
        final controllerEmpty = _controller.text.isEmpty;

        if (event.logicalKey == LogicalKeyboardKey.backspace
            && controllerEmpty && blockEmpty) {
          if (widget.editorState.isBackspaceOnCooldown()) {
            return KeyEventResult.ignored;
          }
          widget.editorState.deleteBlock(silent: true);
          _scheduleRefresh();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter && !ml) {
          final newType = widget.block.type.onEnterType;
          if (newType != null) {
            widget.editorState.addBlockWithType(newType, silent: true);
          }
          _scheduleRefresh();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.space
            && controllerEmpty && blockEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            widget.editorState.activateAiBar(widget.block.id);
          });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        focusNode: _focusNode,
        controller: _controller,
        // 一律允许自动换行：内容超宽时软换行；Enter 仍由 onKeyEvent 拆块（与 multiline 无关）
        maxLines: null,
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
          // 空格召唤 AI：兼容普通空格 (U+0020) 和全角空格 (U+3000)
          if (value.length == 1 && (value == ' ' || value == '　')) {
            _controller.text = '';
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.editorState.activateAiBar(widget.block.id);
            });
            return;
          }
          widget.editorState.updateContent(widget.block.id, value, silent: true);
          _syncControllerFromState();
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

  Widget _buildAiResult(BuildContext context, List<Block> blocks) {
    final colorScheme = Theme.of(context).colorScheme;
    final noteRoot = NoteRootScope.of(context).noteRoot;
    final blockText = widget.block.content.toPlainText();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.primary, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 错误提示（编辑意图走 inline 后，这里只承担纯问答的错误展示）
          if (widget.editorState.aiError != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.editorState.aiError!,
                style: TextStyle(fontSize: 12, color: colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: 6),
          ],
          // 逐个渲染每个 Block（纯问答的 AI 回复）
          for (final block in blocks)
            noteRoot.renderBlock(
              context,
              block,
              onToggleTodo: null,
              onTapAddImage: null,
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              _aiResultBtn(context, Icons.forum, '对话', () {
                final es = widget.editorState;
                es.clearAiResult(widget.block.id);
                final firstText = blocks.isNotEmpty ? blocks.first.content.toPlainText() : '';
                if (context.mounted) {
                  AiConversationOverlay.show(
                    context,
                    blockId: widget.block.id,
                    editorState: es,
                    initialText: firstText,
                    blockTitle: blockText,
                  );
                }
              }),
              const Spacer(),
              _aiResultBtn(context, Icons.undo, null, () {
                widget.editorState.clearAiResult(widget.block.id);
              }),
              const SizedBox(width: 8),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  icon: const Icon(Icons.check, color: Colors.white),
                  onPressed: () => widget.editorState.confirmAiResult(widget.block.id),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aiResultBtn(BuildContext context, IconData icon, String? label, VoidCallback? onTap) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 28,
          padding: label != null ? const EdgeInsets.symmetric(horizontal: 6) : EdgeInsets.zero,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
              if (label != null) ...[
                const SizedBox(width: 3),
                Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ),
    );
  }

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
          // 选中文本后激活 AI Bar
          widget.editorState.activateAiBar(widget.block.id);
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

  Widget _buildPendingRemoved(Block? block) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = NoteRootScope.of(context).noteRoot.textStyleFor(widget.block, context)
        ?? TextStyle(fontSize: 14, color: colorScheme.onSurface);
    return Opacity(
      opacity: 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 13, color: Colors.red.shade400),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                block?.content.toPlainText() ?? '(空)',
                style: baseStyle.copyWith(
                  decoration: TextDecoration.lineThrough,
                  decorationColor: Colors.red.shade400,
                  decorationThickness: 2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text('— 待删除',
                style: TextStyle(fontSize: 11, color: Colors.red.shade400)),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingNew(Block block) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border(left: BorderSide(color: Colors.green.shade400, width: 3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.add_circle_outline,
                size: 13, color: Colors.green.shade700),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: NoteRootScope.of(context).noteRoot.renderBlock(
              context,
              block,
            ),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('+ 新增',
                style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
          ),
        ],
      ),
    );
  }

  Widget _buildDiffHighlight(List<DiffSegment> segments) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = NoteRootScope.of(context).noteRoot.textStyleFor(widget.block, context)
        ?? TextStyle(fontSize: 14, color: colorScheme.onSurface);

    final spans = <InlineSpan>[];
    for (final seg in segments) {
      if (seg.isKept) {
        spans.add(TextSpan(text: seg.text, style: baseStyle));
      } else if (seg.isRemoved) {
        spans.add(TextSpan(
          text: seg.text,
          style: baseStyle.copyWith(
            color: colorScheme.onSurface.withValues(alpha: 0.5),
            decoration: TextDecoration.lineThrough,
            decorationColor: Colors.red.shade400,
            decorationThickness: 2,
            backgroundColor: Colors.red.shade50,
          ),
        ));
      } else if (seg.isAdded) {
        spans.add(TextSpan(
          text: seg.text,
          style: baseStyle.copyWith(
            color: Colors.green.shade900,
            backgroundColor: Colors.green.shade100,
            fontWeight: FontWeight.w500,
          ),
        ));
      }
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      // 选中态 — pending diff 期间 block 不能直接编辑
      onTap: () => widget.editorState.select(widget.block.id),
    );
  }
}

/// 删除按钮 + 小尖角指向 block — 直接在 widget 树内渲染。
class _DeletePill extends StatelessWidget {
  final VoidCallback onDelete;

  const _DeletePill({required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 按钮区域用 GestureDetector + HitTestBehavior.opaque 拦截，
        // 防止外层 Listener 重复接收事件导致多次删除
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDelete,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: scheme.error.withValues(alpha: 0.04),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline, size: 15, color: scheme.error),
                const SizedBox(width: 5),
                Text('删除', style: TextStyle(
                  fontSize: 13,
                  height: 1.0,
                  color: scheme.error,
                  fontWeight: FontWeight.w500,
                )),
              ],
            ),
          ),
        ),
        // 小尖角指向下方 block
        CustomPaint(
          size: const Size(10, 5),
          painter: _TrianglePainter(color: scheme.error.withValues(alpha: 0.6)),
        ),
      ],
    );
  }
}

/// 画一个小三角形（朝下），作为指向 block 的尖角。
class _TrianglePainter extends CustomPainter {
  final Color color;

  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) => oldDelegate.color != color;
}
