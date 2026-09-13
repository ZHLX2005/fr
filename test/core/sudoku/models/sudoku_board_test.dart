// test/core/sudoku/models/sudoku_board_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/sudoku/engine/sudoku_generator.dart';
import 'package:xiaodouzi_fr/core/sudoku/models/sudoku_board.dart';

void main() {
  group('SudokuBoard', () {
    late SudokuBoard board;

    setUp(() {
      board = SudokuBoard.fromPuzzle(
        SudokuGenerator.generate(difficulty: 'medium', seed: 1),
      );
    });

    test('fromPuzzle 初始格 isInitial=true', () {
      int initialCount = 0;
      for (final row in board.cells) {
        for (final c in row) {
          if (c.isInitial) initialCount++;
        }
      }
      expect(initialCount, 30);
    });

    test('filledCount 等于已填值格数', () {
      expect(board.filledCount, 30);
    });

    test('errorCount 初始为 0', () {
      expect(board.errorCount, 0);
    });

    test('isComplete 初始 false（有空）', () {
      expect(board.isComplete, isFalse);
    });

    test('isComplete 填完且全对为 true', () {
      final p = SudokuGenerator.generate(difficulty: 'easy', seed: 2);
      final b = SudokuBoard.fromPuzzle(p);
      for (int r = 0; r < 9; r++) {
        for (int c = 0; c < 9; c++) {
          if (b.cells[r][c].value == null) {
            b.setValue(r, c, p.solution[r * 9 + c], isValidMove: (rr, cc, v) => true);
          }
        }
      }
      expect(b.isComplete, isTrue);
    });

    test('错误数计算', () {
      final p = SudokuGenerator.generate(difficulty: 'easy', seed: 3);
      final b = SudokuBoard.fromPuzzle(p);
      // 找两个空格分别试错和对
      int? emptyR, emptyC, emptyR2, emptyC2;
      for (int r = 0; r < 9 && (emptyR == null || emptyR2 == null); r++) {
        for (int c = 0; c < 9; c++) {
          if (b.cells[r][c].value == null) {
            emptyR ??= r;
            emptyC ??= c;
            if (emptyR != null && emptyR2 == null && (r != emptyR || c != emptyC)) {
              emptyR2 = r;
              emptyC2 = c;
            }
          }
        }
      }
      b.setValue(emptyR!, emptyC!, 1, isValidMove: (r, c, v) => false); // 错的
      b.setValue(emptyR2!, emptyC2!, p.solution[emptyR2! * 9 + emptyC2!], isValidMove: (r, c, v) => true); // 对的
      expect(b.errorCount, 1);
    });
  });
}
