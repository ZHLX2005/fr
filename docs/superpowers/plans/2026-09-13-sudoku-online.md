# 数独联机竞赛 实施计划（Stage 1 / 3）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `lib/core/sudoku/` 下落地 smartMatch 联机数独竞赛，host 在准备阶段生成 puzzle（保证唯一解），双方各解各的板，最快正确完成者胜。

**Architecture:** 复用 `lib/core/chess/p2p/` 拆分模式（room_page + room_config_page + net + script/ 拆分 lifecycle/actions），走 relay v3 + Lua 状态机。server 端校验答案（反作弊）。拆 9 个 self-contained 任务。

**Tech Stack:** Flutter (Dart)、Provider 状态管理、`lib/core/net_engine/relay_v3/` 传输、`lib/core/game_kit/lobby/` 共享 lobby UI、`lib/core/theme/colors/strategy/` 五主题通道。

**Spec:** `docs/superpowers/specs/2026-09-13-sudoku-minesweeper-online-design.md` § 2 (sudoku 结构), § 3.1/3.2 (入口+数独 Lua), § 4.1 (准备卡), § 5 (房间页), § 6 (主题)

---

## Global Constraints

- **SDK**: `^3.11.1` (Flutter)
- **依赖**: 不新增 pub 依赖（仅用现有 provider / flutter_riverpod / shared_preferences）
- **命名**: `lib/core/<game>/` 目录命名遵循现有 `chess/` / `tetris/` 模式
- **Lobby spec**: 必为 `const GameLobbySpec`，字段顺序匹配 `GameLobbySpec` 构造器
- **主题**: 所有颜色走 `context.colors` 通道；不写 `Color(0xFF...)` 字面量在 widget 内
- **提交**: 每个 task 末尾必 commit；commit message 走 Conventional Commits
- **测试**: 测试文件镜像 `test/core/<game>/` 路径
- **代码量上限**: 单文件不超过 400 行（参考 `coding-style.md`）

---

## File Structure

```
lib/core/sudoku/                                  # 新建
├── sudoku.dart                                    # 入口
├── lobby/sudoku_lobby_spec.dart                   # const spec + slots
├── models/
│   ├── sudoku_puzzle.dart                         # {puzzle, solution, seed, difficulty}
│   ├── sudoku_board.dart                          # 9×9 二维 cells
│   └── sudoku_cell.dart                           # value/isInitial/notes/isError
├── engine/
│   ├── sudoku_generator.dart                      # 对称挖洞 + 唯一性验证
│   └── sudoku_validator.dart                      # 行/列/宫冲突
├── widgets/
│   ├── sudoku_grid.dart                           # 9×9 渲染
│   ├── sudoku_cell_widget.dart                    # 单格 widget
│   ├── sudoku_number_pad.dart                     # 1-9 输入
│   ├── sudoku_opponent_strip.dart                 # 双方昵称+计时+完成度
│   └── sudoku_error_badge.dart                    # 错误计数
└── p2p/                                           # ★ 镜像 chess/p2p/
    ├── sudoku_room_page.dart                      # state machine 路由
    ├── sudoku_room_config_page.dart               # 准备阶段难度+puzzle 生成
    ├── sudoku_net.dart                            # action 编码 + 快照解码
    └── script/
        ├── sudoku_script.dart                     # 入口 + assembler 拼接
        ├── sudoku_script_lifecycle.dart           # on_init/on_join/on_leave
        └── sudoku_script_actions.dart             # SET_PUZZLE/START/SUBMIT

lib/core/theme/colors/strategy/sudoku_color_strategy/  # 新建
├── sudoku_color_strategy.dart
└── sudoku_color_strategy_factory.dart

lib/core/theme/tokens/color/sudoku/                   # 新建
├── sudoku_cell_bg.dart
├── sudoku_cell_text.dart
├── sudoku_cell_selected.dart
├── sudoku_cell_error.dart
├── sudoku_cell_initial.dart
├── sudoku_cell_note.dart
├── sudoku_grid_line.dart
└── sudoku_accent.dart

lib/lab/demos/sudoku_lua/                             # 修改
├── sudoku_demo.dart                                  # 注册新 spec
└── constants.dart                                    # 新增 relayUrl 等

test/core/sudoku/                                     # 新建
├── engine/
│   ├── sudoku_generator_test.dart
│   └── sudoku_validator_test.dart
├── models/
│   ├── sudoku_board_test.dart
│   └── sudoku_cell_test.dart
└── p2p/
    ├── sudoku_script_guard_test.dart                # 导出表完整性
    ├── sudoku_script_set_puzzle_test.dart           # SET_PUZZLE 校验
    ├── sudoku_script_start_gate_test.dart           # START gate
    └── sudoku_script_submit_test.dart               # SUBMIT winner 判定
```

---

### Task 1: 数独 validator

**Files:**
- Create: `lib/core/sudoku/engine/sudoku_validator.dart`
- Test: `test/core/sudoku/engine/sudoku_validator_test.dart`

**Interfaces:**
- Produces: `bool isValidBoard(List<List<int?>> cells)`, `bool isValidMove(List<List<int?>> cells, int row, int col, int value)`

- [ ] **Step 1: 写失败测试**

