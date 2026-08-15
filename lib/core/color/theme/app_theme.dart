import 'package:flutter/material.dart';

/// 应用主题模式枚举
enum AppThemeMode {
  /// 浅色模式（默认墨青主题）
  light,

  /// 深色模式（夜间模式）
  dark,

  /// 茶玫主题（浅色模式）
  pink,

  /// 苔绿主题（浅色模式）
  green,

  /// 陶橙主题（活力暖色调）
  orange,

  /// 玫紫主题（优雅暖色调）
  rose,

  /// 暮紫主题（低饱和度）
  purple,
}

/// 应用主题配置类
///
/// 设计语言：v5 — 莫兰迪加灰度版。
/// 在 v4 色彩身份基础上加莫兰迪灰度：主色 S=22-32%，L=55-68%。
/// 每个主色有明显 hue 倾向（蓝/粉/绿/橙/玫/紫），但带柔和灰度，
/// 哑光质感。状态色也按莫兰迪标准重设。
/// 主题配套含完整 Material 3 ColorScheme + 状态色（4 套）+ 分类色板（8 色），
/// 通过 [AppColorsExtension] 在 widget 中读取。
class AppTheme {
  /// 获取主题显示名称
  static String getThemeDisplayName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return '墨青主题';
      case AppThemeMode.dark:
        return '夜间模式';
      case AppThemeMode.pink:
        return '茶玫主题';
      case AppThemeMode.green:
        return '苔绿主题';
      case AppThemeMode.orange:
        return '陶橙主题';
      case AppThemeMode.rose:
        return '玫紫主题';
      case AppThemeMode.purple:
        return '暮紫主题';
    }
  }

  /// 获取主题图标
  static IconData getThemeIcon(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return Icons.water_drop_outlined;
      case AppThemeMode.dark:
        return Icons.dark_mode;
      case AppThemeMode.pink:
        return Icons.local_florist;
      case AppThemeMode.green:
        return Icons.eco;
      case AppThemeMode.orange:
        return Icons.wb_sunny_outlined;
      case AppThemeMode.rose:
        return Icons.spa_outlined;
      case AppThemeMode.purple:
        return Icons.nights_stay;
    }
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
      case AppThemeMode.green:
        return createGreenTheme();
      case AppThemeMode.orange:
        return createOrangeTheme();
      case AppThemeMode.rose:
        return createRoseTheme();
      case AppThemeMode.purple:
        return createPurpleTheme();
    }
  }

  // ============================================================
  // 7 主题实现 — v5 莫兰迪加灰度版
  // ============================================================

  /// 创建墨青主题（默认，浅色）— 莫兰迪蓝
  static ThemeData createLightTheme() {
    return _buildTheme(
      brightness: Brightness.light,
      tokens: const _Tokens(
        primary: Color(0xFF82A1BF),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFFECF0F4),
        onPrimaryContainer: Color(0xFF1F3A5C),
        secondary: Color(0xFFA0B1CA),
        onSecondary: Color(0xFFFFFFFF),
        secondaryContainer: Color(0xFFEFF2F5),
        onSecondaryContainer: Color(0xFF2C4862),
        tertiary: Color(0xFF749FB4),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFFE9EFF1),
        onTertiaryContainer: Color(0xFF1F3F54),
        surface: Color(0xFFF6F7F9),
        onSurface: Color(0xFF1F1B17),
        surfaceVariant: Color(0xFFEBF0F4),
        onSurfaceVariant: Color(0xFF495969),
        background: Color(0xFFF6F7F9),
        onBackground: Color(0xFF1F1B17),
        error: Color(0xFFB6887C),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFF5E1DC),
        onErrorContainer: Color(0xFF4A1F14),
        outline: Color(0xFFD9E0E8),
        outlineVariant: Color(0xFFE7EBEF),
        surfaceTint: Color(0xFF82A1BF),
      ),
      colors: const _ExtColors(
        success: Color(0xFF84BD9C),
        onSuccess: Color(0xFFFFFFFF),
        successContainer: Color(0xFFDEEDE4),
        onSuccessContainer: Color(0xFF1F3F26),
        warning: Color(0xFFC2AD8E),
        onWarning: Color(0xFFFFFFFF),
        warningContainer: Color(0xFFF0ECE5),
        onWarningContainer: Color(0xFF3F2D14),
        info: Color(0xFF82A1BF),
        onInfo: Color(0xFFFFFFFF),
        infoContainer: Color(0xFFECF0F4),
        onInfoContainer: Color(0xFF1F3A5C),
        category: [
          Color(0xFF82A1BF), Color(0xFFA0B1CA), Color(0xFF749FB4),
          Color(0xFFAF9CC6), Color(0xFF86A8B8), Color(0xFFDEB8A6),
          Color(0xFF8AB276), Color(0xFFD9ABB6),
        ],
      ),
      surfaceContainer: const Color(0xFFFFFFFF),
      cardSurface: const Color(0xFFFFFFFF),
      cardShadow: const Color(0x14000000),
      cardForeground: const Color(0xFF1A1A1A),
      cardAccent: const Color(0xFF82A1BF),
      cardAccentContainer: const Color(0xFFECF0F4),
      appBarBackground: const Color(0xFFF6F7F9),
      appBarForeground: const Color(0xFF1F1B17),
      unselectedItem: const Color(0xFF9E9E9E),
      bottomBar: const Color(0xFFFFFFFF),
      filledButtonSurface: const Color(0xFFFFFFFF),
      gradient: null,
    );
  }

  /// 创建夜间主题（深色）— 莫兰迪深蓝
  static ThemeData createDarkTheme() {
    return _buildTheme(
      brightness: Brightness.dark,
      tokens: const _Tokens(
        primary: Color(0xFF9AADC1),
        onPrimary: Color(0xFF0F1419),
        primaryContainer: Color(0xFF2D3748),
        onPrimaryContainer: Color(0xFFCBD5E1),
        secondary: Color(0xFFB5C0CF),
        onSecondary: Color(0xFF0F1419),
        secondaryContainer: Color(0xFF374151),
        onSecondaryContainer: Color(0xFFCBD5E1),
        tertiary: Color(0xFF8CA8B5),
        onTertiary: Color(0xFF0F1419),
        tertiaryContainer: Color(0xFF3D4D5E),
        onTertiaryContainer: Color(0xFFC9DBE8),
        surface: Color(0xFF1A1D24),
        onSurface: Color(0xFFE5E7EB),
        surfaceVariant: Color(0xFF252932),
        onSurfaceVariant: Color(0xFF9CA3AF),
        background: Color(0xFF0F1116),
        onBackground: Color(0xFFE5E7EB),
        error: Color(0xFFC99286),
        onError: Color(0xFF0F1419),
        errorContainer: Color(0xFF4A2A24),
        onErrorContainer: Color(0xFFF0CCC2),
        outline: Color(0xFF374151),
        outlineVariant: Color(0xFF252932),
        surfaceTint: Color(0xFF9AADC1),
      ),
      colors: const _ExtColors(
        success: Color(0xFF95B89E),
        onSuccess: Color(0xFF0F1419),
        successContainer: Color(0xFF2A3F30),
        onSuccessContainer: Color(0xFFB8D6BE),
        warning: Color(0xFFD4B68E),
        onWarning: Color(0xFF0F1419),
        warningContainer: Color(0xFF4A3D24),
        onWarningContainer: Color(0xFFF0D9A8),
        info: Color(0xFF9AADC1),
        onInfo: Color(0xFF0F1419),
        infoContainer: Color(0xFF2D3748),
        onInfoContainer: Color(0xFFCBD5E1),
        category: [
          Color(0xFF9AADC1), Color(0xFFB5C0CF), Color(0xFF6E8AA0),
          Color(0xFFB8A8D0), Color(0xFF8CA8B5), Color(0xFFD4B68E),
          Color(0xFF809C63), Color(0xFFB67C8B),
        ],
      ),
      surfaceContainer: const Color(0xFF1A1D24),
      cardSurface: const Color(0xFF1E1E1E),
      cardShadow: const Color(0x4D000000),
      cardForeground: const Color(0xFFE0E0E0),
      cardAccent: const Color(0xFF9AADC1),
      cardAccentContainer: const Color(0xFF2D3748),
      appBarBackground: const Color(0xFF1A1D24),
      appBarForeground: const Color(0xFFE5E7EB),
      unselectedItem: const Color(0xFF757575),
      bottomBar: const Color(0xFF1E1E1E),
      filledButtonSurface: const Color(0xFF1A1D24),
      gradient: null,
    );
  }

  /// 创建茶玫主题（浅色）— 莫兰迪粉
  static ThemeData createPinkTheme() {
    return _buildTheme(
      brightness: Brightness.light,
      tokens: const _Tokens(
        primary: Color(0xFFDEB5BD),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFFF7EEEF),
        onPrimaryContainer: Color(0xFF5A2233),
        secondary: Color(0xFFE1C1C5),
        onSecondary: Color(0xFF4A1F26),
        secondaryContainer: Color(0xFFF8F1F2),
        onSecondaryContainer: Color(0xFF6B2E3D),
        tertiary: Color(0xFFD5A5B6),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFFF5EAEE),
        onTertiaryContainer: Color(0xFF4D1F38),
        surface: Color(0xFFF9F5F6),
        onSurface: Color(0xFF1F1B17),
        surfaceVariant: Color(0xFFF5EBED),
        onSurfaceVariant: Color(0xFF694950),
        background: Color(0xFFF9F5F6),
        onBackground: Color(0xFF1F1B17),
        error: Color(0xFFB6887C),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFF5E1DC),
        onErrorContainer: Color(0xFF4A1F14),
        outline: Color(0xFFEAD7DB),
        outlineVariant: Color(0xFFF0E6E8),
        surfaceTint: Color(0xFFDEB5BD),
      ),
      colors: const _ExtColors(
        success: Color(0xFF84BD9C),
        onSuccess: Color(0xFFFFFFFF),
        successContainer: Color(0xFFDEEDE4),
        onSuccessContainer: Color(0xFF1F3F26),
        warning: Color(0xFFC2AD8E),
        onWarning: Color(0xFFFFFFFF),
        warningContainer: Color(0xFFF0ECE5),
        onWarningContainer: Color(0xFF3F2D14),
        info: Color(0xFF82A1BF),
        onInfo: Color(0xFFFFFFFF),
        infoContainer: Color(0xFFECF0F4),
        onInfoContainer: Color(0xFF1F3A5C),
        category: [
          Color(0xFFDEB5BD), Color(0xFFE1C1C5), Color(0xFFD5A5B6),
          Color(0xFFB5A6D0), Color(0xFFCDA1AB), Color(0xFFDEB8A6),
          Color(0xFF8CAEB6), Color(0xFF82A1BF),
        ],
      ),
      surfaceContainer: const Color(0xFFFFFFFF),
      cardSurface: const Color(0xFFFFFFFF),
      cardShadow: const Color(0x14000000),
      cardForeground: const Color(0xFF2D1F1F),
      cardAccent: const Color(0xFFDEB5BD),
      cardAccentContainer: const Color(0xFFF7EEEF),
      appBarBackground: const Color(0xFFF9F5F6),
      appBarForeground: const Color(0xFF5A2233),
      unselectedItem: const Color(0xFFD4A0AD),
      bottomBar: const Color(0xFFFFFFFF),
      filledButtonSurface: const Color(0xFFFFFFFF),
      gradient: const _PinkThemeColors(
        gradientStart: Color(0xFFD09AA5),
        gradientEnd: Color(0xFFDBB8BC),
      ),
    );
  }

  /// 创建苔绿主题（浅色）— 莫兰迪绿
  static ThemeData createGreenTheme() {
    return _buildTheme(
      brightness: Brightness.light,
      tokens: const _Tokens(
        primary: Color(0xFF8AB276),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFFEEF4EC),
        onPrimaryContainer: Color(0xFF213F1A),
        secondary: Color(0xFF9DBE93),
        onSecondary: Color(0xFF1F2A14),
        secondaryContainer: Color(0xFFF1F5EF),
        onSecondaryContainer: Color(0xFF2C4627),
        tertiary: Color(0xFF87A668),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFFEDF1E9),
        onTertiaryContainer: Color(0xFF2A351A),
        surface: Color(0xFFF7F9F6),
        onSurface: Color(0xFF1F1B17),
        surfaceVariant: Color(0xFFEEF4EB),
        onSurfaceVariant: Color(0xFF546949),
        background: Color(0xFFF7F9F6),
        onBackground: Color(0xFF1F1B17),
        error: Color(0xFFB6887C),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFF5E1DC),
        onErrorContainer: Color(0xFF4A1F14),
        outline: Color(0xFFDEE9D8),
        outlineVariant: Color(0xFFE9EFE6),
        surfaceTint: Color(0xFF8AB276),
      ),
      colors: const _ExtColors(
        success: Color(0xFF84BD9C),
        onSuccess: Color(0xFFFFFFFF),
        successContainer: Color(0xFFDEEDE4),
        onSuccessContainer: Color(0xFF1F3F26),
        warning: Color(0xFFC2AD8E),
        onWarning: Color(0xFFFFFFFF),
        warningContainer: Color(0xFFF0ECE5),
        onWarningContainer: Color(0xFF3F2D14),
        info: Color(0xFF82A1BF),
        onInfo: Color(0xFFFFFFFF),
        infoContainer: Color(0xFFECF0F4),
        onInfoContainer: Color(0xFF1F3A5C),
        category: [
          Color(0xFF8AB276), Color(0xFF9DBE93), Color(0xFF87A668),
          Color(0xFFB8B287), Color(0xFF7DB277), Color(0xFF86B0B5),
          Color(0xFFB88686), Color(0xFFAF9CC6),
        ],
      ),
      surfaceContainer: const Color(0xFFFFFFFF),
      cardSurface: const Color(0xFFFFFFFF),
      cardShadow: const Color(0x14000000),
      cardForeground: const Color(0xFF1F2418),
      cardAccent: const Color(0xFF8AB276),
      cardAccentContainer: const Color(0xFFEEF4EC),
      appBarBackground: const Color(0xFFF7F9F6),
      appBarForeground: const Color(0xFF213F1A),
      unselectedItem: const Color(0xFF9CA3AF),
      bottomBar: const Color(0xFFFFFFFF),
      filledButtonSurface: const Color(0xFFFFFFFF),
      gradient: const _GreenThemeColors(
        gradientStart: Color(0xFF83A871),
        gradientEnd: Color(0xFF97B48D),
      ),
    );
  }

  /// 创建陶橙主题（浅色）— 莫兰迪橙
  static ThemeData createOrangeTheme() {
    return _buildTheme(
      brightness: Brightness.light,
      tokens: const _Tokens(
        primary: Color(0xFFDEB8A6),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFFF8F0ED),
        onPrimaryContainer: Color(0xFF4F2A14),
        secondary: Color(0xFFE5CEBD),
        onSecondary: Color(0xFF4A2D14),
        secondaryContainer: Color(0xFFF9F4F1),
        onSecondaryContainer: Color(0xFF5F3820),
        tertiary: Color(0xFFD69F95),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFFF6EBE9),
        onTertiaryContainer: Color(0xFF4A1F14),
        surface: Color(0xFFFAF7F5),
        onSurface: Color(0xFF1F1B17),
        surfaceVariant: Color(0xFFF5EEEA),
        onSurfaceVariant: Color(0xFF705242),
        background: Color(0xFFFAF7F5),
        onBackground: Color(0xFF1F1B17),
        error: Color(0xFFB6887C),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFF5E1DC),
        onErrorContainer: Color(0xFF4A1F14),
        outline: Color(0xFFEBDDD6),
        outlineVariant: Color(0xFFF1E9E4),
        surfaceTint: Color(0xFFDEB8A6),
      ),
      colors: const _ExtColors(
        success: Color(0xFF84BD9C),
        onSuccess: Color(0xFFFFFFFF),
        successContainer: Color(0xFFDEEDE4),
        onSuccessContainer: Color(0xFF1F3F26),
        warning: Color(0xFFC2AD8E),
        onWarning: Color(0xFFFFFFFF),
        warningContainer: Color(0xFFF0ECE5),
        onWarningContainer: Color(0xFF3F2D14),
        info: Color(0xFF82A1BF),
        onInfo: Color(0xFFFFFFFF),
        infoContainer: Color(0xFFDEE6ED),
        onInfoContainer: Color(0xFF1F3A5C),
        category: [
          Color(0xFFDEB8A6), Color(0xFFE5CEBD), Color(0xFFD69F95),
          Color(0xFF8CAEB8), Color(0xFFBFA188), Color(0xFF8CAEB0),
          Color(0xFFB5A6D0), Color(0xFFCDA1AB),
        ],
      ),
      surfaceContainer: const Color(0xFFFFFFFF),
      cardSurface: const Color(0xFFFFFFFF),
      cardShadow: const Color(0x14000000),
      cardForeground: const Color(0xFF2B1F18),
      cardAccent: const Color(0xFFDEB8A6),
      cardAccentContainer: const Color(0xFFF8F0ED),
      appBarBackground: const Color(0xFFFAF7F5),
      appBarForeground: const Color(0xFF4F2A14),
      unselectedItem: const Color(0xFFD4A060),
      bottomBar: const Color(0xFFFFFFFF),
      filledButtonSurface: const Color(0xFFFFFFFF),
      gradient: const _OrangeThemeColors(
        gradientStart: Color(0xFFBA8E78),
        gradientEnd: Color(0xFFC5A996),
      ),
    );
  }

  /// 创建玫紫主题（浅色）— 莫兰迪玫
  static ThemeData createRoseTheme() {
    return _buildTheme(
      brightness: Brightness.light,
      tokens: const _Tokens(
        primary: Color(0xFFD9ABB6),
        onPrimary: Color(0xFFFFFFFF),
        primaryContainer: Color(0xFFF7EEF0),
        onPrimaryContainer: Color(0xFF4A1F2A),
        secondary: Color(0xFFE1C1C6),
        onSecondary: Color(0xFF3D1F26),
        secondaryContainer: Color(0xFFF8F1F3),
        onSecondaryContainer: Color(0xFF5A2D38),
        tertiary: Color(0xFFD09AB1),
        onTertiary: Color(0xFFFFFFFF),
        tertiaryContainer: Color(0xFFF5EAEF),
        onTertiaryContainer: Color(0xFF3D1A2C),
        surface: Color(0xFFF9F5F6),
        onSurface: Color(0xFF1F1B17),
        surfaceVariant: Color(0xFFF5EBED),
        onSurfaceVariant: Color(0xFF694951),
        background: Color(0xFFF9F5F6),
        onBackground: Color(0xFF1F1B17),
        error: Color(0xFFB6887C),
        onError: Color(0xFFFFFFFF),
        errorContainer: Color(0xFFF5E1DC),
        onErrorContainer: Color(0xFF4A1F14),
        outline: Color(0xFFEAD7DC),
        outlineVariant: Color(0xFFF0E6E8),
        surfaceTint: Color(0xFFD9ABB6),
      ),
      colors: const _ExtColors(
        success: Color(0xFF84BD9C),
        onSuccess: Color(0xFFFFFFFF),
        successContainer: Color(0xFFDEEDE4),
        onSuccessContainer: Color(0xFF1F3F26),
        warning: Color(0xFFC2AD8E),
        onWarning: Color(0xFFFFFFFF),
        warningContainer: Color(0xFFF0ECE5),
        onWarningContainer: Color(0xFF3F2D14),
        info: Color(0xFF82A1BF),
        onInfo: Color(0xFFFFFFFF),
        infoContainer: Color(0xFFDEE6ED),
        onInfoContainer: Color(0xFF1F3A5C),
        category: [
          Color(0xFFD9ABB6), Color(0xFFE1C1C6), Color(0xFFD09AB1),
          Color(0xFF8CB8AC), Color(0xFFBE8E8E), Color(0xFFB5A6D0),
          Color(0xFF8AB276), Color(0xFFCDA1AB),
        ],
      ),
      surfaceContainer: const Color(0xFFFFFFFF),
      cardSurface: const Color(0xFFFFFFFF),
      cardShadow: const Color(0x14000000),
      cardForeground: const Color(0xFF2A181A),
      cardAccent: const Color(0xFFD9ABB6),
      cardAccentContainer: const Color(0xFFF7EEF0),
      appBarBackground: const Color(0xFFF9F5F6),
      appBarForeground: const Color(0xFF4A1F2A),
      unselectedItem: const Color(0xFFD4A0A0),
      bottomBar: const Color(0xFFFFFFFF),
      filledButtonSurface: const Color(0xFFFFFFFF),
      gradient: const _RoseThemeColors(
        gradientStart: Color(0xFFB67C8B),
        gradientEnd: Color(0xFFC299A0),
      ),
    );
  }

  /// 创建暮紫主题（深色）— 莫兰迪紫
  static ThemeData createPurpleTheme() {
    return _buildTheme(
      brightness: Brightness.dark,
      tokens: const _Tokens(
        primary: Color(0xFFAB97BF),
        onPrimary: Color(0xFF1B1722),
        primaryContainer: Color(0xFF3D2E5C),
        onPrimaryContainer: Color(0xFFE0DAF0),
        secondary: Color(0xFFC1B2CD),
        onSecondary: Color(0xFF1B1722),
        secondaryContainer: Color(0xFF4A3D6B),
        onSecondaryContainer: Color(0xFFDCD5E8),
        tertiary: Color(0xFF9789B3),
        onTertiary: Color(0xFF1B1722),
        tertiaryContainer: Color(0xFF35285C),
        onTertiaryContainer: Color(0xFFD8CFEC),
        surface: Color(0xFF1B1722),
        onSurface: Color(0xFFE5E1EC),
        surfaceVariant: Color(0xFF25202E),
        onSurfaceVariant: Color(0xFFA8A1B8),
        background: Color(0xFF100C18),
        onBackground: Color(0xFFE5E1EC),
        error: Color(0xFFC99DBA),
        onError: Color(0xFF1B1722),
        errorContainer: Color(0xFF4A2D3D),
        onErrorContainer: Color(0xFFF2D9E8),
        outline: Color(0xFF3F3548),
        outlineVariant: Color(0xFF2D2638),
        surfaceTint: Color(0xFFAB97BF),
      ),
      colors: const _ExtColors(
        success: Color(0xFF95B89E),
        onSuccess: Color(0xFF1B1722),
        successContainer: Color(0xFF2A3F30),
        onSuccessContainer: Color(0xFFB8D6BE),
        warning: Color(0xFFD4B68E),
        onWarning: Color(0xFF1B1722),
        warningContainer: Color(0xFF4A3D24),
        onWarningContainer: Color(0xFFF0D9A8),
        info: Color(0xFF9AADC1),
        onInfo: Color(0xFF1B1722),
        infoContainer: Color(0xFF2D3748),
        onInfoContainer: Color(0xFFCBD5E1),
        category: [
          Color(0xFFAB97BF), Color(0xFFC1B2CD), Color(0xFF9789B3),
          Color(0xFF83A970), Color(0xFFB29780), Color(0xFF80A0B2),
          Color(0xFFBC8F98), Color(0xFF809C63),
        ],
      ),
      surfaceContainer: const Color(0xFF1B1722),
      cardSurface: const Color(0xFF252535),
      cardShadow: const Color(0x66000000),
      cardForeground: const Color(0xFFE0DDE8),
      cardAccent: const Color(0xFFAB97BF),
      cardAccentContainer: const Color(0xFF3D2E5C),
      appBarBackground: const Color(0xFF1B1722),
      appBarForeground: const Color(0xFFE5E1EC),
      unselectedItem: const Color(0xFF707080),
      bottomBar: const Color(0xFF1B1722),
      filledButtonSurface: const Color(0xFF1B1722),
      gradient: const _PurpleThemeColors(
        gradientStart: Color(0xFFAB97BF),
        gradientEnd: Color(0xFFC1B2CD),
      ),
    );
  }

  // ============================================================
  // 通用 ThemeData 构建器
  // ============================================================

  static ThemeData _buildTheme({
    required Brightness brightness,
    required _Tokens tokens,
    required _ExtColors colors,
    required Color surfaceContainer,
    required Color cardSurface,
    required Color cardShadow,
    required Color cardForeground,
    required Color cardAccent,
    required Color cardAccentContainer,
    required Color appBarBackground,
    required Color appBarForeground,
    required Color unselectedItem,
    required Color bottomBar,
    required Color filledButtonSurface,
    required ThemeExtension<dynamic>? gradient,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: tokens.primary,
      onPrimary: tokens.onPrimary,
      primaryContainer: tokens.primaryContainer,
      onPrimaryContainer: tokens.onPrimaryContainer,
      secondary: tokens.secondary,
      onSecondary: tokens.onSecondary,
      secondaryContainer: tokens.secondaryContainer,
      onSecondaryContainer: tokens.onSecondaryContainer,
      tertiary: tokens.tertiary,
      onTertiary: tokens.onTertiary,
      tertiaryContainer: tokens.tertiaryContainer,
      onTertiaryContainer: tokens.onTertiaryContainer,
      error: tokens.error,
      onError: tokens.onError,
      errorContainer: tokens.errorContainer,
      onErrorContainer: tokens.onErrorContainer,
      surface: tokens.surface,
      onSurface: tokens.onSurface,
      surfaceContainerHighest: surfaceContainer,
      onSurfaceVariant: tokens.onSurfaceVariant,
      outline: tokens.outline,
      outlineVariant: tokens.outlineVariant,
      surfaceTint: tokens.surfaceTint,
    );

    final ext = AppColorsExtension(
      success: colors.success,
      onSuccess: colors.onSuccess,
      successContainer: colors.successContainer,
      onSuccessContainer: colors.onSuccessContainer,
      warning: colors.warning,
      onWarning: colors.onWarning,
      warningContainer: colors.warningContainer,
      onWarningContainer: colors.onWarningContainer,
      info: colors.info,
      onInfo: colors.onInfo,
      infoContainer: colors.infoContainer,
      onInfoContainer: colors.onInfoContainer,
      category: colors.category,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
      extensions: [
        ext,
        ?gradient,
      ],
      cardTheme: CardThemeData(
        elevation: 2,
        color: cardSurface,
        shadowColor: cardShadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: appBarBackground,
        foregroundColor: appBarForeground,
        surfaceTintColor: tokens.surfaceTint,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.primary,
        foregroundColor: tokens.onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: tokens.onPrimary,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: tokens.primary,
          foregroundColor: tokens.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: bottomBar,
        selectedItemColor: tokens.primary,
        unselectedItemColor: unselectedItem,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

  /// 从主题中读取渐变起始色（测试用；无渐变扩展时返回 null）。
  static Color? gradientStartOf(ThemeData theme) {
    for (final ext in theme.extensions.values) {
      if (ext is _PinkThemeColors) return ext.gradientStart;
      if (ext is _GreenThemeColors) return ext.gradientStart;
      if (ext is _OrangeThemeColors) return ext.gradientStart;
      if (ext is _RoseThemeColors) return ext.gradientStart;
      if (ext is _PurpleThemeColors) return ext.gradientStart;
    }
    return null;
  }

  /// 从主题中读取渐变结束色（测试用；无渐变扩展时返回 null）。
  static Color? gradientEndOf(ThemeData theme) {
    for (final ext in theme.extensions.values) {
      if (ext is _PinkThemeColors) return ext.gradientEnd;
      if (ext is _GreenThemeColors) return ext.gradientEnd;
      if (ext is _OrangeThemeColors) return ext.gradientEnd;
      if (ext is _RoseThemeColors) return ext.gradientEnd;
      if (ext is _PurpleThemeColors) return ext.gradientEnd;
    }
    return null;
  }

  /// 创建主题预览颜色（用于主题设置卡片）
  static Map<String, Color> getPreviewColors(AppThemeMode mode) {
    final colorScheme = getThemeData(mode).colorScheme;
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

/// 应用扩展色板 — 状态色（success/warning/info/error）+ 分类色板（8 色）
///
/// 在 widget 中通过 `Theme.of(context).extension<AppColorsExtension>()` 读取。
/// 用于图表、标签分类、优先级等需要色彩多样性的场景，且所有色已对齐主题低饱和度。
@immutable
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;
  final List<Color> category;

  const AppColorsExtension({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.category,
  });

  @override
  AppColorsExtension copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color?onInfoContainer,
    List<Color>? category,
  }) {
    return AppColorsExtension(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      category: category ?? this.category,
    );
  }

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorsExtension(
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      successContainer: l(successContainer, other.successContainer),
      onSuccessContainer: l(onSuccessContainer, other.onSuccessContainer),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      warningContainer: l(warningContainer, other.warningContainer),
      onWarningContainer: l(onWarningContainer, other.onWarningContainer),
      info: l(info, other.info),
      onInfo: l(onInfo, other.onInfo),
      infoContainer: l(infoContainer, other.infoContainer),
      onInfoContainer: l(onInfoContainer, other.onInfoContainer),
      category: List.generate(
        category.length,
        (i) => l(category[i], other.category[i]),
      ),
    );
  }
}

