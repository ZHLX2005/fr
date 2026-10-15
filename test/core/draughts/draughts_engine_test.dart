// test/core/draughts/draughts_engine_test.dart
//
// 国际跳棋引擎规则测试。
// 覆盖：初始局面 / 强制吃子 / 最长吃子 / 多跳链 / flying king / 升王 / FEN·PDN。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/draughts/draughts.dart';

/// 便利：从方格号取 1D 索引
int sq(int n) => draughtsIndexFromSquareNumber(n);

/// 构造棋盘：白方子（方格号列表）+ 黑方子 + 轮次方
DraughtsBoardState boardOf({
  List<int> whiteMen = const [],
  List<int> whiteKings = const [],
  List<int> blackMen = const [],
  List<int> blackKings = const [],
  DraughtsColor turn = DraughtsColor.white,
}) {
  final cells = List<int?>.filled(kDraughtsCells, null);
  void place(List<int> squares, DraughtsColor color, bool king) {
    for (final n in squares) {
      final idx = sq(n);
      if (idx < 0) continue;
      cells[idx] = DraughtsPiece(color, isKing: king).pack();
    }
  }

  place(whiteMen, DraughtsColor.white, false);
  place(whiteKings, DraughtsColor.white, true);
  place(blackMen, DraughtsColor.black, false);
  place(blackKings, DraughtsColor.black, true);
  return DraughtsBoardState(cells: cells, sideToMove: turn);
}

