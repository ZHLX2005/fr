// 暗黑主题（第 7 套）专项回归：
// 1. scheme 定位正确（Brightness.dark + OLED 近黑 surface）
// 2. materialThemeModeProvider 对 dark 映射 ThemeMode.dark
//    （曾遗漏：switch 只列了 purple，dark 落到 `_ => ThemeMode.light`）
// 3. 7 套主题全部可构建 ThemeData 且 displayName/icon 覆盖齐全

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/theme/app_theme.dart';
import 'package:xiaodouzi_fr/core/theme/state/theme_provider.dart';
import 'package:xiaodouzi_fr/core/theme/tokens/color/theme/dark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DarkColors 调色板', () {
    test('brightness = dark，surface 贴近 OLED 纯黑', () {
      expect(DarkColors.scheme.brightness, Brightness.dark);
      expect(DarkColors.scheme.surface, const Color(0xFF131311));
      expect(DarkColors.scheme.surfaceContainerHighest, const Color(0xFF0C0C0A));
      // 无彩系定位：主色是暖中性浅石墨（R≈G≈B，暖调容差 12 内；
      // 混入紫 / 蓝等色相会立刻超限）
      final p = DarkColors.scheme.primary;
      expect((p.r - p.g).abs() * 255, lessThan(12));
      expect((p.g - p.b).abs() * 255, lessThan(12));
    });
  });

  group('materialThemeModeProvider 深色映射', () {
    test('dark 与 purple 都映射 ThemeMode.dark（light 主题落 light）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      SharedPreferences.setMockInitialValues({});
      // 逐个 setMode 后读派生值
      for (final mode in AppThemeMode.values) {
        container.read(themeNotifierProvider.notifier).state = mode;
        final tm = container.read(materialThemeModeProvider);
        final expected = (mode == AppThemeMode.purple || mode == AppThemeMode.dark)
            ? ThemeMode.dark
            : ThemeMode.light;
        expect(tm, expected, reason: '${mode.name} 应映射 $expected');
      }
    });
  });

  group('7 套主题元数据完整性', () {
    test('每套主题都有 displayName / icon / ThemeData', () {
      expect(AppThemeMode.values.length, 7);
      for (final mode in AppThemeMode.values) {
        expect(AppTheme.getThemeDisplayName(mode), isNotEmpty,
            reason: '${mode.name} 缺 displayName');
        expect(AppTheme.getThemeIcon(mode), isNotNull,
            reason: '${mode.name} 缺 icon');
        expect(AppTheme.getThemeData(mode), isNotNull,
            reason: '${mode.name} 构建 ThemeData 失败');
      }
      // 文案定位：暗黑显示名与图标固定
      expect(AppTheme.getThemeDisplayName(AppThemeMode.dark), '暗黑主题');
      expect(AppTheme.getThemeIcon(AppThemeMode.dark), Icons.contrast);
    });
  });
}
