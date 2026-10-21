// test/core/xiangqi/xiangqi_engine_test.dart
//
// 中国象棋引擎规则测试。
//
// 覆盖：初始局面走法数（红黑各 44 步）、马腿、象眼/不过河、炮架、
// 兵过河横走、九宫限制、将帅照面、将死 / 困毙、FEN 往返。
//
// ## 记号约定
//
// 测试里用「列字母 + 行号」记格（如 `e0`）：字母 = 列（a..i，从左到右），
// **行号 = 内部 row（0 = 顶部黑方底线，9 = 底部红方底线）**。
// 红帅在 `e9`，黑将在 `e0`。

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

/// 便捷：从记号名构造索引
int at(String name) => xiangqiIndexFromName(name);

void main() {
  group('初始局面', () {
    test('FEN 与 board_state.initial() 一致', () {
      final board = XiangqiBoardState.initial();
      expect(
        xiangqiPositionToFen(board),
        'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR',
      );
      expect(board.sideToMove, XiangqiColor.red);
      expect(board.countOf(XiangqiColor.red), 16);
      expect(board.countOf(XiangqiColor.black), 16);
      expect(board.generalSquareOf(XiangqiColor.red), at('e9'));
      expect(board.generalSquareOf(XiangqiColor.black), at('e0'));
    });

    test('红方初始走法数 = 44', () {
      final board = XiangqiBoardState.initial();
      expect(xiangqiLegalMoves(board).length, 44);
    });

    test('黑方初始走法数 = 44（180° 对称）', () {
      final board = XiangqiBoardState.initial()
          .copyWith(sideToMove: XiangqiColor.black);
      expect(xiangqiLegalMoves(board).length, 44);
    });

    test('初始局面双方都不在被将军', () {
      final board = XiangqiBoardState.initial();
      expect(xiangqiIsInCheck(board, XiangqiColor.red), isFalse);
      expect(xiangqiIsInCheck(board, XiangqiColor.black), isFalse);
    });

    test('初始局面为「红先」', () {
      expect(XiangqiBoardState.initial().sideToMove, XiangqiColor.red);
    });
  });

  group('FEN 编解码', () {
    test('往返一致', () {
      final board = XiangqiBoardState.initial();
      final fen = fenFromBoardState(board);
      expect(isValidXiangqiFen(fen), isTrue);
      expect(boardStateFromFen(fen), board);
    });

    test('非法 FEN 被拒', () {
      expect(isValidXiangqiFen('rnbakabnr/9/1c5c1'), isFalse);
      expect(
        isValidXiangqiFen('rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/'
            '1C5C1/9/RNBAKABNR x - - 0 1'),
        isFalse,
      );
      expect(() => boardStateFromFen('bad'), throwsFormatException);
    });
  });

  group('马（蹩马腿）', () {
    test('腿被蹩住时不能走', () {
      // 红马 e9（row 9, col 4）；马腿 e8（row 8, col 4）被自己棋子占据
      // → 挡住 (-2,-1) 与 (-2,1) 两个方向 → 只剩 2 步
      final board = XiangqiBoardState(
        cells: _cells({
          'e9': XiangqiPiece.redHorse,
          'e8': XiangqiPiece.redPawn,
        }),
        sideToMove: XiangqiColor.red,
      );
      final moves = xiangqiLegalMoves(board).where((m) => m.from == at('e9'));
      expect(moves.length, 2);
      expect(moves.map((m) => m.to), containsAll(<int>[at('c8'), at('g8')]));
    });

    test('腿空时可以走满界内 4 个方向', () {
      final board = XiangqiBoardState(
        cells: _cells({'e9': XiangqiPiece.redHorse}),
        sideToMove: XiangqiColor.red,
      );
      final moves = xiangqiLegalMoves(board).where((m) => m.from == at('e9'));
      expect(moves.length, 4);
    });

    test('马不会走出棋盘（越界方向被跳过）', () {
      final board = XiangqiBoardState(
        cells: _cells({'a0': XiangqiPiece.blackHorse}),
        sideToMove: XiangqiColor.black,
      );
      for (final m in xiangqiLegalMoves(board)) {
        expect(m.to, greaterThanOrEqualTo(0));
        expect(m.to, lessThan(kXiangqiCells));
      }
    });
  });

  group('象（塞象眼 + 不过河）', () {
    test('象眼被塞住不能走', () {
      // 红象 c9（row 9, col 2）；象眼 b8（row 8, col 1）被红兵占据
      // → 挡住 (c9 → a7)，只剩 (c9 → e7)
      final board = XiangqiBoardState(
        cells: _cells({
          'c9': XiangqiPiece.redElephant,
          'b8': XiangqiPiece.redPawn,
        }),
        sideToMove: XiangqiColor.red,
      );
      final moves = xiangqiLegalMoves(board).where((m) => m.from == at('c9'));
      expect(moves.length, 1);
      expect(moves.first.to, at('e7'));
    });

    test('象不能过河（起点与终点必须同属一个半场）', () {
      // 黑象 c4（row 4, col 2）—— 在黑方半场，只能在 row ≤ 4 活动
      final board = XiangqiBoardState(
        cells: _cells({'c4': XiangqiPiece.blackElephant}),
        sideToMove: XiangqiColor.black,
      );
      for (final m in xiangqiLegalMoves(board)) {
        expect(xiangqiHalfOf(xiangqiRowOf(m.to)), xiangqiHalfOf(4));
      }
    });

    test('已过河的红象仍不能回黑方半场', () {
      // 红象 c2（row 2, col 2）—— 已过河，只能在 row ≤ 4 活动
      final board = XiangqiBoardState(
        cells: _cells({'c2': XiangqiPiece.redElephant}),
        sideToMove: XiangqiColor.red,
      );
      for (final m in xiangqiLegalMoves(board)) {
        expect(xiangqiHalfOf(xiangqiRowOf(m.to)), 0);
      }
    });
  });

  group('炮（炮架）', () {
    test('隔一子可吃', () {
      final board = XiangqiBoardState(
        cells: _cells({
          'e4': XiangqiPiece.redCannon,
          'e6': XiangqiPiece.redPawn, // 炮架
          'e8': XiangqiPiece.blackHorse, // 目标
        }),
        sideToMove: XiangqiColor.red,
      );
      final moves = xiangqiLegalMoves(board).where((m) => m.from == at('e4'));
      expect(moves.any((m) => m.to == at('e8') && m.isCapture), isTrue);
    });

    test('无炮架时不能吃（只能推不吃）', () {
      final board = XiangqiBoardState(
        cells: _cells({
          'e4': XiangqiPiece.redCannon,
          'e6': XiangqiPiece.blackHorse, // 目标（前面没有炮架）
        }),
        sideToMove: XiangqiColor.red,
      );
      final moves = xiangqiLegalMoves(board).where((m) => m.from == at('e4'));
      expect(moves.any((m) => m.to == at('e6')), isFalse);
    });

    test('隔两子不可吃', () {
      final board = XiangqiBoardState(
        cells: _cells({
          'e4': XiangqiPiece.redCannon,
          'e6': XiangqiPiece.redPawn, // 炮架 1
          'e7': XiangqiPiece.redPawn, // 炮架 2
          'e8': XiangqiPiece.blackHorse,
        }),
        sideToMove: XiangqiColor.red,
      );
      final moves = xiangqiLegalMoves(board).where((m) => m.from == at('e4'));
      expect(moves.any((m) => m.to == at('e8')), isFalse);
    });
  });

  group('兵（过河横走 / 不可后退）', () {
    test('过河后可左右横走', () {
      final board = XiangqiBoardState(
        cells: _cells({'c2': XiangqiPiece.redPawn}), // row 2 —— 已过河
        sideToMove: XiangqiColor.red,
      );
      final moves = xiangqiLegalMoves(board).where((m) => m.from == at('c2'));
      expect(moves.length, 3); // 前 + 左 + 右
    });

    test('未过河只能前进', () {
      final board = XiangqiBoardState(
        cells: _cells({'c6': XiangqiPiece.redPawn}), // row 6 —— 未过河
        sideToMove: XiangqiColor.red,
      );
      final moves = xiangqiLegalMoves(board).where((m) => m.from == at('c6'));
      expect(moves.length, 1);
      expect(moves.first.to, at('c5'));
    });

    test('兵不能后退', () {
      final board = XiangqiBoardState(
        cells: _cells({'c2': XiangqiPiece.redPawn}),
        sideToMove: XiangqiColor.red,
      );
      for (final m in xiangqiLegalMoves(board)) {
        // 前进会减小 row，横走 row 不变 —— 但 row 绝不能变大（后退）
        expect(xiangqiRowOf(m.to), lessThanOrEqualTo(xiangqiRowOf(at('c2'))));
      }
    });
  });

  group('将 / 士（九宫限制）', () {
    test('将不能出九宫', () {
      final board = XiangqiBoardState(
        cells: _cells({'e9': XiangqiPiece.redGeneral}),
        sideToMove: XiangqiColor.red,
      );
      final moves = xiangqiLegalMoves(board).where((m) => m.from == at('e9'));
      // 空九宫时将可走 3 格：上 + 左 + 右（下越界）
      expect(moves.length, 3);
      for (final m in moves) {
        expect(
          xiangqiInPalaceOf(
            xiangqiRowOf(m.to),
            xiangqiColOf(m.to),
            isRed: true,
          ),
          isTrue,
        );
      }
    });

    test('士不能出九宫', () {
      final board = XiangqiBoardState(
        cells: _cells({'d9': XiangqiPiece.redAdvisor}),
        sideToMove: XiangqiColor.red,
      );
      final moves = xiangqiLegalMoves(board).where((m) => m.from == at('d9'));
      expect(moves.length, 1);
      expect(moves.first.to, at('e8'));
    });
  });

  group('将帅照面', () {
    test('同列中间无子 → 双方互相将军（局面非法）', () {
      final board = XiangqiBoardState(
        cells: _cells({
          'e9': XiangqiPiece.redGeneral,
          'e0': XiangqiPiece.blackGeneral,
        }),
        sideToMove: XiangqiColor.red,
      );
      expect(xiangqiIsInCheck(board, XiangqiColor.red), isTrue);
      expect(xiangqiIsInCheck(board, XiangqiColor.black), isTrue);
    });

    test('中间有子 → 不照面', () {
      final board = XiangqiBoardState(
        cells: _cells({
          'e9': XiangqiPiece.redGeneral,
          'e4': XiangqiPiece.redPawn,
          'e0': XiangqiPiece.blackGeneral,
        }),
        sideToMove: XiangqiColor.red,
      );
      expect(xiangqiIsInCheck(board, XiangqiColor.red), isFalse);
      expect(xiangqiIsInCheck(board, XiangqiColor.black), isFalse);
    });

    test('将帅照面时不能沿同列移动（走出照面）', () {
      // 红帅 e9，黑将 e0，中间 e4 空 —— 红帅若走到 e8 仍照面 → 非法；
      // 横走 d9 / f9 会离开 e 线 → 合法。
      final board = XiangqiBoardState(
        cells: _cells({
          'e9': XiangqiPiece.redGeneral,
          'e0': XiangqiPiece.blackGeneral,
        }),
        sideToMove: XiangqiColor.red,
      );
      final moves = xiangqiLegalMoves(board).where((m) => m.from == at('e9'));
      expect(moves.any((m) => m.to == at('e8')), isFalse);
      expect(moves.any((m) => m.to == at('d9')), isTrue);
      expect(moves.any((m) => m.to == at('f9')), isTrue);
    });
  });

  group('终局判定', () {
    test('被将死 → 对方胜（checkmate）', () {
      // 黑将 e0 被红车 e4 直线将军；
      // 逃逸格 e1 / d0 / f0 分别被红车 e4 / d4 / f4 控制
      final board = XiangqiBoardState(
        cells: _cells({
          'e0': XiangqiPiece.blackGeneral,
          'e4': XiangqiPiece.redChariot,
          'd4': XiangqiPiece.redChariot,
          'f4': XiangqiPiece.redChariot,
          'e9': XiangqiPiece.redGeneral,
        }),
        sideToMove: XiangqiColor.black,
      );
      expect(xiangqiIsInCheck(board, XiangqiColor.black), isTrue);
      final st = kDefaultXiangqiEngine.status(board);
      expect(st.isOver, isTrue);
      expect(st.reason, XiangqiEndReason.checkmate);
      expect(st.winner, XiangqiColorOrNull.red);
    });

    test('困毙（无着可走但未被将军）→ 判负（stalemate）', () {
      // 黑方只剩 e0 的将；三个逃逸格 e1 / d0 / f0 被红子占据且被红车保护
      final board = XiangqiBoardState(
        cells: _cells({
          'e0': XiangqiPiece.blackGeneral,
          'd0': XiangqiPiece.redCannon,
          'f0': XiangqiPiece.redCannon,
          'e1': XiangqiPiece.redHorse,
          'd4': XiangqiPiece.redChariot,
          'e4': XiangqiPiece.redChariot,
          'f4': XiangqiPiece.redChariot,
          'e9': XiangqiPiece.redGeneral,
        }),
        sideToMove: XiangqiColor.black,
      );
      expect(xiangqiIsInCheck(board, XiangqiColor.black), isFalse);
      expect(xiangqiLegalMoves(board), isEmpty);
      final st = kDefaultXiangqiEngine.status(board);
      expect(st.isOver, isTrue);
      expect(st.reason, XiangqiEndReason.stalemate);
      expect(st.winner, XiangqiColorOrNull.red);
    });

    test('未终局时返回 playing', () {
      final board = XiangqiBoardState.initial();
      expect(kDefaultXiangqiEngine.status(board).isOver, isFalse);
    });
  });

  group('走法记号', () {
    test('记号与索引互转', () {
      expect(xiangqiSquareName(at('e0')), 'e0');
      expect(at('e0'), xiangqiIndex(0, 4));
      expect(at('e9'), xiangqiIndex(9, 4));
      expect(xiangqiIndexFromName('zz'), -1);
      expect(xiangqiIndexFromName('a'), -1);
    });

    test('走法串往返', () {
      final m = XiangqiMove(from: at('b0'), to: at('e2'));
      expect(m.toUci(), 'b0e2');
      final back = XiangqiMove.fromUci('b0e2');
      expect(back, isNotNull);
      expect(back!.from, m.from);
      expect(back.to, m.to);
      expect(XiangqiMove.fromUci('xx'), isNull);
    });
  });

  group('applyMove', () {
    test('走子后换边 + 吃子', () {
      final board = XiangqiBoardState(
        cells: _cells({
          'e4': XiangqiPiece.redChariot,
          'e6': XiangqiPiece.blackPawn,
        }),
        sideToMove: XiangqiColor.red,
      );
      final move = XiangqiMove(
        from: at('e4'),
        to: at('e6'),
        captured: XiangqiPiece.blackPawn,
      );
      final res = applyXiangqiMove(board, move);
      expect(res.captured, XiangqiPiece.blackPawn);
      expect(res.nextState.sideToMove, XiangqiColor.black);
      expect(res.nextState.pieceAt(at('e6'))?.color, XiangqiColor.red);
      expect(res.nextState.pieceAt(at('e4')), isNull);
    });
  });
}

/// 构造 90 格棋盘：从记号名 → 棋子 的映射。
List<int?> _cells(Map<String, XiangqiPiece> spec) {
  final cells = List<int?>.filled(kXiangqiCells, null, growable: false);
  spec.forEach((name, piece) {
    cells[xiangqiIndexFromName(name)] = piece.pack();
  });
  return cells;
}
