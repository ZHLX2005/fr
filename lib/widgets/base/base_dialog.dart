// Layer 4: BaseConfirmDialog 工具。
//
// 集中 "Cancel + danger-confirm" 模式。

import 'package:flutter/material.dart';

import '../../core/theme/extensions/color_strategy_extension.dart';
import '../../core/theme/strategy/color_strategy.dart';
import '../../core/theme/strategy/default_color_strategy.dart';

class BaseConfirmDialog {
  const BaseConfirmDialog._();

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    required VoidCallback onConfirm,
    String confirmLabel = 'Delete',
    String cancelLabel = 'Cancel',
    Color? confirmColor,
  }) async {
    final s = _resolveStrategy(context);
    final danger = confirmColor ?? s.danger;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: s.surface,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel,
                style: TextStyle(color: s.textMuted)),
          ),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(ctx, true);
            },
            child: Text(confirmLabel, style: TextStyle(color: danger)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static ColorStrategy _resolveStrategy(BuildContext context) {
    final ext = Theme.of(context).extension<ColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultColorStrategy.of(Theme.of(context).colorScheme);
  }
}