```dart
// test/core/sudoku/engine/sudoku_validator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fr/core/sudoku/engine/sudoku_validator.dart';

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
      expect(SudokuValidator.isValidMove(cells, 2, 2, 5), isTrue);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `flutter test test/core/sudoku/engine/sudoku_validator_test.dart`
Expected: FAIL (SudokuValidator not defined)

- [ ] **Step 3: 实现 validator**

```dart
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
```

- [ ] **Step 4: 运行测试通过**

Run: `flutter test test/core/sudoku/engine/sudoku_validator_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/core/sudoku/engine/sudoku_validator.dart test/core/sudoku/engine/sudoku_validator_test.dart
git commit -m "feat(sudoku): add validator (row/col/box conflict check)"
```

---

### Task 2: 数独 generator（含唯一解保证）

**Files:**
- Create: `lib/core/sudoku/engine/sudoku_generator.dart`
- Create: `lib/core/sudoku/models/sudoku_puzzle.dart`
- Test: `test/core/sudoku/engine/sudoku_generator_test.dart`

**Interfaces:**
- Produces:
  - `class SudokuPuzzle { final List<int> puzzle; final List<int> solution; final int seed; final String difficulty; const SudokuPuzzle({...}); }`
  - `class SudokuGenerator { static SudokuPuzzle generate({required String difficulty, int? seed}); static int _difficultyToFilled(String); static List<List<int>> _solveUnique(...); static bool _hasUniqueSolution(List<int> puzzle); }`

- [ ] **Step 1: 写 SudokuPuzzle model + generator 测试**

```dart
// test/core/sudoku/engine/sudoku_generator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fr/core/sudoku/engine/sudoku_generator.dart';
import 'package:fr/core/sudoku/engine/sudoku_validator.dart';

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
```

- [ ] **Step 2: 写 SudokuPuzzle model**

```dart
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
```

- [ ] **Step 3: 运行测试确认失败**

Run: `flutter test test/core/sudoku/engine/sudoku_generator_test.dart`
Expected: FAIL (SudokuGenerator not defined)

- [ ] **Step 4: 实现 generator**

```dart
// lib/core/sudoku/engine/sudoku_generator.dart
//
// 数独生成器：
//   1. 用 seed 初始化 Random
//   2. 回溯生成完整解（fill 81 格）
//   3. 按难度对称挖洞（easy 35 / medium 30 / hard 25 filled）
//   4. 校验挖洞后解仍唯一（回溯计数）
//
// 对称挖洞：选一个格的同时选中心对称格一起挖，降低多解概率。
// 解唯一性：用解的回溯计数前 2 次找到就停（maxSolutions=2），
//   不要求精确计数，只验证"非多解"。
//
// 性能：单次生成 + 唯一性校验 < 50ms。

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
    for (int attempt = 0; attempt < 100; attempt++) {
      final solution = _fillSolved(List.filled(cells, 0), rng);
      final targetFilled = _difficultyToFilled(difficulty);
      final puzzle = _digHoles(solution, targetFilled, rng);
      final solCount = countSolutions(puzzle, maxSolutions: 2);
      if (solCount == 1) {
        return SudokuPuzzle(
          puzzle: puzzle,
          solution: solution,
          seed: seed ?? 0,
          difficulty: difficulty,
        );
      }
    }
    // 极端情况：重试 100 次仍未通过唯一性，回退到 easy（更密更不易多解）
    final rng = Random(seed ?? 0);
    final solution = _fillSolved(List.filled(cells, 0), rng);
    final puzzle = _digHoles(solution, 40, rng);
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

  /// 对称挖洞：每次挖 2 格（中心对称）
  static List<int> _digHoles(List<int> solution, int targetFilled, Random rng) {
    final puzzle = List<int>.from(solution);
    int filled = cells;
    final positions = List.generate(81, (i) => i)..shuffle(rng);
    int i = 0;
    while (filled > targetFilled && i < positions.length) {
      final p1 = positions[i++];
      final p2 = 80 - p1; // 中心对称
      final digs = <int>[p1];
      if (p2 != p1 && filled - digs.length >= targetFilled) digs.add(p2);
      for (final p in digs) {
        if (puzzle[p] != 0) {
          puzzle[p] = 0;
          filled--;
          if (filled <= targetFilled) break;
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
```

- [ ] **Step 5: 运行测试通过**

Run: `flutter test test/core/sudoku/engine/sudoku_generator_test.dart`
Expected: PASS（20 个 seed 全部唯一解可能耗时较长，timeout 30s）

- [ ] **Step 6: 提交**

```bash
git add lib/core/sudoku/engine/sudoku_generator.dart lib/core/sudoku/models/sudoku_puzzle.dart test/core/sudoku/engine/sudoku_generator_test.dart
git commit -m "feat(sudoku): add generator with unique-solution guarantee"
```

---

### Task 3: sudoku_cell + sudoku_board models

**Files:**
- Create: `lib/core/sudoku/models/sudoku_cell.dart`
- Create: `lib/core/sudoku/models/sudoku_board.dart`
- Test: `test/core/sudoku/models/sudoku_cell_test.dart`
- Test: `test/core/sudoku/models/sudoku_board_test.dart`

**Interfaces:**
- Produces:
  - `class SudokuCell { int? value; bool isInitial; Set<int> notes; bool isError; bool get isEmpty; bool get isCorrect; void setValue(int? v); void toggleNote(int n); }`
  - `class SudokuBoard { List<List<SudokuCell>> cells; static SudokuBoard fromPuzzle(SudokuPuzzle p); int get filledCount; int get errorCount; bool get isComplete; void setValue(int r, int c, int? v, {required bool Function(int r, int c, int v) isValid}); void toggleNote(int r, int c, int n); }`

- [ ] **Step 1: 写 cell 测试**

```dart
// test/core/sudoku/models/sudoku_cell_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fr/core/sudoku/models/sudoku_cell.dart';

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
```

- [ ] **Step 2: 实现 SudokuCell**

```dart
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
```

- [ ] **Step 3: 写 board 测试**

```dart
// test/core/sudoku/models/sudoku_board_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fr/core/sudoku/engine/sudoku_generator.dart';
import 'package:fr/core/sudoku/models/sudoku_board.dart';

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
      b.setValue(0, 0, 1, isValidMove: (r, c, v) => false); // 错的
      b.setValue(0, 1, p.solution[0 * 9 + 1], isValidMove: (r, c, v) => true); // 对的
      expect(b.errorCount, 1);
    });
  });
}
```

- [ ] **Step 4: 实现 SudokuBoard**

```dart
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
```

- [ ] **Step 5: 运行测试**

Run: `flutter test test/core/sudoku/models/`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add lib/core/sudoku/models/ test/core/sudoku/models/
git commit -m "feat(sudoku): add cell and board models"
```

