// 应用主题工厂（zen / purple / ink / rose / lemon 主题入口）。
//
// 设计：v6.1「主色不动 · 环境染互补色温」——
//   所有颜色统一从 ColorScheme 派生（theme.component/ 单数据源）。
//   · 5 套 ColorScheme 在 tokens/color/theme/<mode>.dart 集中维护
//   · 切主题 = 换 scheme 实例；strategy 层零主题感知（5 个 strategy 实现单一 default）
//
// 依赖层级：
//   tokens/         raw 原子色 + 5 套主题调色板 + 各用途色板
//   colors/strategy/  5 个 strategy 默认派生规则
//   extensions/     ThemeExtension 注入器
//   component/      全局组件主题 + 家族/域专属子目录
//   text_theme.dart AppTextThemes（与 ColorScheme 平级）
//   state/          Riverpod 状态层（themeNotifierProvider）

import 'package:flutter/material.dart';
import 'colors/factory.dart';
import 'colors/theme_mode.dart' show AppThemeMode;
import 'extensions/board_color_strategy_extension.dart';
import 'extensions/color_strategy_extension.dart';
import 'extensions/team_avatar_strategy_extension.dart';
import 'extensions/tetris_colors_strategy_extension.dart';
import 'extensions/torch_protect_strategy_extension.dart';
import 'text_theme.dart';
import 'tokens/colors.dart';
import 'tokens/color/theme/zen.dart' as zen_t;
import 'tokens/color/theme/purple.dart' as purple_t;
import 'tokens/color/theme/ink.dart' as ink_t;
import 'tokens/color/theme/rose.dart' as rose_t;
import 'tokens/color/theme/lemon.dart' as lemon_t;

export 'colors/theme_mode.dart' show AppThemeMode;
export 'tokens/colors.dart' show AppColorsExtension;

/// 应用主题配置类
class AppTheme {
  // ============================================================
  // 主题入口
  // ============================================================

  /// 获取主题显示名称
  static String getThemeDisplayName(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.purple => '暮紫主题',
      AppThemeMode.zen => '茶禅主题',
      AppThemeMode.ink => '墨白主题',
      AppThemeMode.rose => '粉雾海盐主题',
      AppThemeMode.lemon => '柠檬鼠尾草主题',
    };
  }

  /// 获取主题图标
  static IconData getThemeIcon(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.purple => Icons.nights_stay,
      AppThemeMode.zen => Icons.self_improvement,
      AppThemeMode.ink => Icons.brush_outlined,
      AppThemeMode.rose => Icons.favorite,
      AppThemeMode.lemon => Icons.eco,
    };
  }

  /// 根据模式获取主题数据
  static ThemeData getThemeData(AppThemeMode mode) {
    // 唯一数据源：scheme + appColors 都从 tokens/color/theme/<mode>.dart 取
    return switch (mode) {
      AppThemeMode.purple => _buildTheme(
          scheme: purple_t.PurpleColors.scheme,
          ext: purple_t.PurpleColors.appColors,
          cardShadow: Color(0x66000000),
        ),
      AppThemeMode.zen => _buildTheme(
          scheme: zen_t.ZenColors.scheme,
          ext: zen_t.ZenColors.appColors,
          cardShadow: Color(0x14000000),
        ),
      AppThemeMode.ink => _buildTheme(
          scheme: ink_t.InkColors.scheme,
          ext: ink_t.InkColors.appColors,
          cardShadow: Color(0x14000000),
        ),
      AppThemeMode.rose => _buildTheme(
          scheme: rose_t.RoseColors.scheme,
          ext: rose_t.RoseColors.appColors,
          cardShadow: Color(0x14000000),
        ),
      AppThemeMode.lemon => _buildTheme(
          scheme: lemon_t.LemonColors.scheme,
          ext: lemon_t.LemonColors.appColors,
          cardShadow: Color(0x14000000),
        ),
    };
  }

  // ============================================================
  // 通用 ThemeData 构建器
  // ============================================================
  //
  // 所有颜色统一从传入的 ColorScheme 派生 —— 单一数据源。

  static ThemeData _buildTheme({
    required ColorScheme scheme,
    required AppColorsExtension ext,
    required Color cardShadow,
  }) {
    final colorStrategy = ThemeStrategyFactory.create(scheme);
    final boardStrategy = ThemeStrategyFactory.createBoardColorStrategy(scheme);
    final tetrisColorsStrategy = ThemeStrategyFactory.createTetrisColorsStrategy(scheme);
    final teamAvatarStrategy = ThemeStrategyFactory.createTeamAvatarStrategy();
    final torchProtectStrategy = ThemeStrategyFactory.createTorchProtectStrategy(scheme);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: scheme.brightness,
      textTheme: AppTextThemes.build(scheme.brightness),
      extensions: [
        ext,
        ColorStrategyExtension(colorStrategy),
        BoardColorStrategyExtension(boardStrategy),
        TetrisColorsStrategyExtension(tetrisColorsStrategy),
        TeamAvatarStrategyExtension(teamAvatarStrategy),
        TorchProtectStrategyExtension(torchProtectStrategy),
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
        backgroundColor: scheme.surface,
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
        backgroundColor: scheme.surface,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurface.withValues(alpha: 0.5),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

}