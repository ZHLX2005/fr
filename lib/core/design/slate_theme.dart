import 'package:flutter/material.dart';

import 'slate_palette.dart';

/// Slate 设计系统 —— ThemeData 构造
///
/// 无边框 + 去塑料感：卡片靠柔和阴影分区，无 1px 描边；
/// 圆角统一 14px；低饱和靛蓝为主强调色。
abstract final class SlateTheme {
  static ThemeData light() => _build(
        brightness: Brightness.light,
        background: SlatePalette.lightBackground,
        surface: SlatePalette.lightSurface,
        surfaceTint: SlatePalette.lightSurfaceTint,
        textPrimary: SlatePalette.lightTextPrimary,
        textSecondary: SlatePalette.lightTextSecondary,
        accent: SlatePalette.lightAccent,
        accentSoft: SlatePalette.lightAccentSoft,
        onAccent: SlatePalette.lightOnAccent,
        divider: SlatePalette.lightDivider,
        shadow: SlatePalette.lightShadow,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        background: SlatePalette.darkBackground,
        surface: SlatePalette.darkSurface,
        surfaceTint: SlatePalette.darkSurfaceTint,
        textPrimary: SlatePalette.darkTextPrimary,
        textSecondary: SlatePalette.darkTextSecondary,
        accent: SlatePalette.darkAccent,
        accentSoft: SlatePalette.darkAccentSoft,
        onAccent: SlatePalette.darkOnAccent,
        divider: SlatePalette.darkDivider,
        shadow: SlatePalette.darkShadow,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceTint,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
    required Color accentSoft,
    required Color onAccent,
    required Color divider,
    required Color shadow,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      primaryContainer: accentSoft,
      onPrimaryContainer: accent,
      secondary: accent,
      onSecondary: onAccent,
      secondaryContainer: accentSoft,
      onSecondaryContainer: accent,
      tertiary: accent,
      onTertiary: onAccent,
      tertiaryContainer: accentSoft,
      onTertiaryContainer: accent,
      error: brightness == Brightness.light
          ? const Color(0xFFD64545)
          : const Color(0xFFF0716B),
      onError: Colors.white,
      errorContainer: brightness == Brightness.light
          ? const Color(0xFFFCE8E8)
          : const Color(0xFF4A2626),
      onErrorContainer: brightness == Brightness.light
          ? const Color(0xFF8C2B2B)
          : const Color(0xFFF5C6C6),
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceTint,
      surfaceContainerHigh: brightness == Brightness.light
          ? const Color(0xFFF5F5F6)
          : const Color(0xFF26262B),
      surfaceContainer: brightness == Brightness.light
          ? const Color(0xFFF2F2F4)
          : const Color(0xFF202025),
      surfaceContainerLow: brightness == Brightness.light
          ? const Color(0xFFF7F7F8)
          : const Color(0xFF1C1C20),
      onSurfaceVariant: textSecondary,
      background: background,
      onBackground: textPrimary,
      outline: divider,
      outlineVariant: divider,
      shadow: shadow,
      surfaceTint: accent,
      inverseSurface: brightness == Brightness.light
          ? const Color(0xFF1A1A1A)
          : const Color(0xFFF2F2F4),
      inversePrimary: brightness == Brightness.light
          ? const Color(0xFF6366F1)
          : const Color(0xFF4F46E5),
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,

      // 卡片：无描边，柔和阴影分区
      cardTheme: CardThemeData(
        elevation: 1.5,
        color: surface,
        shadowColor: shadow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SlatePalette.radius),
        ),
        margin: EdgeInsets.zero,
      ),

      // AppBar：无边框无阴影，与背景融合
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),

      // 按钮：圆角 14，无边框
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SlatePalette.radius),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: surface,
          foregroundColor: textPrimary,
          elevation: 1,
          shadowColor: shadow,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SlatePalette.radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SlatePalette.radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SlatePalette.radius),
          ),
        ),
      ),

      // 输入框：无边框，浅表面填充
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceTint,
        hintStyle: TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SlatePalette.radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SlatePalette.radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SlatePalette.radius),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),

      // 底部导航：无边框，表面色
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // 分隔线：极浅，几乎不可见
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),

      // 对话框/底部面板：无边框
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SlatePalette.radius + 2),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.light
            ? const Color(0xFF2E2E33)
            : const Color(0xFF3A3A40),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SlatePalette.radius),
        ),
      ),

      // 图标主题
      iconTheme: IconThemeData(color: textPrimary),

      // 列表
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SlatePalette.radius),
        ),
      ),
    );
  }
}
