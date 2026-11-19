// 面板底色必须**等于**页面背景 —— 回归护栏。
//
// 这条原先是 surface → surfaceContainerHighest 的纵向渐变：展开后下半截比
// 页面背景更沉，整块读起来像贴在页底的一层深色色块。现在浮卡布局不动，
// 只把面板底拉平到背景。谁再往这里塞回第二层表面，测试会立刻红。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/screens/profile/lab/lab_panel/lab_panel_colors.dart';

void main() {
  for (final brightness in Brightness.values) {
    group('LabPanelColors（$brightness）', () {
      final cs = ColorScheme.fromSeed(
        seedColor: const Color(0xFF5B7CFA),
        brightness: brightness,
      );
      final pc = LabPanelColors.resolve(cs, brightness: brightness);

      test('面板底色就是页面背景色（同值，不是「接近」）', () {
        expect(pc.background, cs.surface);
      });

      test('面板底色不透明：展开时必须盖住下面的 demo 网格', () {
        expect(pc.background.a, 1.0);
      });

      test('浮卡与文字色仍由 scheme 派生（改底色不该动它们）', () {
        expect(pc.accent, cs.primary);
        expect(pc.text, cs.onSurface);
        expect(pc.mutedText, cs.onSurfaceVariant);
      });
    });
  }
}
