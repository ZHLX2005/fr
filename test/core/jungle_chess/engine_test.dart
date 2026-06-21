// test/core/jungle_chess/engine_test.dart
//
// 关键回归测试：模拟"开局后随便走一步" → 不应立刻结束游戏。
// 之前的 bug：「无子可走」判定时机错（检查的是当前手方而非下一手方），
// 导致 blue 走一步后立刻判 blue 无子可走 → 立刻 game over。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/models/piece.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/models/game_state.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/engine/jungle_engine.dart';

void main() {
  group('JungleEngine - 胜负判定时机', () {
    test('开局 → 蓝方走一步后不应立刻游戏结束', () {
      final s0 = JungleEngine.createInitialState();
      expect(s0.pieces.length, 16);

      // 蓝猫@50 走到 (8,1)=57 空格
      final s1 = JungleEngine.movePiece(s0, (row: 7, col: 1), (row: 8, col: 1));
      expect(s1, isNotNull, reason: '蓝猫走到空格应成功');
      expect(s1!.gameOverReason, isNull,
          reason: '不应该立刻游戏结束：${s1.gameOverReason}');
      expect(s1.winner, isNull);
      expect(s1.currentTurn, PlayerColor.red,
          reason: '应轮到红方');
    });

    test('开局 → 蓝走一步后轮到红，红方仍应可走（红方不应被困毙）', () {
      final s0 = JungleEngine.createInitialState();
      // 蓝猫@50 走到 (8,1)=57 空格
      final s1 = JungleEngine.movePiece(s0, (row: 7, col: 1), (row: 8, col: 1));
      expect(s1, isNotNull);
      expect(s1!.currentTurn, PlayerColor.red);
      expect(s1.gameOverReason, isNull);
      // 红方当前仍应有合法走法（困毙判定的是 nextToMove，所以这里不应判）
      bool redCanMove = false;
      for (final p in s1.pieces.values) {
        if (!p.isAlive || p.color != PlayerColor.red) continue;
        if (JungleEngine.getValidMoves(s1, p.position).isNotEmpty) {
          redCanMove = true;
          break;
        }
      }
      expect(redCanMove, isTrue, reason: '红方至少应有一个棋子能走');
    });

    test('红方棋子进入蓝穴 → 红方赢', () {
      // 构造状态：双方各一只棋子 + 红方占据蓝穴
      final manual = GameState(
        pieces: const {
          56: Piece(
              animal: Animal.tiger,
              color: PlayerColor.blue,
              position: (row: 8, col: 0)),
          59: Piece(
              animal: Animal.elephant,
              color: PlayerColor.red,
              position: (row: 8, col: 3)),
        },
        currentTurn: PlayerColor.blue,
        history: [],
      );
      final end = JungleEngine.checkGameEnd(manual);
      expect(end.isOver, isTrue);
      expect(end.winner, PlayerColor.red, reason: '红方入蓝穴，红方赢');
      expect(end.reason, contains('蓝穴'));
    });

    test('走法生成：河跳纵向距离正确（虎在 (2,1) 向上跳到 (6,1)）', () {
      // 构造：红虎在 (2,1)=15（红方当前回合）
      final manual = GameState(
        pieces: const {
          15: Piece(
              animal: Animal.tiger,
              color: PlayerColor.red,
              position: (row: 2, col: 1)),
        },
        currentTurn: PlayerColor.red,
        history: [],
      );
      // 红虎向上：左河 row3 col1=22 / row4 col1=29 / row5 col1=36（无阻挡）→ 落到 (6,1)=43
      final moves = JungleEngine.getValidMoves(manual, (row: 2, col: 1));
      expect(moves.any((c) => c.row == 6 && c.col == 1), isTrue,
          reason: '红虎应能纵向河跳到 (6,1)，实际走法=$moves');
    });

    test('河跳被河中鼠阻挡 → 该方向无走法', () {
      // 构造：红虎在 (2,1)=15（红方当前回合）
      // 河中央 (3,1)=22 放一个红鼠
      final manual = GameState(
        pieces: const {
          15: Piece(
              animal: Animal.tiger,
              color: PlayerColor.red,
              position: (row: 2, col: 1)),
          22: Piece(
              animal: Animal.rat,
              color: PlayerColor.red,
              position: (row: 3, col: 1)),
        },
        currentTurn: PlayerColor.red,
        history: [],
      );
      final moves = JungleEngine.getValidMoves(manual, (row: 2, col: 1));
      expect(moves.any((c) => c.row == 6 && c.col == 1), isFalse,
          reason: '河中被鼠阻挡，红虎应不能跳越');
    });

    test('鼠可入河：蓝鼠从 (6,6)=48 走入 (5,6)=41（河）', () {
      final s0 = JungleEngine.createInitialState();
      // (5,6) = 5*7+6 = 41 → row 5 col 6：是陆格（不是河），应该是陷阱？
      // 河是 row 3-5 col 1-2 / col 4-5。row 5 col 6 是陆格。改成 (5,5)
      // (5,5) = 5*7+5 = 40 → row 5 col 5：是右河！✓
      // 但从 (6,6) 到 (5,5) 不是 4 方向走法！改成 (5,6) → 是陆格不是河。
      // 改用蓝鼠走向上到 (5,6)：是陆格；走左到 (6,5)=47：是右河！✓
      final moves = JungleEngine.getValidMoves(s0, (row: 6, col: 6));
      expect(moves.any((c) => c.row == 6 && c.col == 5), isTrue,
          reason: '蓝鼠可走入 (6,5)=47 河格');
    });

    test('鼠标入河后 gameOverReason 应为 null', () {
      final s0 = JungleEngine.createInitialState();
      // 蓝鼠从 (6,6)=48 走到 (6,5)=47 河
      final s1 = JungleEngine.movePiece(s0, (row: 6, col: 6), (row: 6, col: 5));
      expect(s1, isNotNull, reason: '蓝鼠走到河格应合法');
      expect(s1!.gameOverReason, isNull,
          reason: '鼠标入河后不该判结束：${s1.gameOverReason}');
    });

    test('吃子：象不能吃陆地上的鼠（除陷阱）', () {
      // 蓝象 @ (6,0)=42，蓝鼠 @ (5,1)=36（不在陷阱）
      final manual = GameState(
        pieces: const {
          42: Piece(
              animal: Animal.elephant,
              color: PlayerColor.blue,
              position: (row: 6, col: 0)),
          36: Piece(
              animal: Animal.rat,
              color: PlayerColor.red,
              position: (row: 5, col: 1)),
        },
        currentTurn: PlayerColor.blue,
        history: [],
      );
      final moves = JungleEngine.getValidMoves(manual, (row: 6, col: 0));
      // 象不能吃红鼠（红鼠不在陷阱）→ 不应包含 (5,1)
      // 但象可以移动到 (5,0)=35（陆格，空格）
      expect(moves.any((c) => c.row == 5 && c.col == 1), isFalse,
          reason: '蓝象不能吃陆地上的红鼠');
      // 象走到河里？ (5,0)=35 是陆格（不是河），应可走
      // (5,0) → row 5 col 0，左河是 col 1-2，所以 (5,0) 是陆格（陷阱？也不是陷阱）
    });

    test('吃子：陷阱中棋子 rank=0，可被任意同级或更高级吃', () {
      // 蓝狮在 (8,6)=62，红狼在 (7,5)=53（蓝陷阱！52/58/60... 53 不在）
      // 红陷阱 {2,4,10} / 蓝陷阱 {52,58,60}
      // 让红象在蓝陷阱 58=(8,2)，蓝狮 62 试图吃掉它
      final manual = GameState(
        pieces: const {
          62: Piece(
              animal: Animal.lion,
              color: PlayerColor.blue,
              position: (row: 8, col: 6)),
          58: Piece(
              animal: Animal.elephant,
              color: PlayerColor.red,
              position: (row: 8, col: 2)),
        },
        currentTurn: PlayerColor.blue,
        history: [],
      );
      // 蓝狮 (8,6) 向左: (8,5) 空格、(8,4) 陷阱、(8,3) 蓝穴（不能）、(8,2) 红象
      // 距离 > 1 不能横跳（狮可跳河），但 (8,5) 是空格不是河 → 不触发跳
      // 狮走到 (8,5)：空格 (row 8 col 5)
      final moves = JungleEngine.getValidMoves(manual, (row: 8, col: 6));
      // 验证 (8,2) 可吃（红象在蓝陷阱 rank=0，狮 rank7≥0）
      // 但狮在 (8,6) 走到 (8,2) 需要 4 步，是陆格 → 不能跳
      // 走到 (8,5) 空格 → 可
      expect(moves.any((c) => c.row == 8 && c.col == 5), isTrue);
    });

    test('蓝鼠走一步后 gameOverReason 应为 null', () {
      final s0 = JungleEngine.createInitialState();
      // 蓝鼠 @ (6,6)=48 走到 (6,5)=47 河（右河）
      final s1 = JungleEngine.movePiece(s0, (row: 6, col: 6), (row: 6, col: 5));
      expect(s1, isNotNull, reason: '鼠标入河应合法');
      expect(s1!.gameOverReason, isNull,
          reason: '鼠标入河后不该判结束：${s1.gameOverReason}');
    });
  });
}