// lib/core/sudoku/models/sudoku_cell.dart
//
// 数独单格：值 / 笔记 / 错误标记。
//
// isInitial 由 puzzle 生成时设置；普通填值不改。

class SudokuCell {
  int? value;
  bool isInitial;
  Set<int> notes;
  bool isError;

  SudokuCell({
    this.value,
    this.isInitial = false,
    Set<int>? notes,
    this.isError = false,
  }) : notes = notes ?? <int>{};

  bool get isEmpty => value == null;

  void setValue(int? v, {bool isError = false}) {
    value = v;
    this.isError = isError;
    if (v != null) notes.clear();
  }

  void toggleNote(int n) {
    if (value != null) return;
    if (!notes.add(n)) notes.remove(n);
  }
}