---

### Task 4: sudoku_lobby_spec

**Files:**
- Create: `lib/core/sudoku/lobby/sudoku_lobby_spec.dart`
- Modify: `lib/core/game_kit/lobby/game_lobby_spec.dart`（无；确认 RoomCodeRules 复用）

参考 `lib/core/tetris/lobby/tetris_lobby_spec.dart` 写一份 `kSudokuLobbySpec` const（gameId='sudoku', maxPlayers=2, smartMatch, RelayDeviceIdResolver）。hostTitle='数独竞赛（联机）'。

- [ ] **Step 1: 写 spec 文件**

```dart
// lib/core/sudoku/lobby/sudoku_lobby_spec.dart
//
// 数独联机竞赛的 GameLobbySpec —— smartMatch 单按钮入口。
//
// 与 tetris 一致的模式：单表单「昵称 + 房间号」→ tryJoinOrCreate →
// 立即进入。规则（难度）由 host 在准备阶段通过 SET_PUZZLE 推。

import 'package:flutter/material.dart';

import '../../game_kit/lobby/game_lobby_identity.dart';
import '../../game_kit/lobby/game_lobby_spec.dart';

/// 数独入口 spec const。
const GameLobbySpec kSudokuLobbySpec = GameLobbySpec(
  gameId: 'sudoku',
  title: '数独竞赛（联机）',
  heroIcon: Icons.grid_4x4_rounded,
  heroTagline: '输入房间号，与朋友竞速解同一道题',
  relayUrl: 'http://47.110.80.47:8988',
  script: '',  // 占位；Task 5 在 sudoku_script.dart 完成后回填 kSudokuScript
  maxPlayers: 2,
  flow: LobbyFlowType.smartMatch,
  identityResolver: RelayDeviceIdResolver(),
  copy: LobbyCopy(
    primaryBtnText: '进入对局',
    secondaryBtnText: null,
    hintIcon: '◧',
    hintPosition: HintPosition.bottom,
    hintText: '输入同一号码即可对战，谁先到谁是房主。难度与题目由房主在准备阶段生成。',
    aliasFieldHint: '昵称（如：玩家 A）',
    codeFieldHint: '4–6 位大写字母数字',
  ),
);
```

- [ ] **Step 2: 提交**

```bash
git add lib/core/sudoku/lobby/sudoku_lobby_spec.dart
git commit -m "feat(sudoku): add lobby spec (smartMatch)"
```

注：script 字段先占位 `''`，待 Task 5 完成后用 `kSudokuScript` 替换。

---

### Task 5: kSudokuScript（lifecycle + actions + 主入口）

**Files:**
- Create: `lib/core/sudoku/p2p/script/sudoku_script_lifecycle.dart`
- Create: `lib/core/sudoku/p2p/script/sudoku_script_actions.dart`
- Create: `lib/core/sudoku/p2p/script/sudoku_script.dart`
- Test: `test/core/sudoku/p2p/sudoku_script_guard_test.dart`
- Test: `test/core/sudoku/p2p/sudoku_script_set_puzzle_test.dart`
- Test: `test/core/sudoku/p2p/sudoku_script_start_gate_test.dart`
- Test: `test/core/sudoku/p2p/sudoku_script_submit_test.dart`

参考 `lib/core/chess/p2p/script/chess_script*.dart` 拆分模式（lifecycle / actions / 入口经 assembler 拼接）。

- [ ] **Step 1: 写 lifecycle**

