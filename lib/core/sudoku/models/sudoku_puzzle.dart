// lib/core/sudoku/models/sudoku_puzzle.dart
//
// 数独题目包（81 格 + 解 + seed + 难度）。
//
// puzzle / solution 都用 List<int> 长度 81，按 row*9+col 索引。
// 0 = 空格；1-9 = 数字。

class SudokuPuzzle {
  final List<int> puzzle;
  final List<int> solution;
  final int seed;
  final String difficulty;

  const SudokuPuzzle({
    required this.puzzle,
    required this.solution,
    required this.seed,
    required this.difficulty,
  })  : assert(puzzle.length == 81),
        assert(solution.length == 81);
}