void main() {
  group('初始局面', () {
    test('白黑各 20 兵，白先', () {
      final s = DraughtsBoardState.initial();
      expect(s.countOf(DraughtsColor.white), 20);
      expect(s.countOf(DraughtsColor.black), 20);
      expect(s.sideToMove, DraughtsColor.white);
      for (final (_, p) in s.occupied) {
        expect(p.isKing, isFalse);
      }
    });

    test('起始 FEN 往返一致', () {
      final s = DraughtsBoardState.initial();
      expect(fenFromBoardState(s), kDraughtsStartingFen);
      final back = boardStateFromFen(kDraughtsStartingFen);
      expect(back, s);
    });

    test('白方开局恰有 9 种合法着法（FMJD 标准）', () {
      final s = DraughtsBoardState.initial();
      final moves = kDefaultDraughtsEngine.legalMoves(s);
      expect(moves.length, 9);
      for (final m in moves) {
        expect(m.isCapture, isFalse);
      }
    });
  });

  group('方格编号映射', () {
    test('1..50 与索引往返', () {
      for (var n = 1; n <= 50; n++) {
        final idx = sq(n);
        expect(idx, greaterThanOrEqualTo(0));
        expect(draughtsSquareNumberOfIndex(idx), n);
      }
    });

    test('起始 31-50 在白方一侧、1-20 在黑方一侧', () {
      for (var n = 31; n <= 50; n++) {
        expect(draughtsRowOf(sq(n)), greaterThanOrEqualTo(6));
      }
      for (var n = 1; n <= 20; n++) {
        expect(draughtsRowOf(sq(n)), lessThanOrEqualTo(3));
      }
    });
  });

  group('强制吃子', () {
    test('有吃子则只能吃', () {
      // 白兵 28 斜前是黑兵 23，落点 19 空
      final s = boardOf(whiteMen: [28], blackMen: [23]);
      final moves = kDefaultDraughtsEngine.legalMoves(s);
      expect(moves, isNotEmpty);
      expect(moves.every((m) => m.isCapture), isTrue,
          reason: '有吃子时必须吃');
    });

    test('吃子后可继续吃则形成多跳链', () {
      // 白兵 28 吃 23 落 19；19 再吃 14 落 10
      final s = boardOf(whiteMen: [28], blackMen: [23, 14]);
      final moves = kDefaultDraughtsEngine.legalMoves(s);
      expect(moves.length, 1);
      expect(moves.first.captureCount, 2);
      expect(moves.first.path.length, 3);
    });
  });

  group('最长吃子规则', () {
    test('必须选吃子数最多的着法', () {
      final s = boardOf(whiteMen: [28], blackMen: [23, 14, 33]);
      final moves = kDefaultDraughtsEngine.legalMoves(s);
      final maxCap =
          moves.map((m) => m.captureCount).reduce((a, b) => a > b ? a : b);
      expect(moves.every((m) => m.captureCount == maxCap), isTrue);
    });
  });

  group('flying king', () {
    test('王可斜向滑任意距离', () {
      final s = boardOf(whiteKings: [28], blackMen: [5]);
      final moves = kDefaultDraughtsEngine.legalMoves(s);
      final simple = moves.where((m) => !m.isCapture).toList();
      expect(simple.length, greaterThan(4), reason: '王应能滑多格');
      // 方格 28 = (row5,col4)；左上斜线可达 22/17/11/6
      final targets = simple.map((m) => m.to).toSet();
      expect(targets, containsAll([sq(22), sq(17), sq(11), sq(6)]));
      expect(targets, containsAll([sq(32), sq(37), sq(41), sq(46)]));
    });

    test('王可隔距离吃子并自选落点', () {
      final s = boardOf(whiteKings: [46], blackMen: [28]);
      final moves = kDefaultDraughtsEngine.legalMoves(s);
      final caps = moves.where((m) => m.isCapture).toList();
      expect(caps, isNotEmpty);
      expect(caps.map((m) => m.to).toSet().length, greaterThan(1));
    });
  });

  group('升王', () {
    test('兵走到对方底线升王', () {
      final s = boardOf(whiteMen: [6], blackMen: [50]);
      final moves = kDefaultDraughtsEngine.legalMoves(s);
      final promoting = moves.where((m) => m.isPromotion).toList();
      expect(promoting, isNotEmpty);
      final next = applyMoveSimple(s, promoting.first);
      expect(next.pieceAt(promoting.first.to)!.isKing, isTrue);
    });

    test('经过底线但还能吃则不升王且必须继续吃', () {
      // 白兵 11 吃 7 落 2（底线）；2 再向后吃 8 落 13
      final s = boardOf(whiteMen: [11], blackMen: [7, 8]);
      final moves = kDefaultDraughtsEngine.legalMoves(s);
      expect(moves.length, 1);
      expect(moves.first.captureCount, 2);
      expect(moves.first.isPromotion, isFalse);
    });
  });

  group('终局判定', () {
    test('吃光对方判胜', () {
      final s = boardOf(whiteMen: [28]);
      final status = kDefaultDraughtsEngine.status(s);
      expect(status.outcome, DraughtsOutcome.whiteWins);
      expect(status.reason, DraughtsEndReason.noPieces);
    });

    test('王对王判和', () {
      final s = boardOf(whiteKings: [28], blackKings: [23]);
      final status = kDefaultDraughtsEngine.status(s);
      expect(status.outcome, DraughtsOutcome.draw);
      expect(status.reason, DraughtsEndReason.kingVsKing);
    });
  });

  group('PDN', () {
    test('走子记号', () {
      final m = DraughtsMove.simple(sq(32), sq(28));
      expect(m.toPdn(), '32-28');
    });

    test('吃子记号含多跳', () {
      final m = DraughtsMove(
        from: sq(28),
        to: sq(10),
        path: [sq(28), sq(19), sq(10)],
        capturedSquares: [sq(23), sq(14)],
      );
      expect(m.toPdn(), '28x19x10');
    });

    test('PDN 解析回 move 并定位被吃子', () {
      final s = boardOf(whiteMen: [28], blackMen: [23]);
      final m = pdnMoveToMove(s, '28x19');
      expect(m, isNotNull);
      expect(m!.isCapture, isTrue);
      expect(m.capturedSquares, [sq(23)]);
    });

    test('flying king 远距离吃子 PDN 往返', () {
      final s = boardOf(whiteKings: [46], blackMen: [28]);
      final caps = kDefaultDraughtsEngine
          .legalMoves(s)
          .where((m) => m.isCapture)
          .toList();
      expect(caps, isNotEmpty);
      final long = caps.firstWhere(
        (m) {
          final dr = (draughtsRowOf(m.to) - draughtsRowOf(m.from)).abs();
          return dr > 2;
        },
        orElse: () => caps.first,
      );
      expect(
        (draughtsRowOf(long.to) - draughtsRowOf(long.from)).abs(),
        greaterThan(2),
        reason: '测试前提：需有远距离落点',
      );
      final pdn = long.toPdn();
      final decoded = pdnMoveToMove(s, pdn);
      expect(decoded, isNotNull, reason: '远距离 PDN=$pdn 应可解码');
      expect(decoded!.from, long.from);
      expect(decoded.to, long.to);
      expect(decoded.capturedSquares, long.capturedSquares);
    });
  });

  group('FEN', () {
    test('解析带回王与轮次', () {
      final fen = 'B:WK31,K32,33:B1-20';
      final s = boardStateFromFen(fen);
      expect(s.sideToMove, DraughtsColor.black);
      expect(s.pieceAt(sq(31))!.isKing, isTrue);
      expect(s.pieceAt(sq(33))!.isKing, isFalse);
      expect(s.countOf(DraughtsColor.black), 20);
    });

    test('王区间 K31-33 往返仍是王', () {
      final s = boardOf(whiteKings: [31, 32, 33]);
      final fen = fenFromBoardState(s);
      expect(fen, contains('K31-33'));
      final back = boardStateFromFen(fen);
      expect(back.pieceAt(sq(31))!.isKing, isTrue);
      expect(back.pieceAt(sq(32))!.isKing, isTrue);
      expect(back.pieceAt(sq(33))!.isKing, isTrue);
    });

    test('空 FEN 抛异常', () {
      expect(() => boardStateFromFen(''), throwsFormatException);
    });
  });
}
