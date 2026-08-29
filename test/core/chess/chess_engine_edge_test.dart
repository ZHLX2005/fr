// test/core/chess/chess_engine_edge_test.dart
//
// International chess business layer edge cases — does NOT duplicate
// chess_engine_test.dart / chess_engine_deep_test.dart coverage.
//
// Index math reference (FEN row R * 8 + col C):
//   - a8=0, h8=7        (rank 8 = row 0)
//   - a1=56, h1=63      (rank 1 = row 7)
//   - a7=col 0 row 1,    b7=col 1 row 1 → idx 1*8+1=9
//   - b8=col 1 row 0,    c8=col 2 row 0 → idx 0*8+1=1, 0*8+2=2
//   - c7=col 2 row 1,    c2=col 2 row 6 → idx 10, 50
//   - a2=col 0 row 6,    e2=col 4 row 6 → idx 48, 52
//   - e4=col 4 row 4,    e5=col 4 row 3 → idx 36, 28
//   - g1=col 6 row 7,    f3=col 5 row 5 → idx 62, 45
//   - h1=col 7 row 7,    b1=col 1 row 7 → idx 63, 57

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';

void main() {
  group('attack map: minimal board edge cases', () {
    test('empty board — no pieces, attacked set empty (both colors)', () {
      final empty = BoardState(
        board: List<int?>.filled(64, null, growable: false),
        sideToMove: PieceColor.white,
      );
      expect(empty.findKing(PieceColor.white), isNull);
      expect(const ChessEngine().isInCheck(empty), false);
      expect(computeAttackedSquares(empty, PieceColor.white), isEmpty);
      expect(computeAttackedSquares(empty, PieceColor.black), isEmpty);
    });

    test('single white king alone — black attacks nothing; white attacks king 5 in-board neighbors', () {
      // White king at e1 (idx 60). No other pieces.
      final board = List<int?>.filled(64, null, growable: false);
      board[60] = PieceSlot.pack(PieceType.king, PieceColor.white);
      final s = BoardState(
        board: board,
        sideToMove: PieceColor.white,
      );
      // Black has no pieces → attacks nothing
      expect(computeAttackedSquares(s, PieceColor.black), isEmpty);
      // White king attacks its in-board neighbors:
      // e1 (row 7 col 4) → row 6 col 3,4,5 (idx 51,52,53) + row 7 col 3,5 (idx 59,61)
      final whiteAttacked = computeAttackedSquares(s, PieceColor.white);
      expect(whiteAttacked, containsAll([51, 52, 53, 59, 61]));
      // King does NOT attack own square
      expect(whiteAttacked, isNot(contains(60)));
    });
  });

  group('castling: blocked and in-check rejections', () {
    test('white O-O blocked by own pawn on f1 (rank 1) → O-O absent, O-O-O present', () {
      // Row 7 = "R3KP1R": R(a1), 3 empty(b1-d1), K(e1), P(f1), 1 empty(g1), R(h1)
      // FEN row "R3KP1R" is 6 chars encoding 8 squares
      final fen = 'r3k2r/8/8/8/8/8/8/R3KP1R w KQ - 0 1';
      final s = FenCodec.fromFen(fen);
      const engine = ChessEngine();
      final legal = engine.generateLegalMoves(s);
      final ooKingSide = legal.where((m) => m.flag == MoveFlags.castling && m.to == 62);
      final ooQueenSide = legal.where((m) => m.flag == MoveFlags.castling && m.to == 58);
      expect(ooKingSide, isEmpty, reason: 'f1 pawn blocks O-O king transit');
      expect(ooQueenSide, isNotEmpty, reason: 'b1/c1/d1 empty → O-O-O available');
    });

    test('white king currently in check → both castling moves absent', () {
      // Black rook on e8 attacks white king on e1 (file attack).
      // White king transit squares (f1, g1) are not attacked but castling
      // is forbidden while in check.
      final fen = '4r3/8/8/8/8/8/8/4K2R w K - 0 1';
      final s = FenCodec.fromFen(fen);
      const engine = ChessEngine();
      expect(engine.isInCheck(s), true);
      final legal = engine.generateLegalMoves(s);
      final castling = legal.where((m) => m.flag == MoveFlags.castling);
      expect(castling, isEmpty,
          reason: 'castling forbidden while in check, regardless of transit safety');
    });
  });

  group('promotion: vacant target + self-blocked target', () {
    test('white pawn b7 with empty b8 → 4 promotion moves to b8', () {
      // b7 (idx 9) promotes to b8 (idx 1)
      final fen = 'k7/1P6/8/8/8/8/8/K7 w - - 0 1';
      final s = FenCodec.fromFen(fen);
      final legal = const ChessEngine().generateLegalMoves(s);
      final promotions = legal
          .where((m) => m.promotion != null && m.from == 9 && m.to == 1)
          .toList();
      expect(promotions.length, 4);
      expect(promotions.map((m) => m.promotion).toSet(),
          {PieceType.queen, PieceType.rook, PieceType.bishop, PieceType.knight});
    });

    test('pawn c7 promotion blocked by own knight on c8 → no promotion', () {
      // c7 (idx 10) wants to promote to c8 (idx 2) but white knight occupies c8.
      // Row 0: 'k1N5' = k(a8), 1 empty(b8), N(c8), 5 empty(d-h8)
      final fen = 'k1N5/2P5/8/8/8/8/8/K7 w - - 0 1';
      final s = FenCodec.fromFen(fen);
      final legal = const ChessEngine().generateLegalMoves(s);
      final promotions = legal
          .where((m) => m.promotion != null && m.from == 10 && m.to == 2);
      expect(promotions, isEmpty,
          reason: 'c8 occupied by own knight → c7 cannot promote');
    });
  });

  group('applyMove error semantics + deep immutability', () {
    test('applyMove from empty square (e4 idx 36) throws ArgumentError', () {
      final s = BoardState.initial();
      // e4 (row 4 col 4 = idx 36) is empty in initial state
      expect(() => applyMove(s, const Move(from: 36, to: 28)), throwsArgumentError);
    });

    test('applyMove repeated 8 times does not mutate original state — verify all 64 cells + every field', () {
      final original = BoardState.initial();
      // Snapshot every observable field
      final beforeCells = List<int?>.from(original.cells);
      final beforeSide = original.sideToMove;
      final beforeCastling = original.castling;
      final beforeEp = original.enPassantTarget;
      final beforeHalfmove = original.halfmoveClock;
      final beforeFullmove = original.fullmoveNumber;
      final beforeWhiteKing = original.findKing(PieceColor.white);
      final beforeBlackKing = original.findKing(PieceColor.black);

      // 1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. d3 d6
      final seq = [
        const Move(from: 52, to: 36), // e4
        const Move(from: 12, to: 28), // e5
        const Move(from: 62, to: 45), // Nf3
        const Move(from: 57, to: 41), // Nc6
        const Move(from: 61, to: 34), // Bc4
        const Move(from: 5, to: 37), // Bc5
        const Move(from: 51, to: 43), // d3
        const Move(from: 14, to: 46), // d6
      ];
      for (final m in seq) {
        applyMove(original, m);
      }

      // Every observable field must still equal the recorded baseline
      for (var i = 0; i < 64; i++) {
        expect(original.cells[i], beforeCells[i],
            reason: 'cells[$i] was mutated');
      }
      expect(original.sideToMove, beforeSide);
      expect(original.castling, beforeCastling);
      expect(original.enPassantTarget, beforeEp);
      expect(original.halfmoveClock, beforeHalfmove);
      expect(original.fullmoveNumber, beforeFullmove);
      expect(original.findKing(PieceColor.white), beforeWhiteKing);
      expect(original.findKing(PieceColor.black), beforeBlackKing);
    });
  });

  group('long game sanity: 8 half-moves', () {
    test('sequential legal half-moves: halfmove + fullmove + kings + status invariants', () {
      var s = BoardState.initial();
      // 1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. d3 d6 (8 half-moves = 4 full rounds)
      final seq = [
        const Move(from: 52, to: 36), // 1. e4
        const Move(from: 12, to: 28), // 1... e5
        const Move(from: 62, to: 45), // 2. Nf3
        const Move(from: 57, to: 41), // 2... Nc6
        const Move(from: 61, to: 34), // 3. Bc4
        const Move(from: 5, to: 37), // 3... Bc5
        const Move(from: 51, to: 43), // 4. d3
        const Move(from: 14, to: 46), // 4... d6
      ];
      for (final m in seq) {
        s = applyMove(s, m).nextState;
      }

      const engine = ChessEngine();

      // 8 half-moves (4 white + 4 black) → fullmoveNumber 5
      // (start at 1, increments on black move: 1 → 2 → 3 → 4 → 5)
      expect(s.fullmoveNumber, 5);
      // Last move is d6 (pawn) → halfmoveClock resets to 0
      expect(s.halfmoveClock, 0);
      // Both kings still on their home squares
      expect(s.findKing(PieceColor.white), 60);
      expect(s.findKing(PieceColor.black), 4);
      // Not in check, not terminated
      expect(engine.isInCheck(s), false);
      final status = engine.getStatus(s);
      expect(status, GameStatus.playing);
    });
  });
}
