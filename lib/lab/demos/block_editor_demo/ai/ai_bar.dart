import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 内联 AI 输入栏 — 空格触发后替换 block 的 TextField
class AiBar extends StatefulWidget {
  final String blockId;
  final bool isLoading;
  final void Function(String text) onSend;
  final VoidCallback onCancel;

  const AiBar({
    super.key,
    required this.blockId,
    this.isLoading = false,
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<AiBar> createState() => _AiBarState();
}

class _AiBarState extends State<AiBar> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.isLoading) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(AiBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isLoading && widget.isLoading) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.primary, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Focus(
        onKeyEvent: (node, event) {
          if (widget.isLoading) return KeyEventResult.ignored;
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              widget.onCancel();
            });
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: widget.isLoading
            ? _buildLoadingState(colorScheme)
            : _buildInputState(colorScheme),
      ),
    );
  }

  Widget _buildLoadingState(ColorScheme colorScheme) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'AI 思考中...',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
        ),
        InkWell(
          onTap: widget.onCancel,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.close,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputState(ColorScheme colorScheme) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.auto_awesome,
            size: 13,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: '使用 AI 编辑...',
              hintStyle: TextStyle(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontSize: 14,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
          ),
        ),
        Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 13,
            icon:
                Icon(Icons.arrow_upward, color: colorScheme.onPrimaryContainer),
            onPressed: _send,
          ),
        ),
      ],
    );
  }
}
