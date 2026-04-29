import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/ask_message_data.dart';

/// Strategy for rendering Ask messages (input field with confirm/cancel)
class AskMessageWidgetStrategy extends MessageWidgetStrategy<AskMessageData> {
  @override
  Widget build(BuildContext context, AskMessageData data) {
    return _AskMessageContent(data: data);
  }

  @override
  AskMessageData createMockData() => AskMessageData(
    question: '请输入您的回复：',
    placeholder: '在这里输入...',
  );
}

class _AskMessageContent extends StatefulWidget {
  final AskMessageData data;

  const _AskMessageContent({required this.data});

  @override
  State<_AskMessageContent> createState() => _AskMessageContentState();
}

class _AskMessageContentState extends State<_AskMessageContent> {
  final TextEditingController _controller = TextEditingController();
  bool _isFixed = false;
  String _fixedText = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleConfirm() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _fixedText = text;
        _isFixed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Question text
          Text(
            widget.data.question,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),

          // Content area - fixed or input
          if (_isFixed)
            _buildFixedContent(theme)
          else
            _buildInputArea(theme),

          if (!_isFixed) ...[
            const SizedBox(height: 12),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _controller.clear(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _handleConfirm,
                  child: const Text('确认'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputArea(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: TextField(
        controller: _controller,
        maxLines: 3,
        minLines: 1,
        decoration: InputDecoration(
          hintText: widget.data.placeholder,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  Widget _buildFixedContent(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _fixedText,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
