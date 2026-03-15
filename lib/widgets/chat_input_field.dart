import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChatInputField extends StatefulWidget {
  final Function(String content) onSend;
  final Function()? onAttachmentTap;
  final bool isLoading;
  final String hintText;
  final int maxLines;
  final TextEditingController? controller;

  const ChatInputField({
    super.key,
    required this.onSend,
    this.onAttachmentTap,
    this.isLoading = false,
    this.hintText = '输入消息...',
    this.maxLines = 5,
    this.controller,
  });

  @override
  State<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends State<ChatInputField> {
  late TextEditingController _controller;
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_onTextChanged);
    }
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _isComposing = _controller.text.trim().isNotEmpty;
    });
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isLoading) return;

    widget.onSend(text);
    _controller.clear();
    setState(() {
      _isComposing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Attachment button
              if (widget.onAttachmentTap != null)
                IconButton(
                  icon: Icon(
                    Icons.add_circle_outline,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    size: 28,
                  ),
                  onPressed: widget.onAttachmentTap,
                ),

              // Text input field
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _controller,
                    maxLines: widget.maxLines,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Emoji button (placeholder)
              IconButton(
                icon: Icon(
                  Icons.emoji_emotions_outlined,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  size: 24,
                ),
                onPressed: () {
                  // TODO: Show emoji picker
                  HapticFeedback.lightImpact();
                },
              ),

              // Send button
              IconButton(
                icon: widget.isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Icon(
                        _isComposing ? Icons.send : Icons.mic,
                        color: _isComposing
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withOpacity(0.6),
                        size: 24,
                      ),
                onPressed: _isComposing && !widget.isLoading ? _handleSend : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
