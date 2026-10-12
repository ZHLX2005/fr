// 应用主题模式枚举 —— 独立文件避免 app_theme ↔ factory 循环依赖。
//
// app_theme.dart 通过 `export 'colors/theme_mode.dart' show AppThemeMode;`
// 重新导出，外部消费者无感。

/// 应用主题模式（6 套 zen / purple / ink / rose / lemon / cobalt）。
enum AppThemeMode {
  /// 暮紫主题（深色）— 暮紫主色 ↔ 冷炭紫环境 + 稀用鎏金。
  purple,

  /// 茶禅主题（zen）—— sage 绿 + 暖米环境 + 陶土红强调。
  zen,

  /// 墨白主题（ink）—— 墨黑主色 + 暖生宣纸底 + 章印朱红。
  ink,

  /// 粉雾主题（rose）—— 近白页 + 尘玫瑰 CTA（TUTUMIYU 式）。
  rose,

  /// 柠檬鼠尾草主题（lemon）—— 黄油主色 + 暖石中性 + 低彩鼠尾草。
  lemon,

  /// 宝蓝主题（cobalt）—— 宝蓝 + 纯白高对比（ID'CAKE 式）。
  cobalt,
}
