// lib/core/sudoku/widgets/sudoku_cell_widget.dart
//
// 单格渲染：值 / 笔记 / 选中 / 题目初始格 / 错误。
//
// 颜色一律走 context.sudokuColors（8 角色通道），不直接读 theme.colorScheme。
//   · 背景三态：cellBg.filled / empty / initial
//   · 选中覆盖：cellSelected
//   · 错误红字：cellText.error；错误格底色叠加 cellError
//   · 初始格文字加粗：cellInitial（视觉区分"题目给的"）
//   · 笔记候选：cellNote（弱色）
//   · 网格线：gridLine
//
// 笔记渲染：≤4 个走单行 Text（紧凑）；>4 个走 3x3 mini-grid（密集排布）。

import 'package:flutter/material.dart';

import '../../../widgets/context_sudoku_colors.dart';
import '../../theme/colors/strategy/sudoku_color_strategy/sudoku_color_strategy.dart';
import '../models/sudoku_cell.dart';

class SudokuCellWidget extends StatelessWidget {
  final SudokuCell cell;
  final bool selected;
  final VoidCallback? onTap;

  const SudokuCellWidget({
    super.key,
    required this.cell,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.sudokuColors;

    // ── 背景：先按三态选底色，错误态叠加 cellError（带 alpha），选中态用 cellSelected
    Color bg;
    if (cell.isInitial) {
      bg = colors.cellBg.initial;
    } else if (cell.value != null) {
      bg = colors.cellBg.filled;
    } else {
      bg = colors.cellBg.empty;
    }
    if (cell.isError) {
      bg = Color.alphaBlend(colors.cellError.withValues(alpha: 0.18), bg);
    }
    if (selected) {
      bg = colors.cellSelected;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: colors.gridLine),
        ),
        child: Center(child: _buildContent(colors)),
      ),
    );
  }

  Widget? _buildContent(SudokuColorStrategy colors) {
    if (cell.value != null) {
      // 已填值
      return Text(
        cell.value.toString(),
        style: TextStyle(
          color: cell.isError ? colors.cellText.error : colors.cellText.regular,
          fontWeight: cell.isInitial ? FontWeight.bold : FontWeight.normal,
          fontSize: 20,
        ),
      );
    }
    if (cell.notes.isEmpty) return null;

    // 笔记候选：>4 个用 3x3 mini-grid（数字 1-9），≤4 个单行紧凑
    if (cell.notes.length > 4) {
      return _buildNotesGrid(colors);
    }
    final numbers = cell.notes.toList()..sort();
    return Text(
      numbers.join(' '),
      style: TextStyle(color: colors.cellNote, fontSize: 10),
    );
  }

  Widget _buildNotesGrid(SudokuColorStrategy colors) {
    // 3x3 mini-grid（数独笔记的经典排布：1-9 按位置填入空格）
    return Padding(
      padding: const EdgeInsets.all(2),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1,
        ),
        itemCount: 9,
        itemBuilder: (_, i) {
          final n = i + 1;
          final present = cell.notes.contains(n);
          return Center(
            child: Text(
              present ? '$n' : '',
              style: TextStyle(
                color: present ? colors.cellNote : Colors.transparent,
                fontSize: 8,
              ),
            ),
          );
        },
      ),
    );
  }
}