/// Material 3 ColorScheme 完整 token（私有）
@immutable
class _Tokens {
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color surface;
  final Color onSurface;
  final Color surfaceVariant;
  final Color onSurfaceVariant;
  final Color background;
  final Color onBackground;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color outline;
  final Color outlineVariant;
  final Color surfaceTint;

  const _Tokens({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.surface,
    required this.onSurface,
    required this.surfaceVariant,
    required this.onSurfaceVariant,
    required this.background,
    required this.onBackground,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.outline,
    required this.outlineVariant,
    required this.surfaceTint,
  });
}

/// 扩展色板（私有）
@immutable
class _ExtColors {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;
  final List<Color> category;

  const _ExtColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.category,
  });
}

/// 茶玫主题的自定义颜色扩展（渐变）
@immutable
class _PinkThemeColors extends ThemeExtension<_PinkThemeColors> {
  final Color gradientStart;
  final Color gradientEnd;

  const _PinkThemeColors({
    required this.gradientStart,
    required this.gradientEnd,
  });

  @override
  _PinkThemeColors copyWith({Color? gradientStart, Color? gradientEnd}) {
    return _PinkThemeColors(
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
    );
  }

  @override
  _PinkThemeColors lerp(ThemeExtension<_PinkThemeColors>? other, double t) {
    if (other is! _PinkThemeColors) return this;
    return _PinkThemeColors(
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
    );
  }
}

