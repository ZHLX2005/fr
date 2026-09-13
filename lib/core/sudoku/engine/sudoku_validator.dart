// lib/core/sudoku/engine/sudoku_validator.dart
//
// 数独合法性校验（行/列/宫冲突检测）。
//
// 不依赖 Flutter；纯 Dart 函数。

class SudokuValidator {
  static const int size = 9;

  /// 检查整盘是否合法（行/列/宫无重复非零值）。
  static bool isValidBoard(List<List<int?>> cells) {
    if (cells.length != size) return false;
    for (int i = 0; i < size; i++) {
      if (cells[i].length != size) return false;
    }
    for (int i = 0; i < size; i++) {
      for (int j = 0; j < size; j++) {
        final v = cells[i][j];
        if (v == null) continue;
        if (!isValidMove(cells, i, j, v)) return false;
      }
    }
    return true;
  }

  /// 检查在 (row, col) 填入 value 是否合法（不与同 row/col/box 内非零值冲突）。
  static bool isValidMove(
    List<List<int?>> cells,
    int row,
    int col,
    int value,
  ) {
    if (value < 1 || value > 9) return false;
    for (int i = 0; i < size; i++) {
      if (i != col && cells[row][i] == value) return false;
      if (i != row && cells[i][col] == value) return false;
    }
    final boxRow = (row ~/ 3) * 3;
    final boxCol = (col ~/ 3) * 3;
    for (int i = boxRow; i < boxRow + 3; i++) {
      for (int j = boxCol; j < boxCol + 3; j++) {
        if (i == row && j == col) continue;
        if (cells[i][j] == value) return false;
      }
    }
    return true;
  }
}
