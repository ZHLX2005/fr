// 应用主题模式枚举 —— 独立文件避免 app_theme ↔ factory 循环依赖。
//
// app_theme.dart 通过 `export 'colors/theme_mode.dart' show AppThemeMode;`
// 重新导出，外部消费者无感。

/// 应用主题模式（5 套 zen / purple / ink / rose / lemon）。
enum AppThemeMode {
  /// 暮紫主题（深色）— 暮紫主色 ↔ 鎏金暖黑环境（hue45°）。
  purple,

  /// 茶禅主题（zen）—— sage 绿 + 暖米环境 + 陶土红强调。
  zen,

  /// 墨白主题（ink）—— 墨黑主色 + 纯纸白底 + 墨赭互补强调。
  ink,

  /// 粉雾海盐主题（rose）—— Velvet Bloom 粉主色 + 海盐薄荷互补强调。
  rose,

  /// 柠檬鼠尾草主题（lemon）—— 橄榄绿主色 + 柠檬黄强调 + 鼠尾草主背景。
  lemon,
}