/// 苔绿主题的自定义颜色扩展（渐变）
@immutable
class _GreenThemeColors extends ThemeExtension<_GreenThemeColors> {
  final Color gradientStart;
  final Color gradientEnd;

  const _GreenThemeColors({
    required this.gradientStart,
    required this.gradientEnd,
  });

  @override
  _GreenThemeColors copyWith({Color? gradientStart, Color? gradientEnd}) {
    return _GreenThemeColors(
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
    );
  }

  @override
  _GreenThemeColors lerp(ThemeExtension<_GreenThemeColors>? other, double t) {
    if (other is! _GreenThemeColors) return this;
    return _GreenThemeColors(
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
    );
  }
}

/// 陶橙主题的自定义颜色扩展（渐变）
@immutable
class _OrangeThemeColors extends ThemeExtension<_OrangeThemeColors> {
  final Color gradientStart;
  final Color gradientEnd;

  const _OrangeThemeColors({
    required this.gradientStart,
    required this.gradientEnd,
  });

  @override
  _OrangeThemeColors copyWith({Color? gradientStart, Color? gradientEnd}) {
    return _OrangeThemeColors(
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
    );
  }

  @override
  _OrangeThemeColors lerp(ThemeExtension<_OrangeThemeColors>? other, double t) {
    if (other is! _OrangeThemeColors) return this;
    return _OrangeThemeColors(
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
    );
  }
}

