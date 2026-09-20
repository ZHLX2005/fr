// test/core/chess/replay/chess_game_record_store_test.dart
//
// ChessGameRecordStore 测试：临时目录注入 → save/loadAll/delete/exists
// 全链路 + 损坏文件跳过 + web 降级语义（仿残局库 store 测试模式）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_record.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_record_store.dart';

ChessGameRecord _record(String id, {String savedAt = '2026-09-19T15:00:00Z'}) =>
    ChessGameRecord(
      id: id,
      title: '对局 $id',
      initialFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      uciMoves: const ['e2e4', 'e7e5', 'g1f3'],
      status: 'resigned',
      roomCode: '777777',
      savedAt: savedAt,
    );

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chess_game_store_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ChessGameRecordStore store() =>
      ChessGameRecordStore(dirProvider: () async => tmp, isWeb: false);

  group('save / loadAll / exists / delete 全链路', () {
    test('save → loadAll 还原（含目录自动创建）', () async {
      final s = store();
      final r = _record('game-a-1');
      await s.save(r);

      expect(await s.existsLocal(r.id), isTrue);
      final all = await s.loadAll();
      expect(all, hasLength(1));
      expect(all.first.id, r.id);
      expect(all.first.title, r.title);
      expect(all.first.uciMoves, r.uciMoves);
      expect(all.first.status, 'resigned');
    });

    test('loadAll 按 savedAt 倒序（新保存的在最上）', () async {
      final s = store();
      await s.save(_record('old', savedAt: '2026-09-01T10:00:00Z'));
      await s.save(_record('new', savedAt: '2026-09-19T20:00:00Z'));
      await s.save(_record('mid', savedAt: '2026-09-10T10:00:00Z'));

      final all = await s.loadAll();
      expect(all.map((e) => e.id).toList(), ['new', 'mid', 'old']);
    });

    test('损坏文件 / 非本类型文件 → 跳过不影响其余', () async {
      final s = store();
      await s.save(_record('good'));
      final dir = Directory('${tmp.path}/chess_games');
      File('${dir.path}/broken.chessgame.json')
          .writeAsStringSync('{not json');
      File('${dir.path}/other.txt').writeAsStringSync('ignore me');

      final all = await s.loadAll();
      expect(all, hasLength(1));
      expect(all.first.id, 'good');
    });

    test('delete → exists false / loadAll 空', () async {
      final s = store();
      final r = _record('game-b-2');
      await s.save(r);
      await s.delete(r.id);
      expect(await s.existsLocal(r.id), isFalse);
      expect(await s.loadAll(), isEmpty);
    });

    test('delete 不存在的 id → 静默成功', () async {
      await store().delete('no-such-id');
    });
  });

  group('web 降级（isWeb: true 注入）', () {
    test('loadAll 空 / exists false / delete 静默', () async {
      final s = ChessGameRecordStore(dirProvider: () async => tmp, isWeb: true);
      expect(await s.loadAll(), isEmpty);
      expect(await s.existsLocal('x'), isFalse);
      await s.delete('x');
    });

    test('save 抛 UnsupportedError（调用方 Snackbar 文案化）', () async {
      final s = ChessGameRecordStore(dirProvider: () async => tmp, isWeb: true);
      expect(
        () => s.save(_record('web-1')),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
