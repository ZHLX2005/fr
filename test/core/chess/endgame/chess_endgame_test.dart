// test/core/chess/endgame/chess_endgame_test.dart
//
// 残局模型 + 校验 + 内置 assets FEN 合法性 + 黑先 / 白先端到端校验。
//
// 关键覆盖：
//   · tryParse 各种合法 / 非法输入
//   · isValidEndgameFen 双王校验（缺王 / 多王 / 缺子）
//   · 内置 5 套残局 assets 全部能解析（防内置 FEN 手写出错）
//   · ChessEndgameSideFromFen 黑先残局正确返回 'b'

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:xiaodouzi_fr/core/chess/endgame/chess_endgame.dart';

void main() {
  group('ChessEndgame.tryParse', () {
    test('合法 JSON → 完整字段解析', () {
      final raw = jsonEncode({
        'format': 'fr-chess-endgame',
        'version': 1,
        'id': 'eg-test-001',
        'title': '后单王杀王',
        'description': '基础杀王',
        'createdAt': '2026-08-31T00:00:00Z',
        'source': 'imported',
        'tags': ['杀王'],
        'difficulty': 1,
        'snapshots': [
          {'label': '起点', 'fen': '8/8/8/4k3/8/8/4Q3/4K3 w - - 0 1'},
        ],
      });
      final e = ChessEndgame.tryParse(raw);
      expect(e, isNotNull);
      expect(e!.id, 'eg-test-001');
      expect(e.title, '后单王杀王');
      expect(e.source, ChessEndgameSource.imported);
      expect(e.snapshots, hasLength(1));
      expect(e.snapshots.first.fen, contains('4Q3'));
    });

    test('format 错误 → null', () {
      final raw = jsonEncode({
        'format': 'wrong-format',
        'version': 1,
        'id': 'eg-x',
        'title': 'X',
        'snapshots': [
          {'fen': '8/8/8/4k3/8/8/4Q3/4K3 w - - 0 1'},
        ],
      });
      expect(ChessEndgame.tryParse(raw), isNull);
    });

    test('version 不在 1..1 范围 → null', () {
      final raw = jsonEncode({
        'format': 'fr-chess-endgame',
        'version': 99,
        'id': 'eg-x',
        'title': 'X',
        'snapshots': [
          {'fen': '8/8/8/4k3/8/8/4Q3/4K3 w - - 0 1'},
        ],
      });
      expect(ChessEndgame.tryParse(raw), isNull);
    });

    test('title 缺失 → null', () {
      final raw = jsonEncode({
        'format': 'fr-chess-endgame',
        'version': 1,
        'id': 'eg-x',
        'snapshots': [
          {'fen': '8/8/8/4k3/8/8/4Q3/4K3 w - - 0 1'},
        ],
      });
      expect(ChessEndgame.tryParse(raw), isNull);
    });

    test('snapshots 为空 → null', () {
      final raw = jsonEncode({
        'format': 'fr-chess-endgame',
        'version': 1,
        'id': 'eg-x',
        'title': 'X',
        'snapshots': [],
      });
      expect(ChessEndgame.tryParse(raw), isNull);
    });

    test('单 snapshot FEN 缺白王 → null（双王校验）', () {
      final raw = jsonEncode({
        'format': 'fr-chess-endgame',
        'version': 1,
        'id': 'eg-x',
        'title': 'X',
        'snapshots': [
          // 白王缺失
          {'fen': '8/8/8/4k3/8/8/4Q3/8 w - - 0 1'},
        ],
      });
      expect(ChessEndgame.tryParse(raw), isNull);
    });

    test('JSON 解析失败 → null', () {
      expect(ChessEndgame.tryParse('{invalid'), isNull);
    });
  });

  group('ChessEndgame.isValidEndgameFen', () {
    test('双方各一王 → true', () {
      expect(
        ChessEndgame.isValidEndgameFen(
          '8/8/8/4k3/8/8/4Q3/4K3 w - - 0 1',
        ),
        isTrue,
      );
    });

    test('缺一王 → false', () {
      expect(
        ChessEndgame.isValidEndgameFen('8/8/8/8/8/8/4Q3/4K3 w - - 0 1'),
        isFalse,
      );
    });

    test('多王 → false', () {
      // 两白王一黑王
      expect(
        ChessEndgame.isValidEndgameFen(
          '8/8/8/4k3/8/8/4K3/4K3 w - - 0 1',
        ),
        isFalse,
      );
    });

    test('畸形 FEN → false', () {
      expect(
        ChessEndgame.isValidEndgameFen('not a fen'),
        isFalse,
      );
    });
  });

  group('sideFromFen', () {
    test('白先 → w', () {
      expect(
        ChessEndgame.sideFromFen(
          '8/8/8/4k3/8/8/4Q3/4K3 w - - 0 1',
        ),
        'w',
      );
    });

    test('黑先 → b（关键：残局黑先必须返回 b）', () {
      expect(
        ChessEndgame.sideFromFen(
          '8/8/8/4k3/8/8/4P3/4K3 b - - 0 1',
        ),
        'b',
      );
    });

    test('畸形 FEN → 回退 w', () {
      expect(ChessEndgame.sideFromFen('garbage'), 'w');
    });
  });

  group('内置 assets 残局校验', () {
    testWidgets('eg_builtin_01..05 全部合法', (tester) async {
      // assets 加载需要 binding：tester 自动初始化。
      const names = [
        'eg_builtin_01',
        'eg_builtin_02',
        'eg_builtin_03',
        'eg_builtin_04',
        'eg_builtin_05',
      ];
      for (final n in names) {
        final raw = await rootBundle
            .loadString('assets/data/chess_endgames/$n.json');
        final e = ChessEndgame.tryParse(
          raw,
          source: ChessEndgameSource.builtin,
        );
        expect(e, isNotNull, reason: '$n 解析失败');
        expect(e!.title, isNotEmpty, reason: '$n title 空');
        expect(e.snapshots, isNotEmpty, reason: '$n snapshots 空');
        for (final s in e.snapshots) {
          expect(
            ChessEndgame.isValidEndgameFen(s.fen),
            isTrue,
            reason: '$n 快照 FEN 校验失败: ${s.fen}',
          );
        }
      }
    });
  });
}
