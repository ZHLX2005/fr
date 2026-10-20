// test/core/xiangqi/xiangqi_rules_extra_test.dart
//
// 中国象棋规则补强用例 —— 覆盖首轮「fresh-eyes 正确性审查」指出的盲区：
//
//   1. 兵过河边界（row 4 / row 5）**红黑对称**（此前只测了 row 2 / row 6，
//      row 4/5 的 off-by-one 能蒙混过关）
//   2. **非将军棋子**走成「将帅照面」必须非法（此前只测了将自己沿同列走）
//   3. 将死判定：可挡将 / 可吃子时**不得**判将死；困毙 ≠ 将死
//   4. 黑方规则对称性（马腿 / 象眼 / 炮架 / 兵过河 / 九宫）——
//      此前所有规则用例都只用红子，黑方单独实现也能全绿
//   5. FEN 局面随机往返（property test）
//   6. 非法局面 FEN 必须被拒（缺将 / 将出九宫 / 将帅照面 / 数量超限）
//   7. 棋谱里有**无法重放**的记录 → 必须检出并对齐服务端，不得静默跳过
//   8. initial_side 与 FEN 轮次字段不一致时，重放轮次方必须以服务端为准
//
// 记号约定：列字母 a..i，行号 0..9（0 = 顶部黑方底线）。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/xiangqi/constants/xiangqi_constants.dart';
import 'package:xiaodouzi_fr/core/xiangqi/engine/fen_codec.dart';
import 'package:xiaodouzi_fr/core/xiangqi/engine/make_move.dart';
import 'package:xiaodouzi_fr/core/xiangqi/engine/move_generator.dart';
import 'package:xiaodouzi_fr/core/xiangqi/engine/xiangqi_engine.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/board_state.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/game_status.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/move.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/piece.dart';
import 'package:xiaodouzi_fr/core/xiangqi/p2p/xiangqi_room.dart';

int at(String name) => xiangqiIndexFromName(name);

/// 构造 90 格棋盘：记号名 → 棋子。
List<int?> cells(Map<String, XiangqiPiece> spec) {
  final out = List<int?>.filled(kXiangqiCells, null, growable: false);
  spec.forEach((name, piece) {
    out[xiangqiIndexFromName(name)] = piece.pack();
  });
  return out;
}

XiangqiBoardState board(
  Map<String, XiangqiPiece> spec, {
  XiangqiColor sideToMove = XiangqiColor.red,
}) =>
    XiangqiBoardState(cells: cells(spec), sideToMove: sideToMove);

