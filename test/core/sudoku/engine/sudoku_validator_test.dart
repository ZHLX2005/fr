// test/core/sudoku/engine/sudoku_validator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/sudoku/engine/sudoku_validator.dart';

void main() {
  group('sudoku_validator', () {
    test('空 board 合法', () {
      final cells = List.generate(9, (_) => List<int?>.filled(9, null));
      expect(SudokuValidator.isValidBoard(cells), isTrue);
    });

    test('行冲突', () {
      final cells = List.generate(9, (_) => List<int?>.filled(9, null));
      cells[0][0] = 5;
      cells[0][1] = 5;
      expect(SudokuValidator.isValidBoard(cells), isFalse);
    });

    test('列冲突', () {
      final cells = List.generate(9, (_) => List<int?>.filled(9, null));
      cells[0][0] = 5;
      cells[1][0] = 5;
      expect(SudokuValidator.isValidBoard(cells), isFalse);
    });

    test('宫冲突', () {
      final cells = List.generate(9, (_) => List<int?>.filled(9, null));
      cells[0][0] = 5;
      cells[1][1] = 5;
      expect(SudokuValidator.isValidBoard(cells), isFalse);
    });

    test('完全合法 board', () {
      final cells = [
        [5,3,4,6,7,8,9,1,2],
        [6,7,2,1,9,5,3,4,8],
        [1,9,8,3,4,2,5,6,7],
        [8,5,9,7,6,1,4,2,3],
        [4,2,6,8,5,3,7,9,1],
        [7,1,3,9,2,4,8,5,6],
        [9,6,1,5,3,7,2,8,4],
        [2,8,7,4,1,9,6,3,5],
        [3,4,5,2,8,6,1,7,9],
      ];
      expect(SudokuValidator.isValidBoard(cells), isTrue);
    });

    test('isValidMove 同值已存在返回 false', () {
      final cells = List.generate(9, (_) => List<int?>.filled(9, null));
      cells[0][0] = 5;
      expect(SudokuValidator.isValidMove(cells, 0, 1, 5), isFalse);
      expect(SudokuValidator.isValidMove(cells, 1, 0, 5), isFalse);
      expect(SudokuValidator.isValidMove(cells, 1, 1, 5), isFalse);
      expect(SudokuValidator.isValidMove(cells, 2, 3, 5), isTrue);
    });
  });
}