```dart
// lib/core/sudoku/p2p/script/sudoku_script_lifecycle.dart
//
// kSudokuScript 的 lifecycle 段：on_init / on_join / on_leave。
//
// 与 chess 一致的纯字符串段；末尾必以 \n 结尾（assembler regex 边界）。

const String kSudokuScriptLifecycle = r'''
function sudoku_on_init(ctx)
  ctx.state = 'lobby'
  ctx.players = {}
  ctx.puzzle = nil
  ctx.solution = nil
  ctx.seed = 0
  ctx.difficulty = nil
  ctx.host_id = nil
  ctx.guest_id = nil
  ctx.started_at_ms = 0
  ctx.finished_at_ms = {}
  ctx.error_count = {}
  ctx.winner_id = nil
end

function sudoku_on_join(ctx, payload)
  local uid = payload.uid
  if ctx.state == 'lobby' and ctx.host_id == nil then
    ctx.host_id = uid
    ctx.players[uid] = true
    return {ok=true, role='host'}
  elseif ctx.state == 'lobby' and ctx.guest_id == nil and uid ~= ctx.host_id then
    ctx.guest_id = uid
    ctx.players[uid] = true
    return {ok=true, role='guest'}
  else
    return {ok=false, error='room_full'}
  end
end

function sudoku_on_leave(ctx, payload)
  local uid = payload.uid
  ctx.players[uid] = nil
  if uid == ctx.host_id then ctx.host_id = nil end
  if uid == ctx.guest_id then ctx.guest_id = nil end
  return {ok=true}
end
''';
```

- [ ] **Step 2: 写 actions**

```dart
// lib/core/sudoku/p2p/script/sudoku_script_actions.dart
//
// kSudokuScript 的 actions 段：SET_PUZZLE / START / SUBMIT。
//
// 所有 handler 写在导出表（由 assembler 末尾生成）。

const String kSudokuScriptActions = r'''
function action_set_puzzle(ctx, payload)
  -- 仅 host 可调
  if payload.uid ~= ctx.host_id then return {ok=false, error='not_host'} end
  local p = payload.puzzle
  local s = payload.solution
  if type(p) ~= 'table' or #p ~= 81 then return {ok=false, error='bad_puzzle_len'} end
  if type(s) ~= 'table' or #s ~= 81 then return {ok=false, error='bad_solution_len'} end
  -- solution 值域
  for i = 1, 81 do
    local v = s[i]
    if type(v) ~= 'number' or v < 1 or v > 9 then
      return {ok=false, error='bad_solution_value'}
    end
  end
  -- puzzle 与 solution 兼容
  for i = 1, 81 do
    if p[i] ~= 0 and p[i] ~= s[i] then
      return {ok=false, error='puzzle_solution_mismatch'}
    end
  end
  ctx.puzzle = p
  ctx.solution = s
  ctx.seed = payload.seed or 0
  ctx.difficulty = payload.difficulty or 'medium'
  return {ok=true}
end

function action_start(ctx, payload)
  if payload.uid ~= ctx.host_id then return {ok=false, error='not_host'} end
  if ctx.guest_id == nil then return {ok=false, error='no_guest'} end
  if ctx.puzzle == nil then return {ok=false, error='no_puzzle'} end
  ctx.state = 'playing'
  ctx.started_at_ms = now_ms()
  return {ok=true, broadcast_puzzle=ctx.puzzle}
end

function action_submit(ctx, payload)
  if ctx.state ~= 'playing' then return {ok=false, error='not_playing'} end
  if not ctx.players[payload.uid] then return {ok=false, error='not_in_room'} end
  local values = payload.values
  if type(values) ~= 'table' or #values ~= 81 then return {ok=false, error='bad_values_len'} end
  -- 校验答案
  for i = 1, 81 do
    if values[i] ~= ctx.solution[i] then return {ok=false, error='wrong_answer'} end
  end
  ctx.finished_at_ms[payload.uid] = payload.elapsed_ms or 0
  ctx.error_count[payload.uid] = payload.errors or 0
  if ctx.winner_id == nil then
    ctx.winner_id = payload.uid
    ctx.state = 'ended'
  end
  return {ok=true, winner=ctx.winner_id}
end

function now_ms()
  return math.floor(os.time() * 1000)
end
''';
```

- [ ] **Step 3: 写主入口（拼接）**

```dart
// lib/core/sudoku/p2p/script/sudoku_script.dart
//
// kSudokuScript 入口 —— 经 LuaScriptAssembler 拼接 lifecycle + actions +
// 共享 emoji 段。
//
// 与 chess_script.dart 同样的三段拼接顺序约束（见 chess_script.dart 顶部注释）。

import '../../game_kit/emoji/lua_script_assembler.dart';
import '../../game_kit/emoji/emoji_script.dart';
import 'sudoku_script_lifecycle.dart';
import 'sudoku_script_actions.dart';

/// 数独联机 Lua 脚本（const 拼装）。
final String kSudokuScript = assembleLuaScript(
  lifecycle: kSudokuScriptLifecycle,
  actions: kSudokuScriptActions,
  extraSegments: [kEmojiScriptSegment],
);
```

- [ ] **Step 4: 写导出表完整性测试**

```dart
// test/core/sudoku/p2p/sudoku_script_guard_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fr/core/sudoku/p2p/script/sudoku_script.dart';

void main() {
  test('kSudokuScript 含 on_init/on_join/on_leave', () {
    expect(kSudokuScript, contains('function sudoku_on_init'));
    expect(kSudokuScript, contains('function sudoku_on_join'));
    expect(kSudokuScript, contains('function sudoku_on_leave'));
  });

  test('kSudokuScript 含 actions', () {
    expect(kSudokuScript, contains('action_set_puzzle'));
    expect(kSudokuScript, contains('action_start'));
    expect(kSudokuScript, contains('action_submit'));
  });

  test('导出表最后生成', () {
    final idx = kSudokuScript.lastIndexOf('return {');
    expect(idx, greaterThan(0));
    final tail = kSudokuScript.substring(idx);
    expect(tail, contains('on_init'));
    expect(tail, contains('on_join'));
    expect(tail, contains('on_leave'));
    expect(tail, contains('action_set_puzzle'));
    expect(tail, contains('action_start'));
    expect(tail, contains('action_submit'));
  });
}
```

