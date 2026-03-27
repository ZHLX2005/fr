import 'package:flutter/material.dart';

/// 应用主题模式枚举
enum AppThemeMode {
  /// 浅色模式（默认蓝色主题）
  light,

  /// 深色模式（夜间模式）
  dark,

  /// 粉红色主题（浅色模式）
  pink,
}

/// 应用主题配置类
class AppTheme {
  /// 获取主题显示名称
  static String getThemeDisplayName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return '默认主题';
      case AppThemeMode.dark:
        return '夜间模式';
      case AppThemeMode.pink:
        return '粉红主题';
    }
  }

  /// 获取主题图标
  static IconData getThemeIcon(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return Icons.light_mode;
      case AppThemeMode.dark:
        return Icons.dark_mode;
      case AppThemeMode.pink:
        return Icons.favorite;
    }
  }

  /// 创建浅色主题数据
  static ThemeData createLightTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      brightness: Brightness.light,
    );
  }

  /// 创建深色主题数据
  static ThemeData createDarkTheme() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      brightness: Brightness.dark,
    );
  }

  /// 创建粉红色主题数据
  static ThemeData createPinkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF69B4), // HotPink
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: Brightness.light,
      // 自定义粉红色主题的特殊样式
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        centerTitle: true,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 4,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// 根据模式获取主题数据
  static ThemeData getThemeData(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return createLightTheme();
      case AppThemeMode.dark:
        return createDarkTheme();
      case AppThemeMode.pink:
        return createPinkTheme();
    }
  }

  /// 创建主题预览颜色（用于预览卡片）
  static Map<String, Color> getPreviewColors(AppThemeMode mode) {
    final theme = getThemeData(mode);
    final colorScheme = theme.colorScheme;

    return {
      'primary': colorScheme.primary,
      'secondary': colorScheme.secondary,
      'tertiary': colorScheme.tertiary,
      'surface': colorScheme.surface,
      'background': colorScheme.surface,
      'error': colorScheme.error,
    };
  }
}
