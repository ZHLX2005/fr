// test/core/chess/replay/chess_game_record_test.dart
//
// ChessGameRecord 模型测试：encode/tryParse 往返 + 全防御解析 + 标签映射。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_record.dart';

ChessGameRecord _sample() => const ChessGameRecord(
      id: 'game-123456-1758285594000',
      title: '对局 09-19 23:19',
      initialFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      uciMoves: ['e2e4', 'e7e5', 'g1f3', 'e7e8q'],
      status: 'checkmate',
      roomCode: '123456',
      savedAt: '2026-09-19T15:19:54Z',
    );

/// encode → 改字段 → encode 的辅助。
String _mutated(Map<String, dynamic> Function(Map<String, dynamic>) fn) {
  final j = fn(jsonDecode(_sample().encode()) as Map<String, dynamic>);
  return jsonEncode(j);
}

void main() {
  group('ChessGameRecord encode/tryParse 往返', () {
    test('encode → tryParse 全字段还原', () {
      final r = _sample();
      final back = ChessGameRecord.tryParse(r.encode());
      expect(back, isNotNull);
      expect(back!.id, r.id);
      expect(back.title, r.title);
      expect(back.initialFen, r.initialFen);
      expect(back.uciMoves, r.uciMoves);
      expect(back.status, r.status);
      expect(back.roomCode, r.roomCode);
      expect(back.savedAt, r.savedAt);
      expect(back.moveCount, 4);
    });

    test('status/roomCode 缺省 → encode 不写字段 → 往返回退空值', () {
      const r = ChessGameRecord(
        id: 'g1',
        title: 't',
        initialFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        uciMoves: ['e2e4'],
        savedAt: '2026-09-19T15:00:00Z',
      );
      final back = ChessGameRecord.tryParse(r.encode());
      expect(back, isNotNull);
      expect(back!.status, '');
      expect(back.roomCode, isNull);
    });

    test('contentKey：同局面+同谱 → 相同；改谱 → 不同（幂等查重用）', () {
      final a = _sample();
      final b = ChessGameRecord(
        id: 'other-id',
        title: 'other',
        initialFen: a.initialFen,
        uciMoves: a.uciMoves,
        savedAt: a.savedAt,
      );
      expect(a.contentKey(), b.contentKey(),
          reason: '内容指纹只看 initialFen + uciMoves，不看 id/title');
      final c = ChessGameRecord(
        id: a.id,
        title: a.title,
        initialFen: a.initialFen,
        uciMoves: [...a.uciMoves, 'b1c3'],
        savedAt: a.savedAt,
      );
      expect(a.contentKey() == c.contentKey(), isFalse);
    });
  });

  group('ChessGameRecord.tryParse 防御', () {
    test('坏 JSON → null', () {
      expect(ChessGameRecord.tryParse('{not json'), isNull);
    });

    test('format / version 不符 → null', () {
      expect(
        ChessGameRecord.tryParse(_mutated((j) => j..['format'] = 'fr-other')),
        isNull,
      );
      expect(
        ChessGameRecord.tryParse(_mutated((j) => j..['version'] = 99)),
        isNull,
      );
    });

    test('缺 id / title / initialFen → null', () {
      for (final key in ['id', 'title', 'initialFen']) {
        expect(
          ChessGameRecord.tryParse(_mutated((j) => j..remove(key))),
          isNull,
          reason: '缺 $key 应拒解析',
        );
      }
    });

    test('非法 FEN → null', () {
      expect(
        ChessGameRecord.tryParse(
          _mutated((j) => j..['initialFen'] = 'not a fen'),
        ),
        isNull,
      );
    });

    test('uciMoves 非列表 / 项位数非法 → null', () {
      expect(
        ChessGameRecord.tryParse(_mutated((j) => j..['uciMoves'] = 'e2e4')),
        isNull,
      );
      expect(
        ChessGameRecord.tryParse(
          _mutated((j) => j..['uciMoves'] = ['e2e4', 'xyz']),
        ),
        isNull,
      );
    });
  });

  group('chessGameStatusLabel 终局徽标映射', () {
    test('四种终局 → 中文；非终局 → 空串', () {
      expect(chessGameStatusLabel('checkmate'), '将杀');
      expect(chessGameStatusLabel('stalemate'), '僵局');
      expect(chessGameStatusLabel('resigned'), '认输');
      expect(chessGameStatusLabel('draw'), '和棋');
      expect(chessGameStatusLabel('playing'), '');
      expect(chessGameStatusLabel('check'), '');
      expect(chessGameStatusLabel(null), '');
    });
  });
}
