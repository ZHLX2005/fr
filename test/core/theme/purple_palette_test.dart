// 暮紫主题的口径（fr #12：把「紫色味道太重」钉成可测的数）。
//
// 反馈原话是「更加偏向银白月光色，紫色味道太重了」。这话在代码里只有一种
// 落法：**彩度上限 + 亮度下限**。紫味重 = sat 高；月光 = 亮且偏白。
// 写死色值容易在下次重配时又飘回去，所以把口径写成断言。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/design_tokens/color/palettes/purple.dart';

/// WCAG 相对亮度。
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final cs = PurpleColors.scheme;

  group('暮紫 = 银白月光', () {
    test('主色彩度不回到「一块紫」：S ≤ 22%，L ≥ 75%', () {
      final hsl = HSLColor.fromColor(cs.primary);
      expect(hsl.saturation, lessThanOrEqualTo(0.22), reason: 'sat 一高就是紫，不是月光');
      expect(hsl.lightness, greaterThanOrEqualTo(0.75), reason: '月光得亮');
    });

    test('色相仍是暮光那一束（240°~275°），不是把紫换成了别的颜色', () {
      final h = HSLColor.fromColor(cs.primary).hue;
      expect(h, inInclusiveRange(240, 275));
    });

    test('主色比正文暗一档：才不会和正文抢「该看哪儿」', () {
      expect(_lum(cs.primary), lessThan(_lum(cs.onSurface)));
    });

    test('环境是近中性冷灰：surface 的紫味（B−R）不超过 4/255', () {
      final bMinusR = (cs.surface.b * 255).round() - (cs.surface.r * 255).round();
      expect(bMinusR, inInclusiveRange(0, 4), reason: '底色一紫，主色那点紫就显脏');
      expect(cs.surface.r, lessThan(0.2), reason: '它是深色主题');
    });
  });

  group('对比度（深色底上仍要读得清）', () {
    test('primary / surface ≥ 4.5', () {
      expect(_contrast(cs.primary, cs.surface), greaterThanOrEqualTo(4.5));
    });

    test('onSurface / surface ≥ 7', () {
      expect(_contrast(cs.onSurface, cs.surface), greaterThanOrEqualTo(7));
    });

    test('onSurfaceVariant / surface ≥ 4.5（小字元信息也用这一档）', () {
      expect(_contrast(cs.onSurfaceVariant, cs.surface), greaterThanOrEqualTo(4.5));
    });

    test('onPrimary / primary ≥ 4.5（实心按钮上的字）', () {
      expect(_contrast(cs.onPrimary, cs.primary), greaterThanOrEqualTo(4.5));
    });
  });
}
