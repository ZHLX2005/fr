import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/ask_message_data.dart';

/// Strategy for rendering Ask messages (input field with confirm/cancel)
class AskMessageWidgetStrategy extends MessageWidgetStrategy<AskMessageData> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
  }

  @override
  Widget build(BuildContext context, AskMessageData data) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Question text
          Text(
            data.question,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),

          // Input field
          Container(
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
                hintText: data.placeholder,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _controller.clear();
                  // TODO: handle cancel
                },
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final text = _controller.text.trim();
                  if (text.isNotEmpty) {
                    // TODO: handle confirm with text
                  }
                },
                child: const Text('确认'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  AskMessageData createMockData() => AskMessageData(
    question: '请输入您的回复：',
    placeholder: '在这里输入...',
  );
}
