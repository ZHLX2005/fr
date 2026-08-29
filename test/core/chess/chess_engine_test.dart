// test/core/chess/chess_engine_test.dart
//
// 国际象棋核心引擎回归测试（覆盖 FEN、起始 20 走、王车易位、
// 吃过路兵、升变、fool's mate 将杀、僵局、UCI 解析）

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';

void main() {
  group('FEN codec', () {
    test('初始局面 FEN 往返一致', () {
      const fen =
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final s = FenCodec.fromFen(fen);
      expect(FenCodec.toFen(s), fen);
    });

    test('空行用 8 表示', () {
      const fen = '8/8/8/8/8/8/8/8 w - - 0 1';
      final s = FenCodec.fromFen(fen);
      expect(s.cells.every((c) => c == null), true);
    });

    test('非法字符抛 ArgumentError', () {
      expect(
        () => FenCodec.fromFen('8/8/8/8/8/8/8/XX w - - 0 1'),
        throwsArgumentError,
      );
    });

    test('字段数过少抛 ArgumentError', () {
      expect(
        () => FenCodec.fromFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR'),
        throwsArgumentError,
      );
    });

    test('en-passant 字段 a3 / a6 解析正确', () {
      // 白方兵 a2-a4 后 ep-target = a3
      final s1 = FenCodec.fromFen(
          'rnbqkbnr/pppppppp/8/8/P7/8/1PPPPPPP/RNBQKBNR b KQkq a3 0 1');
      expect(s1.enPassantTarget, squareToIndex('a3'));

      // 黑方兵 a7-a5 后 ep-target = a6
      final s2 = FenCodec.fromFen(
          'rnbqkbnr/ppp1pppp/8/P7/8/8/1PPPPPPP/RNBQKBNR w KQkq a6 0 1');
      expect(s2.enPassantTarget, squareToIndex('a6'));
    });
  });

  group('初始局面', () {
    test('白方共 20 个合法走法（含双步兵前进）', () {
      final s = BoardState.initial();
      final legal = const ChessEngine().generateLegalMoves(s);
      expect(legal.length, 20, reason: '起点白方应有 20 合法走法');
    });

    test('起始状态 isInCheck = false', () {
      final s = BoardState.initial();
      expect(const ChessEngine().isInCheck(s), false);
    });
  });

  group('王车易位 (Castling)', () {
    test('白方 K 权存在 + 王无阻碍 + 无将军 → 2 个 castling 走法（O-O + O-O-O）', () {
      // FEN: 白方 K 短、长易位均有；黑方无；王 (e1) 与车之间空格无阻碍；王不在将军
      final fen = 'r3k2r/8/8/8/8/8/8/R3K2R w KQ - 0 1';
      final s = FenCodec.fromFen(fen);
      final legal = const ChessEngine().generateLegalMoves(s);
      final castlingMoves =
          legal.where((m) => m.flag == MoveFlags.castling).toList();
      expect(castlingMoves.length, 2,
          reason: 'K + Q 易位权都存在时应能 2 个易位');
    });

    test('白方 K 权撤销 → 不应能 O-O', () {
      final fen = 'r3k2r/8/8/8/8/8/8/R3K2R w Q - 0 1';
      final s = FenCodec.fromFen(fen);
      final legal = const ChessEngine().generateLegalMoves(s);
      final castling =
          legal.where((m) => m.flag == MoveFlags.castling && m.to == 62).toList();
      expect(castling.length, 0, reason: '白方无 K 易位权时 O-O 不可走');
    });

    test('王经过的格子被攻击 → 不应能 O-O', () {
      // 黑车在 f1 攻击 e1, f1, g1（实际能攻击 f1 是因为车在 f1，但 f1 该空——修改：黑后 d2 攻击 e1,f1,g1）
      // FEN: 4k3/8/8/8/8/8/3q4/R3K2R w KQ - 0 1
      // 黑后在 d2 (idx 11)：沿对角线攻击 e1 (60)。f1,g1 也被攻击（连对角线）
      // 因此 O-O 与 O-O-O 均禁止。
      final fen = '4k3/8/8/8/8/8/3q4/R3K2R w KQ - 0 1';
      final s = FenCodec.fromFen(fen);
      final legal = const ChessEngine().generateLegalMoves(s);
      final castling = legal.where((m) => m.flag == MoveFlags.castling).toList();
      // 注意：白方不"被将"（d2-e1 是斜线攻击 → 实际白王在将军状态）
      // 强制 O-O 不可：王被将 + 王经过的格子被攻击；任一违反即禁止
      expect(castling.length, 0, reason: '王被将 → 易位禁止');
    });
  });

  group('吃过路兵 (en passant)', () {
    test('白方 b2-b4 后，黑方 a4-bishop 可吃 a3 e.p.', () {
      // 白方刚走 1.b2-b4（a-file 仍空，b-file 双步进路过 b3）
      // ep-target = b3，黑方 a4 兵斜前 b3 吃白兵 b4（路过兵）
      // FEN: side=b, rank 5 = "pP6"（a4 黑兵 + b4 白兵），rank 2 = "2PPPPPP"（a2,b2 空 + c2-h2 白兵）
      final fen =
          'rnbqkbnr/pppppppp/8/8/pP6/8/2PPPPPP/RNBQKBNR b KQkq b3 0 1';
      final s = FenCodec.fromFen(fen);
      final legal = const ChessEngine().generateLegalMoves(s);
      final ep = legal.where((m) =>
          m.flag == MoveFlags.enPassant &&
          m.to == squareToIndex('b3') &&
          m.from == squareToIndex('a4')).toList();
      expect(ep.length, 1,
          reason: '黑方 a4-bishop 可吃 a3 吃过路兵');
    });
  });

  group('升变 (Promotion)', () {
    test('白兵到第 1 排 → 4 个升变走法（Q/R/B/N）', () {
      // 白兵已在 c1 (row 1, col 2 → idx 10)；到 row 0 col 2 = idx 2 即升变
      final fen = 'k7/2P5/8/8/8/8/8/4K3 w - - 0 1';
      final s = FenCodec.fromFen(fen);
      final legal = const ChessEngine().generateLegalMoves(s);
      final promotions = legal
          .where((m) =>
              m.promotion != null &&
              m.from == 10 &&
              m.to == 2)
          .toList();
      expect(promotions.length, 4);
    });
  });

  group('将杀判定 - fool\'s mate', () {
    test('1.f3 e5 2.g4 Qh4# — 黑方将杀', () {
      // 1.f3 e5 2.g4 → 局面 FEN
      // row 1（rank 7）: a7 p, b7 p, c7 p, d7 空, e7 空 (→ e5), f7 p, g7 p, h7 p → "ppp2ppp"
      // row 4 (rank 4): g4 = P → "6P1"
      // row 5 (rank 3): f3 = P → "5P2"
      // ep-target = g3 (因 2.g4 = g2→g4 经过 g3)
      const fen =
          'rnbqkbnr/ppp2ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq g3 0 2';
      var s = FenCodec.fromFen(fen);
      // 现在是黑方走，黑方 Qh4#
      final legal = const ChessEngine().generateLegalMoves(s);
      final qh4 = legal.where((m) =>
          m.to == squareToIndex('h4') &&
          m.from == squareToIndex('d8')).toList();
      expect(qh4.length, 1,
          reason: 'd8 皇后经 e7-f6-g5-h4 通路攻击应在合法走法清单');

      s = applyMove(s, qh4.first).nextState;
      final status = const ChessEngine().getStatus(s);
      expect(status, GameStatus.checkmate);
    });
  });

  group('僵局 (Stalemate)', () {
    test('真实僵局：黑方无合法走法且未被将军', () {
      // 经典僵局 K+Q vs k：白王 f7 + 白后 g6 控制黑王 a8 所有退路
      final fen = '7k/5K2/6Q1/8/8/8/8/8 b - - 0 1';
      final s = FenCodec.fromFen(fen);
      final status = const ChessEngine().getStatus(s);
      expect(status, GameStatus.stalemate,
          reason: '黑方无合法走法且未被将军 → 僵局');
    });
  });

  group('UCI 解析往返', () {
    test('Move.fromUci("e2e4") 正确', () {
      final m = Move.fromUci('e2e4');
      expect(m.from, squareToIndex('e2'));
      expect(m.to, squareToIndex('e4'));
      expect(m.promotion, isNull);
    });

    test('Move.toUci 正确（含升变）', () {
      final m = Move(from: squareToIndex('e7'), to: squareToIndex('e8'),
          promotion: PieceType.queen);
      expect(m.toUci(promotingColor: PieceColor.black), 'e7e8q');
    });

    test('棋谱 U 升变是白方', () {
      final m = Move(from: squareToIndex('a2'), to: squareToIndex('a1'),
          promotion: PieceType.rook);
      expect(m.toUci(), 'a2a1R');
    });
  });
}
