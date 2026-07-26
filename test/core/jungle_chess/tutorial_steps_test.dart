// 教程数据与引擎的一致性校验。
//
// 教程是在真实引擎上跑出来的：每一章的演示走法必须真的合法，标了 blocked 的
// 反例必须真的不合法。这个测试就是防止两边漂移 —— 改了引擎规则而教程没跟上时，
// 这里先红，而不是等用户在教程里看到一个走不动的棋子。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/engine/jungle_engine.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/models/game_state.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/models/piece.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/tutorial/tutorial_steps.dart';

void main() {
  group('教程章节', () {
    test('每章的棋子 key（颜色_动物）唯一 —— 否则位移动画会串', () {
      for (final ch in kTutorialChapters) {
        final setup = ch.setup;
        if (setup == null) continue;
        final keys = setup.map((p) => '${p.color.name}_${p.animal.name}');
        expect(
          keys.toSet().length,
          setup.length,
          reason: '「${ch.title}」摆了同色同动物的重复棋子',
        );
      }
    });

    test('每章双方都有棋子，演示不会一开局就判负', () {
      for (final ch in kTutorialChapters) {
        final s = ch.initialState();
        final colors = s.pieces.values.map((p) => p.color).toSet();
        expect(
          colors.length,
          2,
          reason: '「${ch.title}」缺少某一方的棋子',
        );
      }
    });

    test('普通走法都合法、blocked 走法都确实不合法', () {
      for (final ch in kTutorialChapters) {
        var s = ch.initialState();
        for (var i = 0; i < ch.moves.length; i++) {
          final m = ch.moves[i];
          final label = '「${ch.title}」第 ${i + 1} 步（${m.caption}）';
          final next = JungleEngine.movePiece(s, m.from, m.to);

          if (m.blocked) {
            expect(next, isNull, reason: '$label 标了 blocked，但引擎认为它合法');
          } else {
            expect(next, isNotNull, reason: '$label 在引擎里走不通');
            s = next!;
          }
        }
      }
    });

    test('入穴取胜章最后一步真的判出胜负', () {
      final ch = kTutorialChapters.firstWhere((c) => c.title == '入穴取胜');
      var s = ch.initialState();
      for (final m in ch.moves) {
        if (m.blocked) continue;
        s = JungleEngine.movePiece(s, m.from, m.to)!;
      }
      expect(s.isOver, isTrue);
      expect(s.winner, PlayerColor.blue);
    });
  });

  group('鼠与河（引擎规则）', () {
    test('鼠可以从陆地进河、也能从河里上岸', () {
      final s = GameState(
        pieces: {
          43: const Piece(
              animal: Animal.rat,
              color: PlayerColor.blue,
              position: (row: 6, col: 1)),
          15: const Piece(
              animal: Animal.rat,
              color: PlayerColor.red,
              position: (row: 2, col: 1)),
        },
        currentTurn: PlayerColor.blue,
      );
      // 下水：(6,1) → (5,1) 是河
      final inWater = JungleEngine.movePiece(s, (row: 6, col: 1), (row: 5, col: 1));
      expect(inWater, isNotNull);

      // 上岸：让红方走一步后，蓝鼠从 (5,1) 回到 (6,1)
      final redMoved =
          JungleEngine.movePiece(inWater!, (row: 2, col: 1), (row: 2, col: 0));
      final onLand =
          JungleEngine.movePiece(redMoved!, (row: 5, col: 1), (row: 6, col: 1));
      expect(onLand, isNotNull);
    });

    test('水里的鼠吃不到岸上的棋子', () {
      final s = GameState(
        pieces: {
          36: const Piece(
              animal: Animal.rat,
              color: PlayerColor.blue,
              position: (row: 5, col: 1)), // 河
          35: const Piece(
              animal: Animal.dog,
              color: PlayerColor.red,
              position: (row: 5, col: 0)), // 岸
        },
        currentTurn: PlayerColor.blue,
      );
      expect(
        JungleEngine.movePiece(s, (row: 5, col: 1), (row: 5, col: 0)),
        isNull,
      );
    });

    test('河中有鼠时狮跳不过去，鼠让开后能跳', () {
      GameState build({required bool ratInPath}) => GameState(
            pieces: {
              43: const Piece(
                  animal: Animal.lion,
                  color: PlayerColor.blue,
                  position: (row: 6, col: 1)),
              if (ratInPath)
                29: const Piece(
                    animal: Animal.rat,
                    color: PlayerColor.blue,
                    position: (row: 4, col: 1))
              else
                30: const Piece(
                    animal: Animal.rat,
                    color: PlayerColor.blue,
                    position: (row: 4, col: 2)),
              17: const Piece(
                  animal: Animal.wolf,
                  color: PlayerColor.red,
                  position: (row: 2, col: 3)),
            },
            currentTurn: PlayerColor.blue,
          );

      expect(
        JungleEngine.movePiece(
            build(ratInPath: true), (row: 6, col: 1), (row: 2, col: 1)),
        isNull,
        reason: '水路上有鼠，狮不该跳得过去',
      );
      expect(
        JungleEngine.movePiece(
            build(ratInPath: false), (row: 6, col: 1), (row: 2, col: 1)),
        isNotNull,
        reason: '水路清空后狮应该能跳',
      );
    });
  });
}
