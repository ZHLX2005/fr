// test/lab/tetris_lua/tetris_strategy_native_test.dart
//
// TetrisColorsStrategy 跨主题锁定测试 —— 验证 tetris 棋盘配色不跟 5 主题切换。
// 之前 default.dart 从 scheme 派生 4 角色，导致切主题时棋盘配色跟随变化。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/theme/colors/strategy/tetris_colors_strategy/themes/default.dart';
import 'package:xiaodouzi_fr/lab/demos/tetris_lua/constants.dart';

void main() {
  group('DefaultTetrisColorsStrategy 跨主题锁定', () {
    test('不同 ColorScheme 返回同一 pieceColors Map (theme-independent)', () {
      const schemeA = ColorScheme.light(primary: Color(0xFF000000));
      const schemeB = ColorScheme.dark(primary: Color(0xFFFFFFFF));
      final sA = DefaultTetrisColorsStrategy.of(schemeA);
      final sB = DefaultTetrisColorsStrategy.of(schemeB);
      // pieceColors 必须身份相等（同一 const Map 实例）
      expect(identical(sA.pieceColors, sB.pieceColors), true,
          reason: 'tetris 棋盘配色跨主题锁定，pieceColors 必须是同一实例');
    });

    test('同 scheme 连续调用返回缓存的同一实例（factory 缓存）', () {
      const scheme = ColorScheme.light(primary: Color(0xFF000000));
      final a = DefaultTetrisColorsStrategy.of(scheme);
      final b = DefaultTetrisColorsStrategy.of(scheme);
      expect(identical(a, b), true);
    });

    test('切 scheme 后 cellHighlight / pieceBackground / pieceGridLine 不变', () {
      const schemeA = ColorScheme.light(
        onSurface: Color(0xFFFF0000),
        surfaceContainerHighest: Color(0xFF00FF00),
        outline: Color(0xFF0000FF),
      );
      const schemeB = ColorScheme.dark(
        onSurface: Color(0xFF111111),
        surfaceContainerHighest: Color(0xFF222222),
        outline: Color(0xFF333333),
      );
      final sA = DefaultTetrisColorsStrategy.of(schemeA);
      final sB = DefaultTetrisColorsStrategy.of(schemeB);
      // 4 角色必须完全一致（不跟 scheme 切换）
      expect(sA.cellHighlight, sB.cellHighlight);
      expect(sA.pieceBackground, sB.pieceBackground);
      expect(sA.pieceGridLine, sB.pieceGridLine);
    });

    test('7 方块色与 tetris.dart（Ash flat well）一致', () {
      const scheme = ColorScheme.light();
      final s = DefaultTetrisColorsStrategy.of(scheme);
      expect(s.pieceColors[kPieceI], const Color(0xFF2AD4E0));
      expect(s.pieceColors[kPieceL], const Color(0xFFFF9A3D));
    });

    test('L 块 (type 7) 在 strategy.pieceColors 中必须有值（off-by-one 保护）', () {
      const scheme = ColorScheme.light();
      final s = DefaultTetrisColorsStrategy.of(scheme);
      expect(s.pieceColors[kPieceL], isNotNull,
          reason: 'L 块之前是越界源；现在 Map 必须有 type 7');
    });
  });
}
