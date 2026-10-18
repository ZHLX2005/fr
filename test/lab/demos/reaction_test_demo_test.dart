import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/theme/app_theme.dart';
import 'package:xiaodouzi_fr/lab/demos/reaction_test_demo.dart';

/// WCAG 相对对比度。
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 当前相位底色（AnimatedContainer 的目标色；颜色存在 decoration 里，无公开 color getter）。
Color _phaseBg(WidgetTester tester) {
  final box = tester.widget<AnimatedContainer>(
    find.byType(AnimatedContainer).first,
  );
  return (box.decoration! as BoxDecoration).color!;
}

void main() {
  group('ReactionPalette — 语义色可读性守卫', () {
    test('每相位主/次前景对比度 ≥4.5:1', () {
      // [底色, 主前景, 次级前景]
      final phases = <String, List<Color>>{
        'neutral（idle/result）': [
          ReactionPalette.neutralBg,
          ReactionPalette.neutralFg,
          ReactionPalette.neutralMuted,
        ],
        'stop（waiting）': [
          ReactionPalette.stopBg,
          ReactionPalette.stopFg,
          ReactionPalette.stopMuted,
        ],
        'go（ready）': [
          ReactionPalette.goBg,
          ReactionPalette.goFg,
          ReactionPalette.goMuted,
        ],
        'early（tooEarly）': [
          ReactionPalette.earlyBg,
          ReactionPalette.earlyFg,
          ReactionPalette.earlyMuted,
        ],
      };

      phases.forEach((name, c) {
        expect(_contrast(c[1], c[0]), greaterThanOrEqualTo(4.5),
            reason: '$name 主前景对比度不足');
        expect(_contrast(c[2], c[0]), greaterThanOrEqualTo(4.5),
            reason: '$name 次级前景对比度不足');
      });
    });

    test('中性强调色在深底上可读', () {
      expect(
        _contrast(ReactionPalette.neutralAccent, ReactionPalette.neutralBg),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('底色与前景不同色 —— 旧实现 idle/result 底色与提示文字同为 onSurface', () {
      expect(ReactionPalette.neutralFg, isNot(ReactionPalette.neutralBg));
      expect(ReactionPalette.stopFg, isNot(ReactionPalette.stopBg));
      expect(ReactionPalette.goFg, isNot(ReactionPalette.goBg));
      expect(ReactionPalette.earlyFg, isNot(ReactionPalette.earlyBg));
    });

    test('红 / 绿 / 琥珀三态底色互不相同（旧实现暮紫下 ready 与 waiting 同为紫）', () {
      final bgs = {
        ReactionPalette.stopBg,
        ReactionPalette.goBg,
        ReactionPalette.earlyBg,
      };
      expect(bgs.length, 3);
    });
  });

  group('反应力测试 — 主屏信号灯色不随主题漂移', () {
    for (final mode in AppThemeMode.values) {
      testWidgets('${AppTheme.getThemeDisplayName(mode)}：四相位底色固定', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.getThemeData(mode),
            home: const ReactionTestPage(),
          ),
        );

        // idle：中性深底
        expect(_phaseBg(tester), ReactionPalette.neutralBg);

        // waiting：点击开始 → 红（别点）
        await tester.tap(find.text('点击屏幕开始'));
        await tester.pump();
        expect(_phaseBg(tester), ReactionPalette.stopBg);

        // ready：推进随机延迟（1.2s ~ 4.2s）→ 绿（可以点）
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        expect(_phaseBg(tester), ReactionPalette.goBg);

        // result：绿色态点击 → 中性底（顺带避免遗留计时器）
        await tester.tap(find.text('点击！'));
        await tester.pump();
        expect(_phaseBg(tester), ReactionPalette.neutralBg);
      });
    }

    testWidgets('抢跳：红灯期间点击为固定琥珀色', (tester) async {
      // 用墨白主题 —— 旧实现下该主题的 ready 与 idle 底色同为 #1A1A1A
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.getThemeData(AppThemeMode.ink),
          home: const ReactionTestPage(),
        ),
      );

      await tester.tap(find.text('点击屏幕开始'));
      await tester.pump();
      await tester.tap(find.text('等待绿色…'));
      await tester.pump();

      expect(_phaseBg(tester), ReactionPalette.earlyBg);
    });

    testWidgets('墨白主题下 ready 底色不再等于 idle 底色（"变绿"必须可见）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.getThemeData(AppThemeMode.ink),
          home: const ReactionTestPage(),
        ),
      );

      final idleBg = _phaseBg(tester);
      await tester.tap(find.text('点击屏幕开始'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();

      expect(_phaseBg(tester), ReactionPalette.goBg);
      expect(_phaseBg(tester), isNot(idleBg));
    });
  });
}
