// 应用主题工厂（茶禅主题入口）。
//
// 设计：v6.1「主色不动 · 环境染互补色温」——
//   所有颜色统一从 ColorScheme 派生（theme.component/ 单数据源）。
//   · surface / surfaceContainerHighest / onSurface / onSurfaceVariant / outline
//     → 已在 semantic/colors.dart 按每主题环境色染好
//   · primary / primaryContainer / tertiary（互补强调）从 ColorScheme 读取
//   · error 红系不变（危险语义）
//
// 依赖层级：
//   tokens/       raw 原子色（colors / typography / spacing / radius / elevation）
//   semantic/     ColorScheme + AppColorsExtension（语义角色）
//   component/    button / card / section / input（复合组件样式）
//   this file     茶禅主题 ThemeData 工厂 + 各组件主题覆盖

import 'package:flutter/material.dart';
import 'extensions/board_color_strategy_extension.dart';
import 'extensions/color_strategy_extension.dart';
import 'extensions/game_colors_strategy_extension.dart';
import 'semantic/colors.dart';
import 'semantic/extensions.dart';
import 'semantic/typography.dart';
import 'strategy/default_board_color_strategy.dart';
import 'strategy/game_colors_strategy.dart';
import 'strategy/theme_strategy_factory.dart';

export 'semantic/extensions.dart' show AppColorsExtension;

/// 应用主题模式枚举
enum AppThemeMode {
  /// 茶禅主题（zen）—— sage 绿 + 暖米环境 + 陶土红强调。
  zen,
}

/// 应用主题配置类
class AppTheme {
  // ============================================================
  // 主题入口
  // ============================================================

  /// 获取主题显示名称
  static String getThemeDisplayName(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.zen => '茶禅主题',
    };
  }

  /// 获取主题图标
  static IconData getThemeIcon(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.zen => Icons.self_improvement,
    };
  }

  /// 根据模式获取主题数据
  static ThemeData getThemeData(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.zen => _buildTheme(
          scheme: ThemeColorSchemes.zen,
          ext: ThemeAppColors.zen,
          cardShadow: Color(0x14000000)
        ),
    };
  }

  // ============================================================
  // 通用 ThemeData 构建器
  // ============================================================
  //
  // 所有颜色统一从 ColorScheme 派生 —— 单一数据源。
  // 环境色（surface / outline / bg）由 semantic/colors.dart 按互补 hue 染好。

  static ThemeData _buildTheme({
    required ColorScheme scheme,
    required AppColorsExtension ext,
    required Color cardShadow,
  }) {
    final colorStrategy = ThemeStrategyFactory.create(scheme);
    final boardStrategy = DefaultBoardColorStrategy.of(scheme);
    final gameStrategy = DefaultGameColorsStrategy.of(scheme);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: scheme.brightness,
      textTheme: AppTextThemes.build(scheme.brightness),
      extensions: [
        ext,
        ColorStrategyExtension(colorStrategy),
        BoardColorStrategyExtension(boardStrategy),
        GameColorsStrategyExtension(gameStrategy),
      ],
      cardTheme: CardThemeData(
        elevation: 2,
        color: scheme.surface,
        shadowColor: cardShadow,
        surfaceTintColor: scheme.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurface.withValues(alpha: 0.5),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

}

