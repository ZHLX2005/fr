import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';

void main() {
  group('FileRef', () {
    test('roundtrip toJson → fromJson', () {
      const f = FileRef(
        fileId: 'aabbccdd00112233445566778899aabb',
        fileName: '00_white_king.webp',
        sizeBytes: 10396,
        contentType: 'image/webp',
      );
      final j = jsonEncode(f.toJson());
      final r = FileRef.fromJson(jsonDecode(j) as Map<String, dynamic>);
      expect(r.fileId, f.fileId);
      expect(r.fileName, f.fileName);
      expect(r.sizeBytes, f.sizeBytes);
      expect(r.contentType, f.contentType);
    });
  });

  group('ChessSkinMeta 12-key completeness', () {
    test('完整 12 pieces 通过 meta.isComplete', () {
      // note: not const — 'a' * 32 is not a const expression in Dart
      final meta = ChessSkinMeta(
        id: 'demo',
        displayName: 'demo',
        pieces: {
          'wK': FileRef(fileId: 'a' * 32, fileName: 'wk.webp', sizeBytes: 1, contentType: 'image/webp'),
          'wQ': FileRef(fileId: 'b' * 32, fileName: 'wq.webp', sizeBytes: 1, contentType: 'image/webp'),
          'wR': FileRef(fileId: 'c' * 32, fileName: 'wr.webp', sizeBytes: 1, contentType: 'image/webp'),
          'wB': FileRef(fileId: 'd' * 32, fileName: 'wb.webp', sizeBytes: 1, contentType: 'image/webp'),
          'wN': FileRef(fileId: 'e' * 32, fileName: 'wn.webp', sizeBytes: 1, contentType: 'image/webp'),
          'wp': FileRef(fileId: 'f' * 32, fileName: 'wp.webp', sizeBytes: 1, contentType: 'image/webp'),
          'bK': FileRef(fileId: '1' * 32, fileName: 'bk.webp', sizeBytes: 1, contentType: 'image/webp'),
          'bQ': FileRef(fileId: '2' * 32, fileName: 'bq.webp', sizeBytes: 1, contentType: 'image/webp'),
          'bR': FileRef(fileId: '3' * 32, fileName: 'br.webp', sizeBytes: 1, contentType: 'image/webp'),
          'bB': FileRef(fileId: '4' * 32, fileName: 'bb.webp', sizeBytes: 1, contentType: 'image/webp'),
          'bN': FileRef(fileId: '5' * 32, fileName: 'bn.webp', sizeBytes: 1, contentType: 'image/webp'),
          'bp': FileRef(fileId: '6' * 32, fileName: 'bp.webp', sizeBytes: 1, contentType: 'image/webp'),
        },
      );
      expect(meta.isComplete, true);
    });

    test('缺一个 piece → meta.isComplete false', () {
      final pieces = <String, FileRef>{};
      for (final pk in kChessSkin12PieceKeys) {
        pieces[pk] = FileRef(fileId: 'x' * 32, fileName: 'x.webp', sizeBytes: 1, contentType: 'image/webp');
      }
      pieces.remove('wK');
      final meta = ChessSkinMeta(id: 'demo', displayName: 'demo', pieces: pieces);
      expect(meta.isComplete, false);
    });
  });

  group('parseList', () {
    test('空 array → 空 list', () {
      expect(ChessSkinMeta.parseList('[]').length, 0);
    });

    test('重复 id 抛 FormatException', () {
      final json = jsonEncode([
        {'id': 'a', 'displayName': 'A', 'pieces': <String, dynamic>{}},
        {'id': 'a', 'displayName': 'A2', 'pieces': <String, dynamic>{}},
      ]);
      expect(() => ChessSkinMeta.parseList(json), throwsFormatException);
    });

    test('id 不符合 kChessSkinIdPattern 抛 FormatException（Uppercase / 含 ! / 长度超）', () {
      // 测试 3 个 invalid id 模式
      for (final invalidId in ['HasUpper', 'has-bang!', 'a' * 33]) {
        final json = jsonEncode([
          {'id': invalidId, 'displayName': 'X', 'pieces': <String, dynamic>{}},
        ]);
        expect(() => ChessSkinMeta.parseList(json), throwsFormatException,
            reason: 'id "$invalidId" 不符合 kebab-case regex');
      }
    });

    test('parseList 返回的 List 顺序 = 输入 JSON array 顺序（稳定）', () {
      final json = jsonEncode([
        {'id': 'first', 'displayName': '1', 'pieces': <String, dynamic>{}},
        {'id': 'second', 'displayName': '2', 'pieces': <String, dynamic>{}},
        {'id': 'third', 'displayName': '3', 'pieces': <String, dynamic>{}},
      ]);
      final list = ChessSkinMeta.parseList(json);
      expect(list.map((m) => m.id).toList(), ['first', 'second', 'third']);
    });
  });

  group('kChessSkinsCatalog', () {
    test('7 套皮肤全部 meta.isComplete', () {
      expect(kChessSkinsCatalog.length, 7);
      for (final s in kChessSkinsCatalog) {
        expect(s.isComplete, true,
            reason: 'skin ${s.id} missing pieces');
      }
    });

    test('每个 fileId 都是 32-hex', () {
      final hex32 = RegExp(r'^[a-f0-9]{32}$');
      for (final s in kChessSkinsCatalog) {
        for (final entry in s.pieces.entries) {
          expect(hex32.hasMatch(entry.value.fileId), true,
              reason: '${s.id}/${entry.key} fileId not 32-hex');
        }
      }
    });
  });
}