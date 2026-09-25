// test/lab/tetris_lua/tetris_palette_test.dart
//
// Tetris 棋盘配色回归测试 —— 锁定 TetrisColors 当前「Ash flat well」配色。
// tetris 棋盘配色作为特例跨主题锁定，不跟 5 主题切换。
// （历史上曾锁定 commit 6e681248 的 slate 配色，该配色已被 Ash 中灰井取代。）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/theme/tokens/color/tetris/tetris.dart';
import 'package:xiaodouzi_fr/lab/demos/tetris_lua/constants.dart';

void main() {
  group('TetrisColors.pieceColors (Map<int, Color> 1..7)', () {
    test('索引 1..7 全部有值（结构上保证 off-by-one 不会复发）', () {
      for (final t in [
        kPieceI, kPieceO, kPieceT, kPieceS, kPieceZ, kPieceJ, kPieceL,
      ]) {
        expect(
          TetrisColors.pieceColors[t],
          isNotNull,
          reason: 'piece type $t 必须有颜色（L 块 type 7 之前是越界源）',
        );
      }
    });

    test('越界 / 无效索引安全返回 null（强制 ! 编译期 fail）', () {
      expect(TetrisColors.pieceColors[0], isNull);
      expect(TetrisColors.pieceColors[8], isNull);
      expect(TetrisColors.pieceColors[-1], isNull);
      expect(TetrisColors.pieceColors[100], isNull);
    });

    test('7 方块糖果色与 tetris.dart 一致（I=cyan / O=gold / ...）', () {
      expect(TetrisColors.pieceColors[kPieceI], const Color(0xFF2AD4E0));
      expect(TetrisColors.pieceColors[kPieceO], const Color(0xFFF5C518));
      expect(TetrisColors.pieceColors[kPieceT], const Color(0xFFA56BFF));
      expect(TetrisColors.pieceColors[kPieceS], const Color(0xFF3DD68C));
      expect(TetrisColors.pieceColors[kPieceZ], const Color(0xFFFF5A7A));
      expect(TetrisColors.pieceColors[kPieceJ], const Color(0xFF4B7BFF));
      expect(TetrisColors.pieceColors[kPieceL], const Color(0xFFFF9A3D));
    });
  });

  group('TetrisColors 棋盘环境色 (const native)', () {
    test('pieceBackground = Ash 中灰 #3A414C', () {
      expect(TetrisColors.pieceBackground, const Color(0xFF3A414C));
    });

    test('pieceGridLine = white @ ~7% alpha (0x12 ≈ 18/255)', () {
      expect(TetrisColors.pieceGridLine, const Color(0x12FFFFFF));
    });

    test('cellHighlight = white @ 50% alpha (0x80 ≈ 128/255)', () {
      expect(TetrisColors.cellHighlight, const Color(0x80FFFFFF));
    });
  });
}
