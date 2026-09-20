// test/core/chess/replay/chess_replay_resolver_test.dart
//
// ChessGameReplayResolver 重演测试：整谱重演 / 易位 flag 正确性 / 升变 /
// 畸形与脱节棋谱防御截断 / 坏 FEN 回退。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_replay_resolver.dart';

void main() {
  group('ChessGameReplayResolver.resolve', () {
    test('标准开局序列重演：states = moves + 1，终态轮次交替', () {
      const uci = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5'];
      final r = ChessGameReplayResolver.resolve(
        initialFen: kStartingFen,
        uciMoves: uci,
      );

      expect(r.truncated, 0, reason: '合法整谱应完整重演');
      expect(r.moves, hasLength(5));
      expect(r.states, hasLength(6));
      expect(r.states.first == FenCodec.fromFen(kStartingFen), isTrue);
      // 5 手后轮黑。
      expect(r.states.last.sideToMove, PieceColor.black);
      // states[i] 逐手推进：第 1 手后 e4 有白兵、e2 空。
      expect(r.states[1].pieceTypeAt(squareToIndex('e4')), PieceType.pawn);
      expect(r.states[1].isEmpty(squareToIndex('e2')), isTrue);
    });

    test('易位重演：uci e1g1 → 王落 g1、车随移 f1（flag 正确性核心断言）', () {
      // 直接 Move.fromUci 裸 flag 会走成"王飞两格、车不动" —— resolver 必须
      // 经合法走法匹配拿到带 flag 的 Move。
      const fen = 'r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1';
      final r = ChessGameReplayResolver.resolve(
        initialFen: fen,
        uciMoves: const ['e1g1', 'e8c8'],
      );

      expect(r.truncated, 0);
      expect(r.moves, hasLength(2));
      expect(r.moves.first.flag, MoveFlags.castling, reason: '白 O-O 识别为易位');
      final afterWhite = r.states[1];
      expect(afterWhite.pieceTypeAt(squareToIndex('g1')), PieceType.king);
      expect(afterWhite.pieceTypeAt(squareToIndex('f1')), PieceType.rook);
      expect(afterWhite.isEmpty(squareToIndex('e1')), isTrue);
      expect(afterWhite.isEmpty(squareToIndex('h1')), isTrue);
      // 黑 O-O-O 后：王 c8、车 d8。
      expect(r.moves[1].flag, MoveFlags.castling, reason: '黑 O-O-O 识别为易位');
      final afterBlack = r.states[2];
      expect(afterBlack.pieceTypeAt(squareToIndex('c8')), PieceType.king);
      expect(afterBlack.pieceTypeAt(squareToIndex('d8')), PieceType.rook);
      expect(afterBlack.isEmpty(squareToIndex('a8')), isTrue);
    });

    test('吃过路兵重演：过路兵目标格生效（en passant 吃子）', () {
      // 1.e4 a6 2.e5 d5 3.exd6（吃过路兵）。
      const uci = ['e2e4', 'a7a6', 'e4e5', 'd7d5', 'e5d6'];
      final r = ChessGameReplayResolver.resolve(
        initialFen: kStartingFen,
        uciMoves: uci,
      );
      expect(r.truncated, 0);
      final afterEp = r.states.last;
      expect(afterEp.pieceTypeAt(squareToIndex('d6')), PieceType.pawn,
          reason: '吃过路兵后白兵落在 d6');
      expect(afterEp.isEmpty(squareToIndex('d5')), isTrue,
          reason: '被吃黑兵（d5）移除');
    });

    test('升变重演：uci 第 5 位 promotion 透传', () {
      const fen = '8/P6k/8/8/8/8/7K/8 w - - 0 1';
      final r = ChessGameReplayResolver.resolve(
        initialFen: fen,
        uciMoves: const ['a7a8q'],
      );
      expect(r.truncated, 0);
      expect(r.moves.first.promotion, PieceType.queen);
      expect(r.states.last.pieceTypeAt(squareToIndex('a8')), PieceType.queen);
    });

    test('畸形 uci → 截断保留合法前缀', () {
      const uci = ['e2e4', 'zz99', 'e7e5'];
      final r = ChessGameReplayResolver.resolve(
        initialFen: kStartingFen,
        uciMoves: uci,
      );
      expect(r.moves, hasLength(1));
      expect(r.truncated, 2);
      expect(r.states, hasLength(2));
    });

    test('棋谱与局面脱节 → 截断（如开局直接 e7e8q）', () {
      const uci = ['e7e8q', 'e2e4'];
      final r = ChessGameReplayResolver.resolve(
        initialFen: kStartingFen,
        uciMoves: uci,
      );
      expect(r.moves, isEmpty);
      expect(r.truncated, 2);
      expect(r.states, hasLength(1), reason: '零手重演 → 只有初始局面');
    });

    test('坏 FEN → 回退标准开局重演（防御）', () {
      final r = ChessGameReplayResolver.resolve(
        initialFen: 'broken fen',
        uciMoves: const ['e2e4'],
      );
      expect(r.truncated, 0);
      expect(r.states.first == FenCodec.fromFen(kStartingFen), isTrue);
    });

    test('空谱 → 仅初始局面', () {
      final r = ChessGameReplayResolver.resolve(
        initialFen: kStartingFen,
        uciMoves: const [],
      );
      expect(r.moves, isEmpty);
      expect(r.states, hasLength(1));
      expect(r.truncated, 0);
    });
  });
}
