// Layer 4: BaseEmptyState 原子组件。
//
// 居中显示：outline 图标 + 提示文本 + 可选按钮。
// 用于 "No X yet" 类空态。

import 'package:flutter/material.dart';

import '../../core/theme/extensions/color_strategy_extension.dart';
import '../../core/theme/strategy/color_strategy.dart';
import '../../core/theme/strategy/default_color_strategy.dart';
import 'base_button.dart';

class BaseEmptyState extends StatelessWidget {
  const BaseEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionColor,
    this.strategy,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 操作按钮主色（默认 null → 走 strategy.accent）
  final Color? actionColor;
  final ColorStrategy? strategy;

  @override
  Widget build(BuildContext context) {
    final s = _resolve(context);
    final accent = actionColor ?? s.accent;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: s.outline),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: s.textMuted, fontSize: 13)),
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