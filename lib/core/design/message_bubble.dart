import 'package:flutter/material.dart';

import 'slate_palette.dart';

/// 消息发送方
enum BubbleSide {
  /// AI / 对方（左侧，浅表面气泡）
  ai,

  /// 用户 / 自己（右侧，靛蓝气泡）
  user,
}

/// Slate 设计系统 —— 消息气泡（无边框）
///
/// - AI：浅表面气泡（light #EEEEF0 / dark #2A2A2F），黑字
/// - 用户：靛蓝气泡（#4F46E5），白字
/// - 圆角 14px，尾角 4px（AI 左下 / 用户右下）
/// - 无 1px 边框，AI 气泡带柔和阴影
///
/// 供 message_strategy 各 strategy 与聊天页统一使用，保证风格一致。
class MessageBubble extends StatelessWidget {
  final BubbleSide side;
  final Widget child;
  final String? time;
  final double maxWidthFraction;

  const MessageBubble({
    super.key,
    required this.side,
    required this.child,
    this.time,
    this.maxWidthFraction = 0.78,
  });

  bool get _isUser => side == BubbleSide.user;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _isUser
        ? (isDark ? SlatePalette.darkUserBubble : SlatePalette.lightUserBubble)
        : (isDark ? SlatePalette.darkAiBubble : SlatePalette.lightAiBubble);
    final fg = _isUser
        ? SlatePalette.lightOnAccent
        : (isDark ? SlatePalette.darkTextPrimary : SlatePalette.lightTextPrimary);
    final timeColor = _isUser
        ? Colors.white.withValues(alpha: 0.78)
        : (isDark ? SlatePalette.darkTextSecondary : SlatePalette.lightTextSecondary);

    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * maxWidthFraction,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(SlatePalette.radius),
            topRight: const Radius.circular(SlatePalette.radius),
            bottomLeft: Radius.circular(
              _isUser ? SlatePalette.radius : SlatePalette.radiusTail,
            ),
            bottomRight: Radius.circular(
              _isUser ? SlatePalette.radiusTail : SlatePalette.radius,
            ),
          ),
          boxShadow: _isUser
              ? null
              : [
                  BoxShadow(
                    color: isDark
                        ? SlatePalette.darkShadow
                        : SlatePalette.lightShadow,
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
          child: Column(
            crossAxisAlignment: _isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              if (time != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    time!,
                    style: TextStyle(fontSize: 10.5, color: timeColor),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
