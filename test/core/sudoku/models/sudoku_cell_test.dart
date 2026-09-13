// test/core/sudoku/models/sudoku_cell_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/sudoku/models/sudoku_cell.dart';

void main() {
  group('SudokuCell', () {
    test('默认空', () {
      final c = SudokuCell();
      expect(c.value, isNull);
      expect(c.isInitial, isFalse);
      expect(c.isEmpty, isTrue);
      expect(c.notes, isEmpty);
      expect(c.isError, isFalse);
    });

    test('setValue', () {
      final c = SudokuCell();
      c.setValue(5);
      expect(c.value, 5);
      expect(c.isEmpty, isFalse);
    });

    test('setValue(null) 清空', () {
      final c = SudokuCell()..setValue(5);
      c.setValue(null);
      expect(c.value, isNull);
    });

    test('toggleNote 增删', () {
      final c = SudokuCell();
      c.toggleNote(3);
      expect(c.notes, contains(3));
      c.toggleNote(3);
      expect(c.notes, isEmpty);
      c.toggleNote(7);
      expect(c.notes, contains(7));
    });

    test('isError 由外部 setValue 设置', () {
      final c = SudokuCell();
      c.setValue(5, isError: true);
      expect(c.isError, isTrue);
    });
  });
}
