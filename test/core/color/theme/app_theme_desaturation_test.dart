import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/color/theme/app_theme.dart';

void main() {
  group('AppTheme 降饱和', () {
    test('全部 7 套预设的 primary 饱和度都被降低', () {
      for (final mode in AppThemeMode.values) {
        final primary = AppTheme.getThemeData(mode).colorScheme.primary;
        final raw = AppTheme.rawPrimaryOf(mode);
        final actual = HSLColor.fromColor(primary).saturation;
        final expected =
            HSLColor.fromColor(raw).saturation * AppTheme.kSaturationFactor;
        expect(actual, closeTo(expected, 0.005),
            reason: '$mode 的 primary 未按 0.85 降饱和');
      }
    });

    test('surface 与 background 保持原饱和度（暖白奶油底色不被洗白）', () {
      final light = AppTheme.getThemeData(AppThemeMode.light);
      expect(light.colorScheme.surface, equals(const Color(0xFFFFF8F0)));
    });

    test('组件主题跟随 primary 一起降饱和', () {
      for (final mode in AppThemeMode.values) {
        final theme = AppTheme.getThemeData(mode);
        final primary = theme.colorScheme.primary;
        expect(theme.floatingActionButtonTheme.backgroundColor, equals(primary),
            reason: '$mode 的 FAB 背景色与降饱和后的 primary 不一致');
        expect(
          theme.bottomNavigationBarTheme.selectedItemColor,
          equals(primary),
          reason: '$mode 的底栏选中色与降饱和后的 primary 不一致',
        );
        expect(theme.appBarTheme.surfaceTintColor, equals(primary),
            reason: '$mode 的 AppBar surfaceTint 与降饱和后的 primary 不一致');
        expect(
          theme.elevatedButtonTheme.style?.backgroundColor?.resolve({}),
          equals(primary),
          reason: '$mode 的 ElevatedButton 背景与降饱和后的 primary 不一致',
        );
        expect(
          theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
          equals(primary),
          reason: '$mode 的 FilledButton 背景与降饱和后的 primary 不一致',
        );
      }
    });

    test('色相保持不变', () {
      for (final mode in AppThemeMode.values) {
        final primary = AppTheme.getThemeData(mode).colorScheme.primary;
        final raw = AppTheme.rawPrimaryOf(mode);
        expect(HSLColor.fromColor(primary).hue,
            closeTo(HSLColor.fromColor(raw).hue, 1.0),
            reason: '$mode 的色相被改动了');
      }
    });

    test('渐变扩展的颜色也被降饱和', () {
      const gradientModes = [
        AppThemeMode.pink,
        AppThemeMode.green,
        AppThemeMode.orange,
        AppThemeMode.rose,
        AppThemeMode.purple,
      ];

      for (final mode in gradientModes) {
        final desaturated = AppTheme.getThemeData(mode);
        final rawStart = AppTheme.rawGradientStartOf(mode);
        final rawEnd = AppTheme.rawGradientEndOf(mode);
        final actualStart = AppTheme.gradientStartOf(desaturated);
        final actualEnd = AppTheme.gradientEndOf(desaturated);

        expect(actualStart, isNotNull, reason: '$mode 缺少渐变起始色');
        expect(actualEnd, isNotNull, reason: '$mode 缺少渐变结束色');
        expect(
          HSLColor.fromColor(actualStart!).saturation,
          closeTo(
            HSLColor.fromColor(rawStart!).saturation * AppTheme.kSaturationFactor,
            0.005,
          ),
          reason: '$mode 的 gradientStart 未降饱和',
        );
        expect(
          HSLColor.fromColor(actualEnd!).saturation,
          closeTo(
            HSLColor.fromColor(rawEnd!).saturation * AppTheme.kSaturationFactor,
            0.01,
          ),
          reason: '$mode 的 gradientEnd 未降饱和',
        );
      }
    });

    test('亮暗属性未被破坏', () {
      expect(AppTheme.getThemeData(AppThemeMode.light).brightness,
          Brightness.light);
      expect(AppTheme.getThemeData(AppThemeMode.dark).brightness,
          Brightness.dark);
      expect(AppTheme.getThemeData(AppThemeMode.purple).brightness,
          Brightness.dark);
    });
  });
}