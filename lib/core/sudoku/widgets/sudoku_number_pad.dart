// lib/core/sudoku/widgets/sudoku_number_pad.dart
//
// 数独数字键盘：1-9 数字按钮 + 清空按钮 + 提交按钮。
//
// 颜色：走 context.colors（通用 6 角色通道 —— 这是 widget chrome，不是数独棋盘
// 语义，不走 context.sudokuColors）。
//   · 主按钮（数字）：context.colors.accent 文本
//   · 次按钮（清空）：context.colors.textMuted
//   · 提交按钮：context.colors.accent 强调
//
// 状态：
//   · onNumber(int n)：用户按了数字 n（n ∈ 1..9）
//   · onClear()：用户按了清空
//   · onSubmit()：用户按了提交（仅当 canSubmit=true 时显示）
//   · canSubmit=false 时不显示提交按钮（联机对战中通常由 host 主动提交）
//   · disabledNumbers: 已填满 / 已锁定的数字（灰显，不响应）

import 'package:flutter/material.dart';

import '../../../widgets/context_colors.dart';

class SudokuNumberPad extends StatelessWidget {
  final void Function(int n) onNumber;
  final VoidCallback onClear;
  final VoidCallback? onSubmit;
  final Set<int> disabledNumbers;

  const SudokuNumberPad({
    super.key,
    required this.onNumber,
    required this.onClear,
    this.onSubmit,
    this.disabledNumbers = const <int>{},
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 数字 1-9：三行三列
        for (var row = 0; row < 3; row++)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var col = 0; col < 3; col++)
                _buildNumberButton(
                  context,
                  n: row * 3 + col + 1,
                  fg: colors.accent,
                  disabled: disabledNumbers.contains(row * 3 + col + 1),
                ),
            ],
          ),
        const SizedBox(height: 8),
        // 清空 + 提交
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _buildActionButton(
                context,
                label: '清空',
                fg: colors.textMuted,
                onTap: onClear,
              ),
            ),
            if (onSubmit != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  context,
                  label: '提交',
                  fg: colors.accent,
                  onTap: onSubmit!,
                  emphasized: true,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildNumberButton(
    BuildContext context, {
    required int n,
    required Color fg,
    required bool disabled,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: disabled
              ? context.colors.outline.withValues(alpha: 0.3)
              : context.colors.surface,
          child: InkWell(
            onTap: disabled ? null : () => onNumber(n),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              child: Text(
                '$n',
                style: TextStyle(
                  color: fg,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required Color fg,
    required VoidCallback onTap,
    bool emphasized = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: emphasized
            ? context.colors.accent.withValues(alpha: 0.15)
            : context.colors.surface,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 48,
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 16,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
