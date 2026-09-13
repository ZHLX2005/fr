// lib/core/sudoku/widgets/sudoku_grid.dart
//
// 9x9 数独棋盘（81 个 SudokuCellWidget）。
//
// 用 GridView.builder + SliverGridDelegateWithFixedCrossAxisCount(9) 实现，
// physics NeverScrollable（强制 1:1 AspectRatio 固定）。
//
// 选中行 / 列高亮：在外层用 accent 通道（context.sudokuColors.accent）画底色，
// 再用 GridView 叠 81 格 —— 这里只负责单个 cell 渲染，行 / 列高亮由调用方
// 用 Stack 叠加（本文件只暴露 selected 单元格信息）。

import 'package:flutter/material.dart';

import '../models/sudoku_board.dart';
import 'sudoku_cell_widget.dart';

class SudokuGrid extends StatelessWidget {
  final SudokuBoard board;
  final int? selectedRow;
  final int? selectedCol;
  final void Function(int r, int c)? onCellTap;

  const SudokuGrid({
    super.key,
    required this.board,
    this.selectedRow,
    this.selectedCol,
    this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 9,
        ),
        itemCount: 81,
        itemBuilder: (ctx, i) {
          final r = i ~/ 9;
          final c = i % 9;
          return SudokuCellWidget(
            cell: board.cells[r][c],
            selected: r == selectedRow && c == selectedCol,
            onTap: onCellTap == null ? null : () => onCellTap!(r, c),
          );
        },
      ),
    );
  }
}