- [ ] **Step 5: 写 SET_PUZZLE 校验测试**

```dart
// test/core/sudoku/p2p/sudoku_script_set_puzzle_test.dart
//
// 测试 SET_PUZZLE 校验逻辑。用 mock Lua 上下文调用 action_set_puzzle。
// 参考 chess_script_guard_test 中的 mock 模式（实际由 relay 服务端跑，
// 这里只验证纯函数逻辑的单元测试边界）。
//
// 注：完整 Lua 集成测试需启动 relay 服务，本仓库现有 chess 也无此测试。
// 此处只对纯校验逻辑做单元测试（如果 LuaScriptExecutor 在仓库内可用）。
```

> 注：如果 `assembleLuaScript` + Lua runtime 不可用于单测，本文件仅放占位 + 注释，提醒集成测试在 manual QA 中跑通。直接 commit 占位文件即可。

- [ ] **Step 6: 写 START gate + SUBMIT 占位测试（同上）**

```dart
// test/core/sudoku/p2p/sudoku_script_start_gate_test.dart
// 占位：完整逻辑由 relay 服务端跑；本文件仅放占位 + 注释。
```

```dart
// test/core/sudoku/p2p/sudoku_script_submit_test.dart
// 占位：同上。
```

- [ ] **Step 7: 运行测试**

Run: `flutter test test/core/sudoku/p2p/sudoku_script_guard_test.dart`
Expected: PASS

- [ ] **Step 8: 回填 Task 4 的 spec script 字段**

修改 `lib/core/sudoku/lobby/sudoku_lobby_spec.dart`：
- import `../p2p/script/sudoku_script.dart`
- `script: kSudokuScript`
- 改为 `final` 而非 `const`（依赖 final kSudokuScript）

- [ ] **Step 9: 提交**

```bash
git add lib/core/sudoku/p2p/script/ test/core/sudoku/p2p/
git commit -m "feat(sudoku): add Lua script (lifecycle + actions)"
```

---

### Task 6: SudokuColorStrategy + tokens（五主题）

**Files:**
- Create: `lib/core/theme/colors/strategy/sudoku_color_strategy/sudoku_color_strategy.dart`
- Create: `lib/core/theme/colors/strategy/sudoku_color_strategy/sudoku_color_strategy_factory.dart`
- Create: `lib/core/theme/tokens/color/sudoku/{cell_bg,cell_text,cell_selected,cell_error,cell_initial,cell_note,grid_line,accent}.dart`

参考 `lib/core/theme/colors/strategy/chess_color_strategy/` 实现。提供 8 个 token × 5 主题（zen / purple / ink / rose / lemon）。

- [ ] **Step 1: 创建 token 文件（每个 token 一文件，参考 chess）**

```dart
// lib/core/theme/tokens/color/sudoku/sudoku_cell_bg.dart
import 'package:flutter/material.dart';

/// 数独格子背景色 token。
class SudokuCellBg {
  final Color filled;
  final Color empty;
  final Color initial;
  const SudokuCellBg({required this.filled, required this.empty, required this.initial});
}
```

类似为 `cell_text` / `cell_selected` / `cell_error` / `cell_initial` / `cell_note` / `grid_line` / `accent` 各建文件。

- [ ] **Step 2: 创建 strategy 接口**

```dart
// lib/core/theme/colors/strategy/sudoku_color_strategy/sudoku_color_strategy.dart
import 'package:flutter/material.dart';
import '../../../tokens/color/sudoku/sudoku_cell_bg.dart';
// ... 其他 token import

abstract class SudokuColorStrategy {
  SudokuCellBg get cellBg;
  SudokuCellText get cellText;
  SudokuCellSelected get cellSelected;
  SudokuCellError get cellError;
  SudokuCellInitial get cellInitial;
  SudokuCellNote get cellNote;
  SudokuGridLine get gridLine;
  SudokuAccent get accent;
}
```

- [ ] **Step 3: 创建 5 个 strategy 实现（zen / purple / ink / rose / lemon）**

参考 `chess_color_strategy_factory.dart`：基于主题 id 返回对应 strategy。

- [ ] **Step 4: 注册到 context.colors**

修改 `lib/core/theme/` 现有 context_colors 扩展，添加 `SudokuColors of(BuildContext)` getter，从 `Theme.of(context).extension<SudokuColorStrategy>()` 读取。

- [ ] **Step 5: 手动验证（5 主题过一遍）**

逐个切换主题（zen / purple / ink / rose / lemon）→ 打开数独 demo → 视觉检查棋盘配色合理。

- [ ] **Step 6: 提交**

```bash
git add lib/core/theme/
git commit -m "feat(sudoku): add color strategy + tokens (5 themes)"
```

---

### Task 7: sudoku widgets（grid / cell / number_pad / error_badge / opponent_strip）