/// 玫紫主题的自定义颜色扩展（渐变）
@immutable
class _RoseThemeColors extends ThemeExtension<_RoseThemeColors> {
  final Color gradientStart;
  final Color gradientEnd;

  const _RoseThemeColors({
    required this.gradientStart,
    required this.gradientEnd,
  });

  @override
  _RoseThemeColors copyWith({Color? gradientStart, Color? gradientEnd}) {
    return _RoseThemeColors(
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
    );
  }

  @override
  _RoseThemeColors lerp(ThemeExtension<_RoseThemeColors>? other, double t) {
    if (other is! _RoseThemeColors) return this;
    return _RoseThemeColors(
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
    );
  }
}

/// 暮紫主题的自定义颜色扩展（渐变）
@immutable
class _PurpleThemeColors extends ThemeExtension<_PurpleThemeColors> {
  final Color gradientStart;
  final Color gradientEnd;

  const _PurpleThemeColors({
    required this.gradientStart,
    required this.gradientEnd,
  });

  @override
  _PurpleThemeColors copyWith({Color? gradientStart, Color? gradientEnd}) {
    return _PurpleThemeColors(
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
    );
  }

  @override
  _PurpleThemeColors lerp(ThemeExtension<_PurpleThemeColors>? other, double t) {
    if (other is! _PurpleThemeColors) return this;
    return _PurpleThemeColors(
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
    );
  }
}