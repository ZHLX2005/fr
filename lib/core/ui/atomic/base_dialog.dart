// Layer 4: BaseConfirmDialog 工具。
//
// 集中 "Cancel + danger-confirm" 模式。
// 默认文案为中文通用词（确认/取消）；具体动作（删除/清空/退出）由调用方传 confirmLabel。

import 'package:flutter/material.dart';

import '../../../core/theme/extensions/color_strategy_extension.dart';
import '../../../core/theme/colors/strategy/color_strategy/color_strategy.dart';
import '../../../core/theme/colors/strategy/color_strategy/themes/default.dart';

class BaseConfirmDialog {
  const BaseConfirmDialog._();

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    VoidCallback? onConfirm,
    String confirmLabel = '确认',
    String cancelLabel = '取消',
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
              onConfirm?.call();
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
