// Layer 1 — Raw spacing tokens.
//
// 应用全局间距节奏：4 / 8 / 12 / 16 / 24 / 32 / 48。
// 组件层（core/ui/、core/ui/global/zen/、app_theme）的 padding / margin / SizedBox
// 间距从这里取；业务页面的布局值不强制迁移（多为一次性排版值）。
// 消费者：core/ui/global/section/main.dart 等。

/// 应用间距 token（4dp 节奏）。
///
/// 命名按"语义档位"而非数值：
///   - xxs (4)  ：紧凑连接（icon 与文字间隙）
///   - xs  (8)  ：组件内部紧凑间距
///   - sm  (12) ：列表项内边距
///   - md  (16) ：卡片内边距基线
///   - lg  (24) ：页面内边距 / 大块间距
///   - xl  (32) ：段落间距
///   - xxl (48) ：顶部留白
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}