import 'package:flutter/material.dart';

/// 笔记编辑器主题常量
///
/// 提供笔记编辑器专用的色彩和样式配置
class NoteEditorTheme {
  NoteEditorTheme._();

  // ==================== 亮色主题色彩 ====================

  /// 亮色主题 - 编辑器背景色（护眼米白）
  static const Color lightBg = Color(0xFFFAFAFA);

  /// 亮色主题 - 编辑器内容区背景
  static const Color lightSurface = Color(0xFFFFFFFF);

  /// 亮色主题 - 次要背景色
  static const Color lightSurfaceVariant = Color(0xFFF5F5F5);

  /// 亮色主题 - 主文本色（深灰，更柔和）
  static const Color lightOnSurface = Color(0xFF2D2D2D);

  /// 亮色主题 - 次要文本色
  static const Color lightOnSurfaceVariant = Color(0xFF757575);

  /// 亮色主题 - 标题高亮色（蓝色，更突出）
  static const Color lightHeaderHighlight = Color(0xFF1976D2);

  /// 亮色主题 - 引用块背景（淡黄）
  static const Color lightQuoteBackground = Color(0xFFFFF8E1);

  /// 亮色主题 - 引用块边框
  static const Color lightQuoteBorder = Color(0xFFFFB74D);

  /// 亮色主题 - 代码块背景
  static const Color lightCodeBackground = Color(0xFFF5F5F5);

  /// 亮色主题 - 列表项目符号色
  static const Color lightBulletColor = Color(0xFF42A5F5);

  // ==================== 暗色主题色彩 ====================

  /// 暗色主题 - 编辑器背景色
  static const Color darkBg = Color(0xFF1A1A1A);

  /// 暗色主题 - 编辑器内容区背景
  static const Color darkSurface = Color(0xFF242424);

  /// 暗色主题 - 次要背景色
  static const Color darkSurfaceVariant = Color(0xFF2D2D2D);

  /// 暗色主题 - 主文本色
  static const Color darkOnSurface = Color(0xFFE0E0E0);

  /// 暗色主题 - 次要文本色
  static const Color darkOnSurfaceVariant = Color(0xFF9E9E9E);

  /// 暗色主题 - 标题高亮色
  static const Color darkHeaderHighlight = Color(0xFF64B5F6);

  /// 暗色主题 - 引用块背景
  static const Color darkQuoteBackground = Color(0xFF3E2723);

  /// 暗色主题 - 引用块边框
  static const Color darkQuoteBorder = Color(0xFFFFB74D);

  /// 暗色主题 - 代码块背景
  static const Color darkCodeBackground = Color(0xFF2D2D2D);

  /// 暗色主题 - 列表项目符号色
  static const Color darkBulletColor = Color(0xFF64B5F6);

  // ==================== 标题层级色彩 ====================

  /// H1 标题颜色
  static const Color header1Light = Color(0xFF1565C0);
  static const Color header1Dark = Color(0xFF64B5F6);

  /// H2 标题颜色
  static const Color header2Light = Color(0xFF1976D2);
  static const Color header2Dark = Color(0xFF81D4FA);

  /// H3 标题颜色
  static const Color header3Light = Color(0xFF2196F3);
  static const Color header3Dark = Color(0xFF4FC3F7);

  /// H4-H6 标题颜色（依次变淡）
  static const Color header4Light = Color(0xFF42A5F5);
  static const Color header4Dark = Color(0xFF29B6F6);

  static const Color header5Light = Color(0xFF66BB6A);
  static const Color header5Dark = Color(0xFF81C784);

  static const Color header6Light = Color(0xFF78909C);
  static const Color header6Dark = Color(0xFF90A4AE);

  // ==================== 功能按钮色彩 ====================

  /// AI 按钮颜色
  static const Color aiButtonLight = Color(0xFFFFD54F);
  static const Color aiButtonDark = Color(0xFFFFCA28);

  /// 格式化按钮 - 常规态
  static const Color formatButtonLight = Color(0xFF757575);
  static const Color formatButtonDark = Color(0xFF9E9E9E);

