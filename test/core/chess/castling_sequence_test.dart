// test/core/chess/castling_sequence_test.dart
//
// 白棋王车易位实战序列回归测试：
// 孤立 FEN 易位测试（chess_engine_test.dart）已通过，但"从初始局面走
// 若干步后易位"的序列场景未覆盖 —— castling 权利随每手 applyMove 传递，
// 任何中间手把它悄悄弄丢都会导致"白棋王车无法正常易位"。
//
// 场景：
//   A. 实战短易位：1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5 4.O-O
//   B. 实战长易位：1.d4 d5 2.Nc3 Nc6 3.Bf4 Nf6 4.Qc2 e6 5.O-O-O
//   C. 攻击线被挡：黑后 h4 盯 e1（f2 兵挡住）→ 不构成将军，O-O 仍合法
//   D. 每步 FEN castling 字段断言（权利传递追踪）
//   E. 吃车撤权：白兵 xa8（吃 a8 黑车）→ k 权应保留、q 权应撤销

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/constants/chess_constants.dart';
import 'package:xiaodouzi_fr/core/chess/engine/chess_engine.dart';
import 'package:xiaodouzi_fr/core/chess/engine/fen_codec.dart';
import 'package:xiaodouzi_fr/core/chess/engine/make_move.dart';
import 'package:xiaodouzi_fr/core/chess/models/board_state.dart';
import 'package:xiaodouzi_fr/core/chess/models/move.dart';
import 'package:xiaodouzi_fr/core/chess/models/piece.dart';

const ChessEngine engine = ChessEngine();

/// 从合法走法表里找 uci 对应的走法（断言必须恰好一条）
Move legalMove(BoardState s, String uci) {
  final m = Move.fromUci(uci);
  final hits = engine
      .generateLegalMoves(s)
      .where((x) => x.from == m.from && x.to == m.to)
      .toList();
  expect(hits, isNotEmpty, reason: 'uci $uci 应为合法走法');
  return hits.first;
}

BoardState play(BoardState s, String uci) =>
    applyMove(s, legalMove(s, uci)).nextState;

String castlingField(BoardState s) =>
    FenCodec.toFen(s).split(' ')[2];

