import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/color/color_utils.dart';

void main() {
  group('ColorUtils.desaturate', () {
    test('降低饱和度但保留色相与明度', () {
      const input = Color(0xFF2196F3);
      final original = HSLColor.fromColor(input);
      final result = HSLColor.fromColor(ColorUtils.desaturate(input, factor: 0.85));

      // 容差 0.005：HSL -> 8-bit RGB -> HSL 往返存在固有量化误差（此输入实测 0.0021）。
      // 仍远小于 factor 失效时的偏差（0.85 vs 1.0 相差 0.135），足以判别。
      expect(result.saturation, closeTo(original.saturation * 0.85, 0.005));
      expect(result.hue, closeTo(original.hue, 0.5));
      expect(result.lightness, closeTo(original.lightness, 0.001));
    });

    test('默认系数为 0.85', () {
      const input = Color(0xFFFF6B95);
      expect(
        ColorUtils.desaturate(input),
        equals(ColorUtils.desaturate(input, factor: 0.85)),
      );
    });

    test('纯灰色无变化', () {
      const grey = Color(0xFF808080);
      final result = ColorUtils.desaturate(grey);
      expect(HSLColor.fromColor(result).saturation, closeTo(0.0, 0.001));
    });

    test('保留 alpha 通道', () {
      const translucent = Color(0x802196F3);
      final result = ColorUtils.desaturate(translucent);
      expect(result.a, closeTo(translucent.a, 0.001));
    });

    test('factor 被 clamp 到 0..1', () {
      const input = Color(0xFF2196F3);
      final over = HSLColor.fromColor(ColorUtils.desaturate(input, factor: 5.0));
      final origin = HSLColor.fromColor(input);
      expect(over.saturation, closeTo(origin.saturation, 0.001));

      final under = HSLColor.fromColor(ColorUtils.desaturate(input, factor: -1.0));
      expect(under.saturation, closeTo(0.0, 0.001));
    });
  });
}