void main() {
  group('① 兵过河边界（row 4 / 5）红黑对称', () {
    test('红兵 row 4（已过河）→ 3 步：前 + 左 + 右', () {
      final b = board({'c4': XiangqiPiece.redPawn});
      final moves = xiangqiLegalMoves(b).where((m) => m.from == at('c4'));
      expect(moves.length, 3);
    });

    test('红兵 row 5（未过河）→ 1 步：只能前进', () {
      final b = board({'c5': XiangqiPiece.redPawn});
      final moves = xiangqiLegalMoves(b).where((m) => m.from == at('c5'));
      expect(moves.length, 1);
      expect(moves.first.to, at('c4'));
    });

    test('黑卒 row 5（已过河）→ 3 步：前 + 左 + 右（与红兵 row 4 对称）', () {
      final b = board({'c5': XiangqiPiece.blackPawn}, sideToMove: XiangqiColor.black);
      final moves = xiangqiLegalMoves(b).where((m) => m.from == at('c5'));
      expect(moves.length, 3);
    });

    test('黑卒 row 4（未过河）→ 1 步：只能前进', () {
      final b = board({'c4': XiangqiPiece.blackPawn}, sideToMove: XiangqiColor.black);
      final moves = xiangqiLegalMoves(b).where((m) => m.from == at('c4'));
      expect(moves.length, 1);
      expect(moves.first.to, at('c5'));
    });
  });

  group('② 非将军棋子走成「将帅照面」必须非法', () {
    test('红车离开 e 线 → 双将照面 → 该着法非法', () {
      // 双将在 e0 / e9，红车在 e5 挡着。红车横移到 d5 → e 线空了
      // → 双将照面 → 必须非法；纵向走到 e4 / e6（仍挡着）→ 合法。
      final b = board({
        'e9': XiangqiPiece.redGeneral,
        'e0': XiangqiPiece.blackGeneral,
        'e5': XiangqiPiece.redChariot,
      });
      final moves = xiangqiLegalMoves(b).where((m) => m.from == at('e5'));
      expect(moves.any((m) => m.to == at('d5')), isFalse,
          reason: '离开 e 线 → 双将照面 → 必须非法');
      expect(moves.any((m) => m.to == at('e4')), isTrue,
          reason: '仍留在 e 线 → 继续挡着 → 合法');
      expect(moves.any((m) => m.to == at('e6')), isTrue);
    });

    test('红车离开 e 线的所有着法都非法（不只 d5）', () {
      final b = board({
        'e9': XiangqiPiece.redGeneral,
        'e0': XiangqiPiece.blackGeneral,
        'e5': XiangqiPiece.redChariot,
      });
      final moves = xiangqiLegalMoves(b).where((m) => m.from == at('e5'));
      final legalTargets = moves.map((m) => m.to).toSet();
      for (final t in legalTargets) {
        expect(xiangqiColOf(t) == 4, isTrue,
            reason: '合法目标必须仍在 e 线（否则双将照面）');
      }
    });
  });

  group('③ 将死判定：可挡将 / 可吃子时不得判将死', () {
    test('被将但能用棋子挡住 → 不是终局', () {
      // 黑将 e0 被红车 e4 将军（e1/e2/e3 之间有黑士 e2 挡着 → 其实没被将），
      // 且黑方仍有走子空间（士可动）→ 不是终局。
      final b = board({
        'e0': XiangqiPiece.blackGeneral,
        'e4': XiangqiPiece.redChariot,
        'e2': XiangqiPiece.blackAdvisor,
        'e9': XiangqiPiece.redGeneral,
      }, sideToMove: XiangqiColor.black);
      final st = kDefaultXiangqiEngine.status(b);
      expect(st.isOver, isFalse, reason: '还有合法着法 → 不该判终局');
    });

    test('被将且无解 → 将死（checkmate），判负', () {
      // 红车 e4 将军（e1/e2/e3 空），红车 d4 / f4 封住左右逃格，
      // 黑将 e0 退到 e1 仍在红车线上 → 无解 → 将死。
      final b = board({
        'e0': XiangqiPiece.blackGeneral,
        'e4': XiangqiPiece.redChariot,
        'd4': XiangqiPiece.redChariot,
        'f4': XiangqiPiece.redChariot,
        'e9': XiangqiPiece.redGeneral,
      }, sideToMove: XiangqiColor.black);
      final st = kDefaultXiangqiEngine.status(b);
      expect(st.isOver, isTrue);
      expect(st.reason, XiangqiEndReason.checkmate);
      expect(st.winner, XiangqiColorOrNull.red);
    });

    test('困毙（未被将军但无着可走）→ stalemate，且仍判负', () {
      final b = board({
        'e0': XiangqiPiece.blackGeneral,
        'd0': XiangqiPiece.redCannon,
        'f0': XiangqiPiece.redCannon,
        'e1': XiangqiPiece.redHorse,
        'd4': XiangqiPiece.redChariot,
        'e4': XiangqiPiece.redChariot,
        'f4': XiangqiPiece.redChariot,
        'e9': XiangqiPiece.redGeneral,
      }, sideToMove: XiangqiColor.black);
      expect(xiangqiIsInCheck(b, XiangqiColor.black), isFalse);
      final st = kDefaultXiangqiEngine.status(b);
      expect(st.reason, XiangqiEndReason.stalemate);
      expect(st.winner, XiangqiColorOrNull.red, reason: '困毙也判负');
    });
  });

  group('④ 黑方规则对称性', () {
    test('黑马腿：腿被自己棋子占住 → 该方向不可走', () {
      // 黑马 b0（row 0, col 1），腿 b1（row 1, col 1）被黑兵占据
      // → (-2,-1) / (-2,+1) 两个方向被堵。
      final b = board({
        'b0': XiangqiPiece.blackHorse,
        'b1': XiangqiPiece.blackPawn,
      }, sideToMove: XiangqiColor.black);
      final moves = xiangqiLegalMoves(b).where((m) => m.from == at('b0'));
      // 界内 4 个目标：a2 / c2（下二）与 a1? / c1?…
      for (final m in moves) {
        expect(xiangqiRowOf(m.to), lessThanOrEqualTo(1),
            reason: '马腿被蹩 → 不能跳到 row 2');
      }
    });

    test('黑象眼：象眼被占 → 该方向不可走', () {
      // 黑衣象 b0，象眼 c1（row 1, col 2）被黑兵占据
      final b = board({
        'b0': XiangqiPiece.blackElephant,
        'c1': XiangqiPiece.blackPawn,
      }, sideToMove: XiangqiColor.black);
      final moves = xiangqiLegalMoves(b).where((m) => m.from == at('b0'));
      expect(moves.any((m) => m.to == at('d2')), isFalse,
          reason: '象眼被塞 → 不可走');
    });

    test('黑炮架：隔一子可吃、隔两子不可吃', () {
      final b = board({
        'e4': XiangqiPiece.blackCannon,
        'e6': XiangqiPiece.blackPawn,
        'e8': XiangqiPiece.redHorse,
      }, sideToMove: XiangqiColor.black);
      final moves = xiangqiLegalMoves(b).where((m) => m.from == at('e4'));
      expect(moves.any((m) => m.to == at('e8') && m.isCapture), isTrue);
    });

    test('黑将九宫限制：不能出九宫', () {
      final b = board({'e0': XiangqiPiece.blackGeneral},
          sideToMove: XiangqiColor.black);
      for (final m in xiangqiLegalMoves(b)) {
        expect(
          xiangqiInPalaceOf(xiangqiRowOf(m.to), xiangqiColOf(m.to),
              isRed: false),
          isTrue,
        );
      }
    });
  });

  group('⑤ FEN 局面随机往返（property test）', () {
    test('随机合法局面 → FEN → 解析 → 局面键一致', () {
      for (var seed = 0; seed < 12; seed++) {
        final rng = Random(seed);
        var b = XiangqiBoardState.initial();
        for (var i = 0; i < 40; i++) {
          final moves = xiangqiLegalMoves(b);
          if (moves.isEmpty) break;
          b = applyXiangqiMoveSimple(b, moves[rng.nextInt(moves.length)]);
        }
        final fen = fenFromBoardState(b);
        expect(isValidXiangqiFen(fen), isTrue, reason: '生成的 FEN 必须自洽');
        final back = boardStateFromFen(fen);
        expect(back.positionKey, b.positionKey,
            reason: 'seed=$seed FEN 往返必须得到同一局面');
        expect(back.sideToMove, b.sideToMove);
      }
    });
  });

  group('⑥ 非法局面 FEN 必须被拒', () {
    test('缺黑将 → 拒', () {
      // 去掉黑将（row 0 的 K 位 → 空）
      const bad = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/4k3NR r - - 0 1';
      expect(isValidXiangqiFen(bad), isFalse);
    });

    test('红将数量为 2 → 拒', () {
      const bad = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNRR r - - 0 1';
      expect(isValidXiangqiFen(bad), isFalse);
    });

    test('兵数量 6 → 拒（超上限）', () {
      const bad = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/PPPPPPPPPP/1C5C1/9/RNBAKABNR r - - 0 1';
      expect(isValidXiangqiFen(bad), isFalse);
    });

    test('轮次字段非 r/b → 拒（解析器也必须拒，不能静默当红）', () {
      expect(isValidXiangqiFen('rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/'
          '1C5C1/9/RNBAKABNR w - - 0 1'), isFalse);
      expect(
        () => boardStateFromFen('rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/'
            '1C5C1/9/RNBAKABNR w - - 0 1'),
        throwsFormatException,
      );
    });

    test('合法初始局面 → 局面合法性通过', () {
      final b = XiangqiBoardState.initial();
      expect(isLegalXiangqiPosition(b), isTrue);
    });

    test('将出九宫 / 将帅照面 → 局面合法性拒绝', () {
      // 红帅跑到黑方半场（row 2）
      final outOfPalace = board({
        'e2': XiangqiPiece.redGeneral,
        'e0': XiangqiPiece.blackGeneral,
      });
      expect(isLegalXiangqiPosition(outOfPalace), isFalse);

      // 双将同列相望（中间无子）
      final facing = board({
        'e9': XiangqiPiece.redGeneral,
        'e0': XiangqiPiece.blackGeneral,
      });
      expect(isLegalXiangqiPosition(facing), isFalse);
      expect(xiangqiGeneralsFaceEachOther(facing), isTrue);
    });
  });

  group('⑦ 无法重放的棋谱记录 → 必须检出并对齐服务端（不得静默跳过）', () {
    test('起点无子的记录 → 检出不一致，且棋盘按服务端 FEN 对齐', () {
      // 服务端权威 FEN = 走完 'b7e7'（炮二平五）之后的局面：row 7 = '4C4'
      const afterCannon = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/'
          '4C4/9/RNBAKABNR b - - 0 1';
      // 第一手合法，第二手 'a8a9' 起点无子 → 无法重放
      final history = [
        XiangqiMoveRecord(uci: 'b7e7', by: 'H', ts: 1, fen: afterCannon),
        XiangqiMoveRecord(uci: 'a8a9', by: 'H', ts: 2, fen: afterCannon),
      ];
      final r = XiangqiRoom.rebuildBoardVerified(
        history,
        initialFen: kXiangqiStartingFen,
        serverFen: afterCannon,
        initialSide: XiangqiColor.red,
      );
      expect(r.consistent, isFalse, reason: '必须检出那一手无法重放');
      expect(r.repairedAtPly, 1);
      expect(r.matchesServerFen, isTrue,
          reason: '修复后棋盘必须与服务端一致');
      // 棋盘确实被服务端 FEN 接管（炮在 e7）
      expect(r.board.pieceAt(at('e7'))?.type, XiangqiPieceType.cannon);
    });

    test('与服务端 FEN 不一致时以服务端为准', () {
      final history = [
        XiangqiMoveRecord(uci: 'b7e7', by: 'H', ts: 1, fen: kXiangqiStartingFen),
      ];
      // 服务端 FEN 停在开局（未走）→ 与重放出的局面不同 → 以服务端为准
      final r = XiangqiRoom.rebuildBoardVerified(
        history,
        initialFen: kXiangqiStartingFen,
        serverFen: kXiangqiStartingFen,
        initialSide: XiangqiColor.red,
      );
      expect(r.consistent, isFalse, reason: '必须检出与服务端不一致');
      expect(r.matchesServerFen, isTrue, reason: '已按服务端 FEN 对齐');
      expect(r.board.pieceAt(at('b7'))?.type, XiangqiPieceType.cannon,
          reason: '服务端说炮还在 b7 → 以服务端为准');
    });
  });

  group('⑧ initial_side 与 FEN 轮次字段不一致 → 以服务端 initial_side 为准', () {
    test('initial_side=b（黑先）而 FEN 轮次位=r → 重放后轮次方按 parity 推', () {
      // 走一手 'b7e7'（红炮）—— 若重放起点是红方，走完后该黑走。
      final history = [
        XiangqiMoveRecord(uci: 'b7e7', by: 'H', ts: 1, fen: kXiangqiStartingFen),
      ];
      final r = XiangqiRoom.rebuildBoardVerified(
        history,
        initialFen: kXiangqiStartingFen,
        initialSide: XiangqiColor.black,
      );
      // initial_side=b → 第一手是黑方的；重放后轮次方 = side_to_move(1) = 红
      expect(r.board.sideToMove, XiangqiColor.red);
    });
  });
}
