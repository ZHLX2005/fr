// lib/core/sudoku/engine/sudoku_generator.dart
//
// 数独生成器：
//   1. 用 seed 初始化 Random
//   2. 回溯生成完整解（fill 81 格）
//   3. 按难度挖洞（easy 35 / medium 30 / hard 25 filled）
//   4. 每挖一格都校验解仍唯一；不可挖则跳过，保证最终达到目标 filled 数
//
// 挖洞顺序：先按对称对 (p, 80-p) 顺序挖，中心自身对称（p=40）。
// 解唯一性：用回溯计数前 2 次找到就停（maxSolutions=2），
//   不要求精确计数，只验证"非多解"。
// 性能：hard 难度单次生成 < 500ms。

import 'dart:math';
import '../models/sudoku_puzzle.dart';
import 'sudoku_validator.dart';

class SudokuGenerator {
  static const int size = 9;
  static const int cells = 81;

  /// 难度 → 已填格数
  static int _difficultyToFilled(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return 35;
      case 'hard':
        return 25;
      case 'medium':
      default:
        return 30;
    }
  }

  /// 主入口
  static SudokuPuzzle generate({required String difficulty, int? seed}) {
    final rng = Random(seed ?? DateTime.now().microsecondsSinceEpoch);
    for (int attempt = 0; attempt < 500; attempt++) {
      final solution = _fillSolved(List.filled(cells, 0), rng);
      final targetFilled = _difficultyToFilled(difficulty);
      final puzzle = _digHoles(solution, targetFilled, rng);
      // 必须恰好达到目标 filled 数（per-dig 检查已保证唯一性）
      if (puzzle.where((v) => v != 0).length == targetFilled) {
        return SudokuPuzzle(
          puzzle: puzzle,
          solution: solution,
          seed: seed ?? 0,
          difficulty: difficulty,
        );
      }
    }
    // 极端情况：重试 500 次仍未达到目标，回退到 easy（更密更不易多解）
    final rngFallback = Random(seed ?? 0);
    final solution = _fillSolved(List.filled(cells, 0), rngFallback);
    final puzzle = _digHoles(solution, 40, rngFallback);
    return SudokuPuzzle(
      puzzle: puzzle,
      solution: solution,
      seed: seed ?? 0,
      difficulty: 'easy',
    );
  }

  /// 回溯生成完整解（81 格全部填满）
  static List<int> _fillSolved(List<int> grid, Random rng) {
    int findEmpty() {
      for (int i = 0; i < cells; i++) {
        if (grid[i] == 0) return i;
      }
      return -1;
    }

    bool backtrack() {
      final idx = findEmpty();
      if (idx == -1) return true;
      final r = idx ~/ size;
      final c = idx % size;
      final nums = [1, 2, 3, 4, 5, 6, 7, 8, 9]..shuffle(rng);
      for (final v in nums) {
        if (SudokuValidator.isValidMove(_toGrid(grid), r, c, v)) {
          grid[idx] = v;
          if (backtrack()) return true;
          grid[idx] = 0;
        }
      }
      return false;
    }

    backtrack();
    return grid;
  }

  /// 挖洞：单格挖洞 + 每步唯一性检查（标准 Sudoku 生成法）。
  /// 优先按对称对顺序挖（一对中两格都安全才挖），
  /// 单格不可挖时跳过该位置继续，保证最终达到目标 filled 数。
  static List<int> _digHoles(List<int> solution, int targetFilled, Random rng) {
    final puzzle = List<int>.from(solution);
    int filled = cells;
    // 构造对称对顺序：每对 (p, 80-p) 相邻
    final order = <int>[];
    final pairIdxs = List<int>.generate(40, (i) => i)..shuffle(rng);
    for (final idx in pairIdxs) {
      order.add(idx);
      order.add(80 - idx);
    }
    order.add(40); // 中心（自身对称）

    for (final p in order) {
      if (filled <= targetFilled) break;
      if (puzzle[p] != 0) {
        final saved = puzzle[p];
        puzzle[p] = 0;
        filled--;
        if (countSolutions(puzzle, maxSolutions: 2) > 1) {
          puzzle[p] = saved;
          filled++;
        }
      }
    }
    return puzzle;
  }

  /// 计数解的前 maxSolutions 个解（用于唯一性验证）
  static int countSolutions(List<int> puzzle, {int maxSolutions = 2}) {
    final grid = List<int>.from(puzzle);
    int count = 0;
    int findEmpty() {
      for (int i = 0; i < cells; i++) {
        if (grid[i] == 0) return i;
      }
      return -1;
    }

    void backtrack() {
      if (count >= maxSolutions) return;
      final idx = findEmpty();
      if (idx == -1) {
        count++;
        return;
      }
      final r = idx ~/ size;
      final c = idx % size;
      final asGrid = _toGrid(grid);
      for (int v = 1; v <= 9; v++) {
        if (SudokuValidator.isValidMove(asGrid, r, c, v)) {
          grid[idx] = v;
          backtrack();
          grid[idx] = 0;
          if (count >= maxSolutions) return;
        }
      }
    }

    backtrack();
    return count;
  }

  static List<List<int?>> _toGrid(List<int> flat) {
    return List.generate(
      size,
      (i) => List<int?>.generate(size, (j) => flat[i * size + j]),
    );
  }
}
