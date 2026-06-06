import 'package:flutter/material.dart';
import 'ai_models.dart';

/// 内联 AI 回复气泡 — 显示在 block 下方
class AiBubble extends StatelessWidget {
  final BlockAIConversation conversation;
  final VoidCallback onOpenConversation;

  const AiBubble({
    super.key,
    required this.conversation,
    required this.onOpenConversation,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = conversation.latestResponseText;
    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 回复文本
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          // 操作按钮行 — 仅对话、撤回、确认
          Row(
            children: [
              // 对话按钮
              _actionBtn(
                context,
                Icons.forum,
                () => onOpenConversation(),
                label: '对话',
              ),
              const Spacer(),
              // 撤回
              _actionBtn(context, Icons.undo, null),
              const SizedBox(width: 8),
              // 确认按钮
              _actionBtn(context, Icons.check, null, isPrimary: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(BuildContext context, IconData icon, VoidCallback? onTap,
      {String? label, bool isPrimary = false}) {
    final colorScheme = Theme.of(context).colorScheme;

    if (isPrimary) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 18,
          icon: const Icon(Icons.check, color: Colors.white),
          onPressed: onTap ?? () {},
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 32,
          padding: label != null
              ? const EdgeInsets.symmetric(horizontal: 8)
              : const EdgeInsets.all(0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
              if (label != null) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