  /// 格式化按钮 - 选中态（主色）
  static const Color formatButtonActiveLight = Color(0xFF1976D2);
  static const Color formatButtonActiveDark = Color(0xFF64B5F6);

  /// 底部工具栏背景色（亮色）
  static const Color toolbarBgLight = Color(0xFFFAFAFA);

  /// 底部工具栏背景色（暗色）
  static const Color toolbarBgDark = Color(0xFF2D2D2D);

  // ==================== 间距常量 ====================

  /// 编辑器内边距
  static const EdgeInsets editorPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 16);

  /// 底部工具栏内边距
  static const EdgeInsets toolbarPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  /// 工具栏按钮间距
  static const double toolbarButtonSpacing = 8;

  /// 工具栏分组间距
  static const double toolbarGroupSpacing = 16;

  // ==================== 圆角常量 ====================

  /// 工具栏按钮圆角
  static const double toolbarButtonRadius = 8;

  /// 卡片圆角
  static const double cardRadius = 12;

  // ==================== 字体大小常量 ====================

  /// H1 字体大小
  static const double h1FontSize = 28;

  /// H2 字体大小
  static const double h2FontSize = 24;

  /// H3 字体大小
  static const double h3FontSize = 20;

  /// H4 字体大小
  static const double h4FontSize = 18;

  /// H5 字体大小
  static const double h5FontSize = 16;

  /// H6 字体大小
  static const double h6FontSize = 14;

  // ==================== 主题扩展 ====================

  /// 获取对应主题的色彩
  static NoteEditorColors getColors(Brightness brightness) {
    return brightness == Brightness.light
        ? NoteEditorColors(
            bg: lightBg,
            surface: lightSurface,
            surfaceVariant: lightSurfaceVariant,
            onSurface: lightOnSurface,
            onSurfaceVariant: lightOnSurfaceVariant,
            headerHighlight: lightHeaderHighlight,
            quoteBackground: lightQuoteBackground,
            quoteBorder: lightQuoteBorder,
            codeBackground: lightCodeBackground,
            bulletColor: lightBulletColor,
            toolbarBg: toolbarBgLight,
            formatButton: formatButtonLight,
            formatButtonActive: formatButtonActiveLight,
            aiButton: aiButtonLight,
            h1: header1Light,
            h2: header2Light,
            h3: header3Light,
            h4: header4Light,
            h5: header5Light,
            h6: header6Light,
          )
        : NoteEditorColors(
            bg: darkBg,
            surface: darkSurface,
            surfaceVariant: darkSurfaceVariant,
            onSurface: darkOnSurface,
            onSurfaceVariant: darkOnSurfaceVariant,
            headerHighlight: darkHeaderHighlight,
            quoteBackground: darkQuoteBackground,
            quoteBorder: darkQuoteBorder,
            codeBackground: darkCodeBackground,
            bulletColor: darkBulletColor,
            toolbarBg: toolbarBgDark,
            formatButton: formatButtonDark,
            formatButtonActive: formatButtonActiveDark,
            aiButton: aiButtonDark,
            h1: header1Dark,
            h2: header2Dark,
            h3: header3Dark,
            h4: header4Dark,
            h5: header5Dark,
            h6: header6Dark,
          );
  }
}

/// 笔记编辑器色彩配置
class NoteEditorColors {
  final Color bg;
  final Color surface;
  final Color surfaceVariant;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color headerHighlight;
  final Color quoteBackground;
  final Color quoteBorder;
  final Color codeBackground;
  final Color bulletColor;
  final Color toolbarBg;
  final Color formatButton;
  final Color formatButtonActive;
  final Color aiButton;
  final Color h1;
  final Color h2;
  final Color h3;
  final Color h4;
  final Color h5;
  final Color h6;

  const NoteEditorColors({
    required this.bg,
    required this.surface,
    required this.surfaceVariant,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.headerHighlight,
    required this.quoteBackground,
    required this.quoteBorder,
    required this.codeBackground,
    required this.bulletColor,
    required this.toolbarBg,
    required this.formatButton,
    required this.formatButtonActive,
    required this.aiButton,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.h4,
    required this.h5,
    required this.h6,
  });
}
