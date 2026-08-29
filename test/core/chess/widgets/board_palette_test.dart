// test/core/chess/widgets/board_palette_test.dart
//
// BoardPalette（自定义棋盘配色）值类测试：
//   · 默认构造 → 全字段 null + isEmpty（完整跟随主题）
//   · 设置任一字段 → isEmpty false
//   · ==/hashCode 按字段（同值相等、异值不等）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/board_palette.dart';

void main() {
  group('BoardPalette 值类', () {
    test('默认构造 → 全字段 null + isEmpty（跟随主题）', () {
      const p = BoardPalette();
      expect(p.lightSquare, isNull);
      expect(p.darkSquare, isNull);
      expect(p.gridLine, isNull);
      expect(p.selectedSquare, isNull);
      expect(p.lastMoveHighlight, isNull);
      expect(p.legalMoveHint, isNull);
      expect(p.captureHint, isNull);
      expect(p.checkWarning, isNull);
      expect(p.isEmpty, isTrue, reason: '全字段 null → isEmpty（完整回退主题）');
    });

    test('只设置两主格色 → isEmpty false', () {
      const p = BoardPalette(
        lightSquare: Color(0xFFF0D9B5),
        darkSquare: Color(0xFFB58863),
      );
      expect(p.isEmpty, isFalse);
      expect(p.lightSquare, const Color(0xFFF0D9B5));
      expect(p.darkSquare, const Color(0xFFB58863));
      // 其余角色未覆盖（null = 主题默认）
      expect(p.gridLine, isNull);
      expect(p.selectedSquare, isNull);
    });

    test('只设置任一高亮色 → isEmpty false（部分覆盖合法）', () {
      const p = BoardPalette(selectedSquare: Color(0x597A9A7E));
      expect(p.isEmpty, isFalse);
      expect(p.selectedSquare, const Color(0x597A9A7E));
      expect(p.lightSquare, isNull);
    });

    test('==/hashCode 按字段（同值相等）', () {
      const a = BoardPalette(
        lightSquare: Color(0xFFF0D9B5),
        darkSquare: Color(0xFFB58863),
      );
      const b = BoardPalette(
        lightSquare: Color(0xFFF0D9B5),
        darkSquare: Color(0xFFB58863),
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('任一字段不同 → 不相等', () {
      const a = BoardPalette(lightSquare: Color(0xFFF0D9B5));
      const b = BoardPalette(lightSquare: Color(0xFFEBE5D6));
      const c = BoardPalette(
        lightSquare: Color(0xFFF0D9B5),
        darkSquare: Color(0xFFB58863),
      );
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(c)), reason: 'c 多覆盖了 darkSquare → 不等');
    });

    test('空 palette == 空 palette（isEmpty 的两种来源一致）', () {
      const a = BoardPalette();
      const b = BoardPalette();
      expect(a, equals(b));
      expect(a.isEmpty, isTrue);
    });
  });
}