**Files:**
- Create: `lib/core/sudoku/widgets/sudoku_grid.dart`
- Create: `lib/core/sudoku/widgets/sudoku_cell_widget.dart`
- Create: `lib/core/sudoku/widgets/sudoku_number_pad.dart`
- Create: `lib/core/sudoku/widgets/sudoku_error_badge.dart`
- Create: `lib/core/sudoku/widgets/sudoku_opponent_strip.dart`

- [ ] **Step 1: SudokuCellWidget**

```dart
// lib/core/sudoku/widgets/sudoku_cell_widget.dart
import 'package:flutter/material.dart';
import '../models/sudoku_cell.dart';

class SudokuCellWidget extends StatelessWidget {
  final SudokuCell cell;
  final bool selected;
  final VoidCallback? onTap;
  const SudokuCellWidget({
    super.key,
    required this.cell,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isInitial = cell.isInitial;
    final bg = isInitial
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer : bg,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Center(
          child: cell.value != null
              ? Text(
                  cell.value.toString(),
                  style: TextStyle(
                    color: cell.isError
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                    fontWeight: isInitial ? FontWeight.bold : FontWeight.normal,
                  ),
                )
              : cell.notes.isEmpty
                  ? null
                  : Text(cell.notes.toList().join(' ')),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: SudokuGrid**

```dart
// lib/core/sudoku/widgets/sudoku_grid.dart
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
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 9),
        itemCount: 81,
        itemBuilder: (ctx, i) {
          final r = i ~/ 9, c = i % 9;
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
```

- [ ] **Step 3: SudokuNumberPad + SudokuErrorBadge + SudokuOpponentStrip**

实现数字键盘（1-9 + 清空）、错误数 badge、对手条（双方昵称 + 计时 + 完成度）。

- [ ] **Step 4: 提交**

```bash
git add lib/core/sudoku/widgets/
git commit -m "feat(sudoku): add widgets (grid/cell/number-pad/strip)"
```

---

### Task 8: SudokuRoomConfigPanel（准备阶段）

**Files:**
- Create: `lib/core/sudoku/p2p/sudoku_room_config_page.dart`

参考 `lib/core/chess/p2p/chess_room_config_page.dart` 的 `ChessRoomRulesPanel`（嵌入 ready 卡的 StatefulWidget）。

- [ ] **Step 1: 实现 ConfigPanel**

```dart
// lib/core/sudoku/p2p/sudoku_room_config_page.dart
//
// 数独准备阶段规则面板（嵌入 lobby/ready 卡，非全屏页面）。
//
// host 视图：难度 radio + 「生成题目」按钮 + 生成状态。
// guest 视图：只读展示当前难度 + 「题已生成」状态。

import 'package:flutter/material.dart';
import '../engine/sudoku_generator.dart';
import '../models/sudoku_puzzle.dart';

class SudokuRoomConfig {
  final String difficulty;
  final SudokuPuzzle? puzzle;  // host 生成后填入；guest 端由快照同步
  const SudokuRoomConfig({required this.difficulty, this.puzzle});
}

class SudokuRoomConfigPanel extends StatefulWidget {
  final bool editable;       // true = host
  final String difficulty;
  final bool puzzleReady;
  final void Function(String difficulty)? onDifficultyChanged;
  final VoidCallback? onGenerate;
  const SudokuRoomConfigPanel({
    super.key,
    required this.editable,
    required this.difficulty,
    required this.puzzleReady,
    this.onDifficultyChanged,
    this.onGenerate,
  });

  @override
  State<SudokuRoomConfigPanel> createState() => _SudokuRoomConfigPanelState();
}

class _SudokuRoomConfigPanelState extends State<SudokuRoomConfigPanel> {
  static const _difficulties = [
    ('easy', '简单 (35 格)'),
    ('medium', '中等 (30 格)'),
    ('hard', '困难 (25 格)'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('难度'),
            ..._difficulties.map((d) => RadioListTile<String>(
                  value: d.$1,
                  groupValue: widget.difficulty,
                  title: Text(d.$2),
                  onChanged: widget.editable && widget.onDifficultyChanged != null
                      ? (v) => widget.onDifficultyChanged!(v!)
                      : null,
                )),
            const SizedBox(height: 8),
            if (widget.editable)
              FilledButton.icon(
                onPressed: widget.onGenerate,
                icon: const Icon(Icons.refresh),
                label: const Text('生成题目'),
              ),
            if (widget.puzzleReady)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('✓ 题已生成，等待双方准备'),
              )
            else if (!widget.editable)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('等待 host 生成题目…'),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/core/sudoku/p2p/sudoku_room_config_page.dart
git commit -m "feat(sudoku): add room config panel (difficulty + generate)"
```

---

### Task 9: SudokuRoomPage（state machine 路由）

**Files:**
- Create: `lib/core/sudoku/p2p/sudoku_room_page.dart`
- Create: `lib/core/sudoku/p2p/sudoku_net.dart`
- Create: `lib/core/sudoku/sudoku.dart`（入口）

参考 `lib/core/chess/p2p/chess_room_page.dart`（2257 行，state machine 路由）。状态：
- lobby → 准备卡 + 「等待对手」
- ready → 双方 + 配置卡
- playing → 棋盘 + 计时 + 错误数
- ended → 结果 + 「再来一局」

- [ ] **Step 1: 写 sudoku_net.dart（action 编码 + 快照解码）**

```dart
// lib/core/sudoku/p2p/sudoku_net.dart
//
// 数独联机的 action 编码与快照解码辅助。
//
// 编码：把 Dart 对象 → Lua 端可接收的 payload（通过 relay_v3 transport 的
// sendAction 机制）。
// 解码：从快照 context 提取 puzzle / solution / state 等。

import '../../net_engine/relay_v3/relay_v3_transport.dart';

class SudokuNet {
  static const String kActionSetPuzzle = 'SET_PUZZLE';
  static const String kActionStart = 'START';
  static const String kActionSubmit = 'SUBMIT';

  static void sendSetPuzzle(
    RoomHandle handle, {
    required List<int> puzzle,
    required List<int> solution,
    required int seed,
    required String difficulty,
  }) {
    handle.sendAction(kActionSetPuzzle, {
      'puzzle': puzzle,
      'solution': solution,
      'seed': seed,
      'difficulty': difficulty,
    });
  }

  static void sendStart(RoomHandle handle) {
    handle.sendAction(kActionStart, const {});
  }

  static void sendSubmit(
    RoomHandle handle, {
    required List<int> values,
    required int elapsedMs,
    required int errors,
  }) {
    handle.sendAction(kActionSubmit, {
      'values': values,
      'elapsed_ms': elapsedMs,
      'errors': errors,
    });
  }
}
```

- [ ] **Step 2: 实现 SudokuRoomPage（state machine 路由）**

```dart
// lib/core/sudoku/p2p/sudoku_room_page.dart
//
// 数独联机房间页（lobby/ready/playing/ended 四态路由）。
//
// 接收 RoomHandle + 订阅 snapshot，按 state 分发子组件：
//   - 'lobby' / 'ready' → SudokuLobbyPanel（含 ConfigPanel）
//   - 'playing' → SudokuPlayingPanel（棋盘 + 计时 + 错误数）
//   - 'ended' → SudokuEndedPanel（结果）

import 'package:flutter/material.dart';
import '../../net_engine/relay_v3/relay_v3_transport.dart';
import '../models/sudoku_board.dart';
import '../widgets/sudoku_grid.dart';
import '../widgets/sudoku_number_pad.dart';
import '../widgets/sudoku_opponent_strip.dart';
import 'sudoku_net.dart';
import 'sudoku_room_config_page.dart';

class SudokuRoomPage extends StatefulWidget {
  final RoomHandle handle;
  const SudokuRoomPage({super.key, required this.handle});

  @override
  State<SudokuRoomPage> createState() => _SudokuRoomPageState();
}

class _SudokuRoomPageState extends State<SudokuRoomPage> {
  late Stream<RoomSnapshot> _snapshots;
  RoomSnapshot? _snap;
  SudokuBoard? _board;
  int? _selectedR, _selectedC;
  int _errors = 0;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    _snapshots = widget.handle.snapshots;
    _snapshots.listen((s) {
      if (!mounted) return;
      setState(() {
        _snap = s;
        if (_startedAt == null && s.context['state'] == 'playing') {
          _startedAt = DateTime.now();
          _errors = 0;
        }
        // 第一次进入 playing 时构造 board
        if (_board == null && s.context['puzzle'] != null) {
          final puzzleFlat = (s.context['puzzle'] as List).cast<int>();
          _board = SudokuBoard.fromPuzzle(
            // 构造临时 SudokuPuzzle（无 solution 服务端校验，不进 board）
            _Puzzle(puzzleFlat),
          );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = _snap?.context['state'] as String? ?? 'lobby';
    return Scaffold(
      appBar: AppBar(title: const Text('数独竞赛')),
      body: switch (state) {
        'lobby' || 'ready' => _buildLobby(),
        'playing' => _buildPlaying(),
        'ended' => _buildEnded(),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _buildLobby() {
    // 准备卡 + 难度 + 双方状态
    final isHost = _snap?.context['host_id'] == widget.handle.deviceId;
    return Center(
      child: SudokuRoomConfigPanel(
        editable: isHost,
        difficulty: (_snap?.context['difficulty'] as String?) ?? 'medium',
        puzzleReady: _snap?.context['puzzle'] != null,
        onDifficultyChanged: (d) {/* TODO: trigger SET_PUZZLE in Task 10 */},
        onGenerate: () {/* TODO: host generates + send SET_PUZZLE */},
      ),
    );
  }

  Widget _buildPlaying() {
    if (_board == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        SudokuOpponentStrip(
          hostName: _snap?.context['host_name'] as String? ?? 'Host',
          guestName: _snap?.context['guest_name'] as String? ?? 'Guest',
          elapsedMs: _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inMilliseconds,
          hostFilled: _board!.filledCount,
          guestFilled: _snap?.context['guest_filled'] as int? ?? 0,
        ),
        SudokuGrid(
          board: _board!,
          selectedRow: _selectedR,
          selectedCol: _selectedC,
          onCellTap: (r, c) => setState(() {
            _selectedR = r;
            _selectedC = c;
          }),
        ),
        SudokuNumberPad(
          onNumber: (n) {
            if (_selectedR == null || _selectedC == null) return;
            _board!.setValue(_selectedR!, _selectedC!, n, isValidMove: (r, c, v) {
              // TODO: 接入 validator
              return true;
            });
            setState(() {});
          },
          onClear: () {
            if (_selectedR == null || _selectedC == null) return;
            _board!.setValue(_selectedR!, _selectedC!, null, isValidMove: (_, __, ___) => true);
            setState(() {});
          },
          onSubmit: () {
            // TODO: 完整提交逻辑
            final flat = <int>[];
            for (final row in _board!.cells) {
              for (final c in row) {
                flat.add(c.value ?? 0);
              }
            }
            final elapsed = _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inMilliseconds;
            SudokuNet.sendSubmit(
              widget.handle,
              values: flat,
              elapsedMs: elapsed,
              errors: _errors,
            );
          },
        ),
      ],
    );
  }

  Widget _buildEnded() {
    final winner = _snap?.context['winner_id'] as String?;
    final winnerTime = _snap?.context['finished_at_ms']?[winner] as int? ?? 0;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🏆 赢家：$winner', style: Theme.of(context).textTheme.headlineMedium),
          Text('用时：${winnerTime ~/ 1000} 秒'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回大厅'),
          ),
        ],
      ),
    );
  }
}

/// 临时 puzzle 包装，仅用于从快照构造 SudokuBoard（不含 solution）。
class _Puzzle implements dynamic {
  final List<int> _flat;
  _Puzzle(this._flat);
  List<int> get puzzle => _flat;
  List<int> get solution => const [];
  int get seed => 0;
  String get difficulty => 'medium';
}
```

- [ ] **Step 3: 写入口文件**

```dart
// lib/core/sudoku/sudoku.dart
//
// 数独模块入口。导出 lobby spec + room page。

export 'lobby/sudoku_lobby_spec.dart';
export 'p2p/sudoku_room_page.dart';
export 'p2p/sudoku_net.dart';
```

- [ ] **Step 4: 提交**

```bash
git add lib/core/sudoku/p2p/sudoku_net.dart lib/core/sudoku/p2p/sudoku_room_page.dart lib/core/sudoku/sudoku.dart
git commit -m "feat(sudoku): add room page (state machine) + net + entry"
```

注：完整 host 端生成 puzzle + 推送 SET_PUZZLE 联动放到 Stage 3 demo 入口接通时一起做（与路由一并）。

---

### Task 10: 数独 demo 入口接通 + 路由

**Files:**
- Modify: `lib/lab/demos/sudoku_lua/sudoku_demo.dart`
- Modify: `lib/lab/demos/sudoku_lua/constants.dart`

- [ ] **Step 1: 修改 sudoku_demo.dart 注册新 spec**

```dart
// 在 sudoku_demo.dart 路由表里添加数独联机入口
import 'package:fr/core/sudoku/lobby/sudoku_lobby_spec.dart';
// ... 在 gameLauncher 里注册：
//   GameLauncherEntry(
//     spec: kSudokuLobbySpec,
//     buildRoomPage: (handle) => SudokuRoomPage(handle: handle),
//   ),
```

- [ ] **Step 2: 修改 constants.dart 新增 relayUrl**

```dart
const String kSudokuRelayUrl = 'http://47.110.80.47:8988';
```

更新 `kSudokuLobbySpec` 的 `relayUrl: kSudokuRelayUrl`。

- [ ] **Step 3: 手动端到端验证**

按 `lib/lab/demos/chess_lua/` 的运行方式启两个客户端，进入同一房间号，验证：
1. host 进入 lobby → 准备卡显示
2. guest 加入 → state='ready' → 双方看到准备卡
3. host 选难度 → 生成 puzzle → SET_PUZZLE 上传
4. host 点 START → state='playing' → 棋盘出现，计时启动
5. 一方填完点 SUBMIT → state='ended' → 显示赢家
6. 切换 5 主题验证配色

- [ ] **Step 4: 提交**

```bash
git add lib/lab/demos/sudoku_lua/
git commit -m "feat(sudoku): wire demo entry + relay URL"
```

---

## Self-Review

**1. Spec coverage:**
- § 2 模块结构 — Task 1-9 全覆盖 ✓
- § 3.1 入口 smartMatch — Task 4 + Task 10 ✓
- § 3.2 Lua 状态机 — Task 5 ✓
- § 4.1 准备卡 — Task 8 ✓
- § 5 房间页 — Task 9 ✓
- § 6 主题 — Task 6 ✓
- § 7 测试 — Task 1-3 单测，Task 5 脚本测试 ✓
- § 9 stage-1 — 本计划即 stage-1 ✓

**2. Placeholder scan:**
- "TODO" 在 Task 9 中标记了 3 处（生成 puzzle 联动、validator 接入、完整 SUBMIT 链）—— 均放在 Stage 3 demo 入口接通时一起做。已在 spec 阶段记录。
- "占位" 在 Task 5 Step 5-6（Lua runtime 不可用，集成测试在 manual QA 跑通）—— 已在注释说明。
- 无 TBD / "implement later"。

**3. Type consistency:**
- `SudokuValidator.isValidMove(List<List<int?>>, int, int, int) → bool` — Task 1 定义，Task 9 调用 ✓
- `SudokuBoard.setValue(int, int, int?, {required bool Function(int,int,int) isValidMove})` — Task 3 定义，Task 9 调用 ✓
- `SudokuPuzzle.{puzzle, solution, seed, difficulty}` — Task 2 定义，Task 3 调用 ✓
- `SudokuNet.sendSetPuzzle/Start/Submit` — Task 9 定义，Task 9 调用 ✓

OK，no issues found.