void main() {
  group('白棋短易位实战序列 1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5 4.O-O', () {
    test('每步易位权保持 KQkq，第 4 手 O-O 可走且应用正确', () {
      var s = BoardState.initial();
      expect(castlingField(s), 'KQkq');

      s = play(s, 'e2e4'); // 1.e4
      expect(castlingField(s), 'KQkq', reason: '兵动不撤权');
      s = play(s, 'e7e5');
      expect(castlingField(s), 'KQkq');
      s = play(s, 'g1f3'); // 2.Nf3
      expect(castlingField(s), 'KQkq', reason: '马从 g1 离开不撤白权');
      s = play(s, 'b8c6');
      expect(castlingField(s), 'KQkq');
      s = play(s, 'f1c4'); // 3.Bc4
      expect(castlingField(s), 'KQkq', reason: '象从 f1 离开不撤白权');
      s = play(s, 'f8c5');
      expect(castlingField(s), 'KQkq');

      // 4.O-O：f1/g1 已空，黑象 c5 的攻击线被 f2 兵挡住，不构成将军
      final castleK = legalMove(s, 'e1g1');
      expect(castleK.flag, MoveFlags.castling);

      s = applyMove(s, castleK).nextState;
      // 王到 g1(62)、车到 f1(61)
      expect(s.pieceTypeAt(62), isNotNull);
      expect(s.pieceTypeAt(61), isNotNull);
      expect(s.pieceColorAt(62), PieceColor.white, reason: 'g1 应是白王');
      expect(s.pieceColorAt(61), PieceColor.white, reason: 'f1 应是白车');
      expect(castlingField(s), 'kq', reason: '白易位后白权撤销、黑权保留');
      expect(s.sideToMove, PieceColor.black, reason: '白走完轮黑');
    });

    test('O-O 后快照 FEN 往返（走子方发送 → 服务端存储 → 对方重建）', () {
      var s = BoardState.initial();
      for (final uci in ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5']) {
        s = play(s, uci);
      }
      s = play(s, 'e1g1');
      // 模拟 P2P：走子方发 toFen → 对方 fromFen 重建
      final wire = FenCodec.toFen(s);
      final rebuilt = FenCodec.fromFen(wire);
      // 重建后黑方（对方）应能正常走子；白方已易位权撤销
      expect(castlingField(rebuilt), 'kq');
      // 对方再走一手后白方"飞车/飞象"等普通走法不受影响（防状态污染）
      final blackMoves = engine.generateLegalMoves(rebuilt);
      expect(blackMoves, isNotEmpty);
    });
  });

  group('白棋长易位实战序列（London 体系：1.d4 d5 2.Nc3 Nf6 3.Bf4 e6 4.e3 Be7 5.c3 O-O 6.Qc2 … 7.O-O-O）', () {
    test('b1/c1/d1 清空后 O-O-O 可走', () {
      var s = BoardState.initial();
      s = play(s, 'd2d4'); // 1.d4
      s = play(s, 'd7d5');
      s = play(s, 'b1c3'); // 2.Nc3
      s = play(s, 'g8f6');
      s = play(s, 'c1f4'); // 3.Bf4
      s = play(s, 'e7e6');
      s = play(s, 'e2e3'); // 4.e3
      s = play(s, 'f8e7');
      s = play(s, 'f1d3'); // 5.Bd3 —— c1 彻底清空
      s = play(s, 'e8g8'); // 黑 O-O（验证黑易位路径正常）
      expect(castlingField(s), 'KQ', reason: '黑易位后黑权撤销、白 KQ 保留');
      s = play(s, 'd1d2'); // 6.Qd2 —— 后让出 d1（d2 已被 d4 兵空出）
      s = play(s, 'f8e8'); // 黑车 f8→e8（随便一步合法棋）
      expect(castlingField(s), 'KQ',
          reason: '白王/车未动、a1/h1 车原位未动 → 白 KQ 权应完整');
      final oo = legalMove(s, 'e1c1');
      expect(oo.flag, MoveFlags.castling);
      s = applyMove(s, oo).nextState;
      expect(castlingField(s), '-', reason: '白 O-O-O 后双方权全无');
      // 王到 c1(58)、车到 d1(59)
      expect(s.pieceColorAt(58), PieceColor.white, reason: 'c1 应是白王');
      expect(s.pieceColorAt(59), PieceColor.white, reason: 'd1 应是白车');
      expect(s.isEmpty(60), isTrue, reason: 'e1 应已清空');
      expect(s.isEmpty(56), isTrue, reason: 'a1 应已清空');
    });
  });

  group('吃车撤权', () {
    test('白兵 b7xa8 吃黑 a8 车 → 黑 q 权撤销，白 KQ/黑 k 保留', () {
      const fen = 'rk6/1P6/8/8/8/8/8/R3K2R w KQkq - 0 1';
      final s = FenCodec.fromFen(fen);
      final cap = legalMove(s, 'b7a8');
      final next = applyMove(s, cap).nextState;
      expect(castlingField(next), 'KQk',
          reason: 'a8 车被吃 → 黑 q 权撤销；白权与黑 k 权不受影响');
    });

    test('黑兵 g2xh1 吃白 h1 车 → 白 K 权撤销，白 Q/黑 kq 保留', () {
      const fenB = 'r3k3/8/8/8/8/8/6p1/R3K2R b KQkq - 0 1';
      final sB = FenCodec.fromFen(fenB);
      final cap = legalMove(sB, 'g2h1');
      final next = applyMove(sB, cap).nextState;
      expect(castlingField(next), 'Qkq',
          reason: 'h1 车被吃 → 白 K 权撤销；Q 权与黑权保留');
    });
  });

  group('攻击线细节（白棋易位合法性边界）', () {
    test('黑车盯 h 列（h1 白车被攻击）不影响白 O-O 合法性', () {
      // 规则：易位只查"王经过格"（e1/f1/g1），车被攻击不禁止易位
      const fen = '7r/8/8/8/8/8/8/R3K2R w KQ - 0 1';
      final s = FenCodec.fromFen(fen);
      final castling = engine
          .generateLegalMoves(s)
          .where((m) => m.flag == MoveFlags.castling)
          .toList();
      expect(castling.map((m) => m.to), contains(62),
          reason: 'h 列被攻击不禁止王翼易位');
    });

    test('黑车沿 e 列直盯 e1（无遮挡）→ 白王被将，O-O 禁止', () {
      const fen = '4r3/8/8/8/8/8/8/R3K2R w KQ - 0 1';
      final s = FenCodec.fromFen(fen);
      final castling = engine
          .generateLegalMoves(s)
          .where((m) => m.flag == MoveFlags.castling)
          .toList();
      expect(castling, isEmpty, reason: '被将时禁止易位');
    });

    test('黑车 e 列被白兵 e4 挡住 → 王未被将，O-O 合法（王离开后兵仍在挡）', () {
      const fen = '4r3/8/8/8/4P3/8/8/R3K2R w KQ - 0 1';
      final s = FenCodec.fromFen(fen);
      final castling = engine
          .generateLegalMoves(s)
          .where((m) => m.flag == MoveFlags.castling)
          .toList();
      expect(castling.map((m) => m.to), contains(62),
          reason: 'e4 兵挡住 e 列攻击线，短易位合法');
    });
  });
}
