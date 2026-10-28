// Layer 4: BaseEmptyState 原子组件。
//
// 居中显示：outline 图标 + 可选标题/副标题 + 可选按钮。
// 用于 "No X yet" 类空态。

import 'package:flutter/material.dart';

import '../../../../core/theme/extensions/color_strategy_extension.dart';
import '../../../../core/theme/colors/strategy/color_strategy/color_strategy.dart';
import '../../../../core/theme/colors/strategy/color_strategy/themes/default.dart';
import '../../global/button/main.dart';

class BaseEmptyState extends StatelessWidget {
  const BaseEmptyState({
    super.key,
    required this.icon,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.actionColor,
    this.iconSize = 64,
    this.strategy,
  }) : assert(
          title != null || message != null,
          'title 与 message 至少提供一个',
        );

  /// 空态图标。
  final IconData icon;

  /// 主文案（粗体）；只传 [message] 时等价旧用法。
  final String? title;

  /// 副文案 / 单行提示（弱色）。
  final String? message;

  /// 可选动作按钮文案。
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 操作按钮主色（默认 null → 走 strategy.accent）
  final Color? actionColor;

  /// 图标尺寸（手写空态常见 56 / 64 两档，默认 64）。
  final double iconSize;

  final ColorStrategy? strategy;

  @override
  Widget build(BuildContext context) {
    final s = _resolve(context);
    final accent = actionColor ?? s.accent;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: iconSize, color: s.outline),
          const SizedBox(height: 16),
          if (title != null) ...[
            Text(
              title!,
              style: TextStyle(
                color: s.text,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (message != null) const SizedBox(height: 4),
          ],
          if (message != null)
            Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(color: s.textMuted, fontSize: 13),
            ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 8),
            BaseButton(
              onPressed: onAction,
              label: actionLabel!,
              foreground: accent,
              border: accent,
            ),
          ],
        ],
      ),
    );
  }

  ColorStrategy _resolve(BuildContext context) {
    final injected = strategy;
    if (injected != null) return injected;
    final ext = Theme.of(context).extension<ColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultColorStrategy.of(Theme.of(context).colorScheme);
  }
}
