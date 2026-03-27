import 'package:flutter/material.dart';

/// 应用主题模式枚举
enum AppThemeMode {
  /// 浅色模式（默认蓝色主题）
  light,

  /// 深色模式（夜间模式）
  dark,

  /// 粉红色主题（浅色模式）
  pink,

  /// 青绿色主题（浅色模式）
  green,
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
      case AppThemeMode.green:
        return '青绿主题';
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
      case AppThemeMode.green:
        return Icons.eco;
    }
  }

  /// 创建浅色主题数据（清新蓝色）
  static ThemeData createLightTheme() {
    // 使用清新明亮的蓝色系
    const primaryColor = Color(0xFF2196F3); // 鲜艳的蓝色
    const secondaryColor = Color(0xFF00BCD4); // 青色
    const tertiaryColor = Color(0xFF7C4DFF); // 紫色

    return ThemeData(
      colorScheme: ColorScheme.light(
        // 主色系 - 鲜艳明亮
        primary: primaryColor,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFE3F2FD),
        onPrimaryContainer: const Color(0xFF0D47A1),

        // 次要色系
        secondary: secondaryColor,
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFE0F7FA),
        onSecondaryContainer: const Color(0xFF006064),

        // 第三色系
        tertiary: tertiaryColor,
        onTertiary: Colors.white,
        tertiaryContainer: const Color(0xFFEDE7F6),
        onTertiaryContainer: const Color(0xFF311B92),

        // 表面色 - 干净明亮的底色
        surface: Colors.white,
        onSurface: const Color(0xFF1A1A1A),
        surfaceVariant: const Color(0xFFF5F5F5), // 非常浅的灰色
        onSurfaceVariant: const Color(0xFF757575),

        // 背景色 - 纯净的浅色
        background: const Color(0xFFFAFAFA), // 接近白色但不刺眼
        onBackground: const Color(0xFF1A1A1A),

        // 错误色
        error: const Color(0xFFE53935),
        onError: Colors.white,
        errorContainer: const Color(0xFFFFEBEE),
        onErrorContainer: const Color(0xFFB71C1C),

        // 轮廓和分割线
        outline: const Color(0xFFE0E0E0),
        outlineVariant: const Color(0xFFF0F0F0),

        // 容器色调
        surfaceTint: primaryColor,
      ),
      useMaterial3: true,
      brightness: Brightness.light,

      // 自定义组件样式
      cardTheme: CardThemeData(
        elevation: 2,
        color: Colors.white,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF1A1A1A),
        surfaceTintColor: Color(0xFF2196F3),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: const Color(0xFF9E9E9E),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

  /// 创建深色主题数据（舒适的夜间模式）
  static ThemeData createDarkTheme() {
    // 使用柔和的蓝紫色调，不刺眼
    const primaryColor = Color(0xFF7986CB); // 柔和的蓝紫色
    const secondaryColor = Color(0xFF81D4FA); // 柔和的天蓝色

    return ThemeData(
      colorScheme: ColorScheme.dark(
        // 主色系 - 柔和的蓝紫色
        primary: primaryColor,
        onPrimary: const Color(0xFF1A237E),
        primaryContainer: const Color(0xFF2D3766),
        onPrimaryContainer: const Color(0xFFC5CAE9),

        // 次要色系 - 柔和的天蓝色
        secondary: secondaryColor,
        onSecondary: const Color(0xFF01579B),
        secondaryContainer: const Color(0xFF1E4D7A),
        onSecondaryContainer: const Color(0xFFB3E5FC),

        // 第三色系
        tertiary: const Color(0xFF9575CD),
        onTertiary: const Color(0xFF311B92),
        tertiaryContainer: const Color(0xFF3D2E5C),
        onTertiaryContainer: const Color(0xFFD1C4E9),

        // 表面色 - 舒适的深色背景
        surface: const Color(0xFF121212), // 不是纯黑，更舒适
        onSurface: const Color(0xFFE0E0E0),
        surfaceVariant: const Color(0xFF1E1E1E),
        onSurfaceVariant: const Color(0xFFB0B0B0),

        // 背景色
        background: const Color(0xFF0A0A0A),
        onBackground: const Color(0xFFE0E0E0),

        // 错误色
        error: const Color(0xFFEF5350),
        onError: const Color(0xFFB71C1C),
        errorContainer: const Color(0xFF5C1B1B),
        onErrorContainer: const Color(0xFFFFCDD2),

        // 轮廓和分割线 - 在深色模式下更明显
        outline: const Color(0xFF424242),
        outlineVariant: const Color(0xFF2C2C2C),

        // 容器色调
        surfaceTint: primaryColor,
      ),
      useMaterial3: true,
      brightness: Brightness.dark,

      // 自定义组件样式
      cardTheme: CardThemeData(
        elevation: 2,
        color: const Color(0xFF1E1E1E),
        shadowColor: Colors.black.withOpacity(0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: const Color(0xFFE0E0E0),
        surfaceTintColor: primaryColor,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: const Color(0xFF1A237E),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: const Color(0xFF1A237E),
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: const Color(0xFF1A237E),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: primaryColor,
        unselectedItemColor: const Color(0xFF757575),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

  /// 创建粉红色主题数据（甜美少女心）
  static ThemeData createPinkTheme() {
    // 使用鲜艳的粉色系
    const primaryColor = Color(0xFFFF6B95); // 鲜艳的樱花粉
    const secondaryColor = Color(0xFFFF8FAB); // 蜜桃粉
    const tertiaryColor = Color(0xFFFFB6C1); // 浅粉色

    return ThemeData(
      colorScheme: ColorScheme.light(
        // 主色系 - 鲜艳的粉色
        primary: primaryColor,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFFFE4EC),
        onPrimaryContainer: const Color(0xFF8A1244),

        // 次要色系 - 温暖的粉色调
        secondary: secondaryColor,
        onSecondary: const Color(0xFF6B1A3A),
        secondaryContainer: const Color(0xFFFFD6E3),
        onSecondaryContainer: const Color(0xFF7A1A3A),

        // 第三色系 - 浅粉色调
        tertiary: tertiaryColor,
        onTertiary: const Color(0xFF5C1838),
        tertiaryContainer: const Color(0xFFFFE1EC),
        onTertiaryContainer: const Color(0xFF4A1230),

        // 表面色 - 干净明亮的底色
        surface: const Color(0xFFFFF8FA), // 非常浅的粉白色
        onSurface: const Color(0xFF2D1A20),
        surfaceVariant: const Color(0xFFFFF0F5), // 淡紫粉色
        onSurfaceVariant: const Color(0xFF8A6A70),

        // 背景色
        background: const Color(0xFFFAFAFA),
        onBackground: const Color(0xFF2D1A20),

        // 错误色
        error: const Color(0xFFE53935),
        onError: Colors.white,
        errorContainer: const Color(0xFFFFEBEE),
        onErrorContainer: const Color(0xFFB71C1C),

        // 轮廓和分割线
        outline: const Color(0xFFE8B8C4),
        outlineVariant: const Color(0xFFFFD6E3),

        // 容器色调
        surfaceTint: primaryColor,
      ),
      useMaterial3: true,
      brightness: Brightness.light,

      // 自定义组件样式
      cardTheme: CardThemeData(
        elevation: 2,
        color: Colors.white,
        shadowColor: const Color(0xFFFF6B95).withOpacity(0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Color(0xFFFFE4EC),
        foregroundColor: Color(0xFF8A1244),
        surfaceTintColor: Color(0xFFFF6B95),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: const Color(0xFFD4A0AD),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // 添加粉色主题的渐变效果
      extensions: const [
        _PinkThemeColors(
          gradientStart: Color(0xFFFF6B95),
          gradientEnd: Color(0xFFFF8FAB),
        ),
      ],
    );
  }

  /// 创建青绿色主题数据（清新自然）
  static ThemeData createGreenTheme() {
    // 使用清新的绿色系
    const primaryColor = Color(0xFF10B981); // 鲜艳的翠绿色
    const secondaryColor = Color(0xFF34D399); // 清新的浅绿色
    const tertiaryColor = Color(0xFF6EE7B7); // 柔和的薄荷绿

    return ThemeData(
      colorScheme: ColorScheme.light(
        // 主色系 - 鲜艳的翠绿色
        primary: primaryColor,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFD1FAE5),
        onPrimaryContainer: const Color(0xFF064E3B),

        // 次要色系 - 清新的浅绿色
        secondary: secondaryColor,
        onSecondary: const Color(0xFF065F46),
        secondaryContainer: const Color(0xFFD1FAE5),
        onSecondaryContainer: const Color(0xFF064E3B),

        // 第三色系 - 柔和的薄荷绿
        tertiary: tertiaryColor,
        onTertiary: const Color(0xFF064E3B),
        tertiaryContainer: const Color(0xFFE6FFFA),
        onTertiaryContainer: const Color(0xFF065F46),

        // 表面色 - 干净明亮的底色
        surface: const Color(0xFFF0FDF4), // 非常浅的绿白色
        onSurface: const Color(0xFF1A202C),
        surfaceVariant: const Color(0xFFECFDF5), // 淡淡的绿色背景
        onSurfaceVariant: const Color(0xFF6B7280),

        // 背景色
        background: const Color(0xFFFAFAFA),
        onBackground: const Color(0xFF1A202C),

        // 错误色
        error: const Color(0xFFE53935),
        onError: Colors.white,
        errorContainer: const Color(0xFFFFEBEE),
        onErrorContainer: const Color(0xFFB71C1C),

        // 轮廓和分割线
        outline: const Color(0xFFA7F3D0),
        outlineVariant: const Color(0xFFD1FAE5),

        // 容器色调
        surfaceTint: primaryColor,
      ),
      useMaterial3: true,
      brightness: Brightness.light,

      // 自定义组件样式
      cardTheme: CardThemeData(
        elevation: 2,
        color: Colors.white,
        shadowColor: const Color(0xFF10B981).withOpacity(0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Color(0xFFD1FAE5),
        foregroundColor: Color(0xFF064E3B),
        surfaceTintColor: Color(0xFF10B981),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: const Color(0xFF9CA3AF),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // 添加绿色主题的渐变效果
      extensions: const [
        _GreenThemeColors(
          gradientStart: Color(0xFF10B981),
          gradientEnd: Color(0xFF34D399),
        ),
      ],
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
      case AppThemeMode.green:
        return createGreenTheme();
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

/// 粉色主题的自定义颜色扩展
@immutable
class _PinkThemeColors extends ThemeExtension<_PinkThemeColors> {
  final Color gradientStart;
  final Color gradientEnd;

  const _PinkThemeColors({
    required this.gradientStart,
    required this.gradientEnd,
  });

  @override
  _PinkThemeColors copyWith({
    Color? gradientStart,
    Color? gradientEnd,
  }) {
    return _PinkThemeColors(
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
    );
  }

  @override
  _PinkThemeColors lerp(ThemeExtension<_PinkThemeColors>? other, double t) {
    if (other is! _PinkThemeColors) {
      return this;
    }
    return _PinkThemeColors(
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
    );
  }
}

/// 绿色主题的自定义颜色扩展
@immutable
class _GreenThemeColors extends ThemeExtension<_GreenThemeColors> {
  final Color gradientStart;
  final Color gradientEnd;

  const _GreenThemeColors({
    required this.gradientStart,
    required this.gradientEnd,
  });

  @override
  _GreenThemeColors copyWith({
    Color? gradientStart,
    Color? gradientEnd,
  }) {
    return _GreenThemeColors(
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
    );
  }

  @override
  _GreenThemeColors lerp(ThemeExtension<_GreenThemeColors>? other, double t) {
    if (other is! _GreenThemeColors) {
      return this;
    }
    return _GreenThemeColors(
      gradientStart: Color.lerp(gradientStart, other.gradientStart, t)!,
      gradientEnd: Color.lerp(gradientEnd, other.gradientEnd, t)!,
    );
  }
}
