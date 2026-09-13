// lib/core/sudoku/widgets/sudoku_error_badge.dart
//
// 错误数 badge：在玩家 / 对手信息条上挂的小红圈，显示当前错误填值数。
//
// 颜色走 context.colors（通用通道）：
//   · 错误数 > 0：context.colors.danger 底色 + context.colors.surface 文字
//   · 错误数 == 0：context.colors.outline 底色 + context.colors.textMuted 文字
//
// 紧凑展示（高度 20 圆角矩形），不抢棋盘主视觉。

import 'package:flutter/material.dart';

import '../../../widgets/context_colors.dart';

class SudokuErrorBadge extends StatelessWidget {
  final int errorCount;

  const SudokuErrorBadge({
    super.key,
    required this.errorCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasErrors = errorCount > 0;
    final bg = hasErrors ? colors.danger : colors.outline.withValues(alpha: 0.4);
    final fg = hasErrors ? colors.surface : colors.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 12,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            '$errorCount',
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
