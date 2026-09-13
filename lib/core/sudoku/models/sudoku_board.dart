// lib/core/sudoku/models/sudoku_board.dart
//
// 数独棋盘：9×9 SudokuCell 二维数组。
//
// 从 SudokuPuzzle 构造；支持填值 / 笔记 / 错误统计。
// 不内嵌 validator（注入 isValidMove 回调，便于测试）。

import 'sudoku_cell.dart';
import 'sudoku_puzzle.dart';

class SudokuBoard {
  final List<List<SudokuCell>> cells;

  SudokuBoard(this.cells);

  factory SudokuBoard.fromPuzzle(SudokuPuzzle p) {
    return SudokuBoard(
      List.generate(
        9,
        (r) => List.generate(9, (c) {
          final v = p.puzzle[r * 9 + c];
          return SudokuCell(
            value: v == 0 ? null : v,
            isInitial: v != 0,
          );
        }),
      ),
    );
  }

  int get filledCount {
    int n = 0;
    for (final row in cells) {
      for (final c in row) {
        if (c.value != null) n++;
      }
    }
    return n;
  }

  int get errorCount {
    int n = 0;
    for (final row in cells) {
      for (final c in row) {
        if (c.isError) n++;
      }
    }
    return n;
  }

  bool get isComplete {
    for (final row in cells) {
      for (final c in row) {
        if (c.value == null || c.isError) return false;
      }
    }
    return true;
  }

  /// 填值。
  /// [isValidMove] 由调用方注入（典型为 SudokuValidator.isValidMove）。
  /// 当填入值与 puzzle solution 不一致时强制标 isError=true（用于反作弊 / 提示）。
  void setValue(
    int r,
    int c,
    int? v, {
    required bool Function(int r, int c, int v) isValidMove,
  }) {
    final cell = cells[r][c];
    if (cell.isInitial) return;
    final isError = v != null && !isValidMove(r, c, v);
    cell.setValue(v, isError: isError);
  }

  void toggleNote(int r, int c, int n) {
    cells[r][c].toggleNote(n);
  }
}
