// pi 聊天日期分隔件 —— 2026-10-28 自 lib/core/ai_chat/pi/pi_chat_ui.dart 拆出
//（任务 #7 组件收敛：聊天域通用件集中到 lib/core/ui/chat/）。

import 'package:flutter/material.dart';

import 'pi_chat_style.dart';

/// 日期分隔：不做成灰胶囊（那是 Material Chip 的观感），
/// 改用「细线 + 居中文字」，更安静。
class PiDayDivider extends StatelessWidget {
  final String label;

  const PiDayDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final colors = PiChatColors.of(t);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PiChatTokens.s4),
      child: Row(
        children: [
          Expanded(child: Divider(color: colors.bubbleBorder, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PiChatTokens.s3),
            child: Text(
              label,
              style: t.textTheme.labelSmall?.copyWith(
                color: colors.metaText.withValues(alpha: 0.8),
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(child: Divider(color: colors.bubbleBorder, height: 1)),
        ],
      ),
    );
  }
}
