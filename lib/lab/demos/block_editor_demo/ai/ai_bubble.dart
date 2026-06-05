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
          // 操作按钮行
          Row(
            children: [
              _actionBtn(context, Icons.thumb_up_outlined, null),
              const SizedBox(width: 2),
              _actionBtn(context, Icons.chat_bubble_outline, null),
              const SizedBox(width: 2),
              _actionBtn(context, Icons.more_horiz, null),
              const Spacer(),
              // 对话按钮
              _actionBtn(
                context,
                Icons.forum,
                () => onOpenConversation(),
                label: '对话',
              ),
              const SizedBox(width: 2),
              _actionBtn(context, Icons.undo, null),
              const SizedBox(width: 2),
              // 确认按钮 — 蓝色圆形
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 14,
                  icon: const Icon(Icons.check, color: Colors.white),
                  onPressed: () {},
                ),
              ),
            ],
          ),
          // footer 计数
          const SizedBox(height: 4),
          Text(
            '${conversation.messages.length} 条消息',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(BuildContext context, IconData icon, VoidCallback? onTap,
      {String? label}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 28,
          padding: label != null
              ? const EdgeInsets.symmetric(horizontal: 6)
              : const EdgeInsets.all(0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
              if (label != null) ...[
                const SizedBox(width: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
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
