// test/core/sudoku/engine/sudoku_generator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/sudoku/engine/sudoku_generator.dart';
import 'package:xiaodouzi_fr/core/sudoku/engine/sudoku_validator.dart';

void main() {
  group('sudoku_generator', () {
    test('easy 难度生成 35 filled', () {
      final p = SudokuGenerator.generate(difficulty: 'easy', seed: 42);
      final filled = p.puzzle.where((v) => v != 0).length;
      expect(filled, 35);
    });

    test('medium 难度生成 30 filled', () {
      final p = SudokuGenerator.generate(difficulty: 'medium', seed: 42);
      expect(p.puzzle.where((v) => v != 0).length, 30);
    });

    test('hard 难度生成 25 filled', () {
      final p = SudokuGenerator.generate(difficulty: 'hard', seed: 42);
      expect(p.puzzle.where((v) => v != 0).length, 25);
    });

    test('solution 自身合法', () {
      final p = SudokuGenerator.generate(difficulty: 'medium', seed: 42);
      final grid = List.generate(9, (i) => List<int>.generate(9, (j) => p.solution[i * 9 + j]));
      expect(SudokuValidator.isValidBoard(grid), isTrue);
    });

    test('puzzle 与 solution 兼容', () {
      final p = SudokuGenerator.generate(difficulty: 'medium', seed: 42);
      for (int i = 0; i < 81; i++) {
        if (p.puzzle[i] != 0) {
          expect(p.puzzle[i], p.solution[i]);
        }
      }
    });

    test('解唯一', () {
      // 多次生成，断言解计数 == 1（用 validator 走简单回溯检查）
      for (int seed = 0; seed < 20; seed++) {
        final p = SudokuGenerator.generate(difficulty: 'medium', seed: seed);
        final count = SudokuGenerator.countSolutions(p.puzzle, maxSolutions: 2);
        expect(count, 1, reason: 'seed=$seed 出现多解');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('同 seed 生成相同 puzzle', () {
      final a = SudokuGenerator.generate(difficulty: 'medium', seed: 12345);
      final b = SudokuGenerator.generate(difficulty: 'medium', seed: 12345);
      expect(a.puzzle, b.puzzle);
      expect(a.solution, b.solution);
    });
  });
}
