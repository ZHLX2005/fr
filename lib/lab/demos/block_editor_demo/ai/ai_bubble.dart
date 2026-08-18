import 'package:flutter/material.dart';
import '../../../../widgets/context_colors.dart';
import 'ai_models.dart';

/// 内联 AI 回复气泡 — 显示在 block 下方
class AiBubble extends StatelessWidget {
  final BlockAIConversation conversation;
  final VoidCallback onOpenConversation;

  AiBubble({
    super.key,
    required this.conversation,
    required this.onOpenConversation,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colors.scheme;
    final text = conversation.latestResponseText;
    if (text.isEmpty) return SizedBox.shrink();

    return Container(
      margin: EdgeInsets.only(left: 8, right: 8, bottom: 4),
      padding: EdgeInsets.all(10),
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
          SizedBox(height: 8),
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
              Spacer(),
              // 撤回
              _actionBtn(context, Icons.undo, null),
              SizedBox(width: 8),
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
    final colorScheme = context.colors.scheme;

    if (isPrimary) {
      final isDark = colorScheme.brightness == Brightness.dark;
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: isDark ? 0.65 : 0.5),
          ),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 18,
          icon: Icon(Icons.check, color: colorScheme.primary),
          onPressed: onTap ?? () {},
        ),
      );
    }

    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 32,
          padding: label != null
              ? EdgeInsets.symmetric(horizontal: 8)
              : EdgeInsets.all(0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
              if (label != null) ...[
                SizedBox(width: 4),
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
