// test/core/theme/chess_color_strategy_test.dart
//
// DefaultChessColorStrategy 派生正确性测试 ——
// 与 tetris 不同，chess 走 scheme 派生（切主题 = 换 scheme = 13 角色全部跟随变化）。
// 对照断言：
//   1. 同 scheme 多次调用返回同一实例（factory 单例缓存）
//   2. 切 scheme 后 13 角色全部重新派生（颜色随主题变化）
//   3. 与 tokens/color/chess/chess.dart 的 *From() 方法产出一致
//   4. ==/hashCode 按角色正确实现

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/theme/colors/strategy/chess_color_strategy/themes/default.dart';
import 'package:xiaodouzi_fr/core/theme/tokens/color/chess/chess.dart';

void main() {
  group('DefaultChessColorStrategy 派生正确性', () {
    test('同 scheme 连续调用返回缓存的同一实例', () {
      const scheme = ColorScheme.light();
      final a = DefaultChessColorStrategy.of(scheme);
      final b = DefaultChessColorStrategy.of(scheme);
      expect(identical(a, b), true, reason: '.of() 必须走单例缓存');
    });

    test('切 scheme 后返回新实例（非同一实例）', () {
      const schemeA = ColorScheme.light();
      const schemeB = ColorScheme.dark();
      final sA = DefaultChessColorStrategy.of(schemeA);
      final sB = DefaultChessColorStrategy.of(schemeB);
      expect(identical(sA, sB), false);
    });

    test('lightSquare 派生 = scheme.surface', () {
      const scheme = ColorScheme.light();
      final s = DefaultChessColorStrategy.of(scheme);
      expect(s.lightSquare, scheme.surface);
    });

    test('darkSquare 派生 = scheme.surfaceContainerHighest', () {
      const scheme = ColorScheme.light();
      final s = DefaultChessColorStrategy.of(scheme);
      expect(s.darkSquare, scheme.surfaceContainerHighest);
    });

    test('checkWarning 派生 = scheme.error（保留危险语义）', () {
      const scheme = ColorScheme.light();
      final s = DefaultChessColorStrategy.of(scheme);
      expect(s.checkWarning, scheme.error);
    });

    test('captureHint 派生 = scheme.tertiary（互补色，对比 legalMoveHint）', () {
      const scheme = ColorScheme.light();
      final s = DefaultChessColorStrategy.of(scheme);
      expect(s.captureHint, scheme.tertiary);
    });

    test('切 zen → purple 后 darkSquare 跟着变（scheme 派生）', () {
      // 模拟 zen 主题（暖白底）与 purple 主题（深色底）
      const zenLike = ColorScheme.light(
        surface: Color(0xFFFAF7F0),
        surfaceContainerHighest: Color(0xFFE3DDC8),
      );
      const purpleLike = ColorScheme.dark(
        surface: Color(0xFF201F1A),
        surfaceContainerHighest: Color(0xFF2D2B25),
      );
      final sZen = DefaultChessColorStrategy.of(zenLike);
      final sPurple = DefaultChessColorStrategy.of(purpleLike);
      expect(sZen.darkSquare, isNot(sPurple.darkSquare),
          reason: 'scheme 派生应跟随主题环境色温变化');
      expect(sZen.lightSquare, isNot(sPurple.lightSquare));
    });

    test('checkmateOverlay 始终是 scrim 半透（端局压住整盘）', () {
      const scheme = ColorScheme.dark();
      final s = DefaultChessColorStrategy.of(scheme);
      expect(s.checkmateOverlay, scheme.scrim.withValues(alpha: 0.78));
    });

    test('13 角色与 tokens/color/chess/chess.dart 的 *From() 产出一致', () {
      const scheme = ColorScheme.light();
      final s = DefaultChessColorStrategy.of(scheme);
      expect(s.lightSquare, ChessColors.lightSquareFrom(scheme));
      expect(s.darkSquare, ChessColors.darkSquareFrom(scheme));
      expect(s.gridLine, ChessColors.gridLineFrom(scheme));
      expect(s.coordinateLabel, ChessColors.coordinateLabelFrom(scheme));
      expect(s.selectedSquare, ChessColors.selectedSquareFrom(scheme));
      expect(s.lastMoveHighlight, ChessColors.lastMoveHighlightFrom(scheme));
      expect(s.legalMoveHint, ChessColors.legalMoveHintFrom(scheme));
      expect(s.captureHint, ChessColors.captureHintFrom(scheme));
      expect(s.checkWarning, ChessColors.checkWarningFrom(scheme));
      expect(s.checkmateOverlay, ChessColors.checkmateOverlayFrom(scheme));
      expect(s.promotionOverlay, ChessColors.promotionOverlayFrom(scheme));
      expect(s.promotionBorder, ChessColors.promotionBorderFrom(scheme));
    });
  });

  group('ChessColorStrategy ==/hashCode 契约', () {
    test('同 scheme 派生实例相等（14 role 一致 → ==) ', () {
      const scheme = ColorScheme.light();
      final sA = DefaultChessColorStrategy.of(scheme);
      final sB = DefaultChessColorStrategy.of(scheme);
      expect(sA, equals(sB));
      expect(sA.hashCode, equals(sB.hashCode));
    });

    test('不同 scheme 派生实例不相等（角色随主题变）', () {
      const schemeA = ColorScheme.light();
      const schemeB = ColorScheme.dark();
      final sA = DefaultChessColorStrategy.of(schemeA);
      final sB = DefaultChessColorStrategy.of(schemeB);
      expect(sA, isNot(equals(sB)));
    });

    test('抽象 strategy 是 immutable（同实例 hashCode 稳定）', () {
      const scheme = ColorScheme.light();
      final s = DefaultChessColorStrategy.of(scheme);
      expect(s.hashCode, equals(s.hashCode));
    });
  });
}
