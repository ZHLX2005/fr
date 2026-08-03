import 'package:flutter/material.dart';

/// 边框强调风格按钮（替代纯色色块）
///
/// 用户痛点：FilledButton/ElevatedButton 默认是主题色纯色实心块（"塑料感"）；
/// 改成边框强调后视觉更克制：浅色调底 + 彩色描边 + 彩色文字。
///
/// **完全从 [Theme.of(context).colorScheme] 取色**，不依赖任何硬编码调色板
/// —— 配合当前主题（light/dark/pink/green/orange/rose/purple）自动呈现对应色相。
///
/// 三档语义：
/// - [borderEmphasis] —— 一般功能（登录/发送/保存/确认 等）
/// - [dangerEmphasis]  —— 破坏性操作（删除/取消等）
/// - [ghostEmphasis]  —— 次要辅助（透底仅文字颜色）
///
/// 用法：
///   OutlinedButton(
///     style: SlateButton.borderEmphasis(context, color: colorScheme.primary),
///     onPressed: ...,
///     child: Text('发送'),
///   )
abstract final class SlateButton {
  /// 统一圆角：从主题 cardTheme 取，缺省 14
  static double _radiusOf(BuildContext context) {
    final shape = Theme.of(context).cardTheme.shape;
    if (shape is RoundedRectangleBorder) {
      final br = shape.borderRadius;
      if (br is BorderRadius) return br.topLeft.x;
    }
    return 14;
  }

  /// 边框强调按钮样式（一般功能）
  ///
  /// [color] 一般传 `colorScheme.primary`；破坏性场景可传自定义红/橙。
  static ButtonStyle borderEmphasis(
    BuildContext context, {
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final radius = _radiusOf(context);
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      backgroundColor: color.withValues(alpha: isDark ? 0.18 : 0.08),
      side: BorderSide(
        color: color.withValues(alpha: isDark ? 0.65 : 0.5),
        width: 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }

  /// 边框强调按钮样式（破坏性）—— 红色由 [colorScheme.error] 派生
  static ButtonStyle dangerEmphasis(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return borderEmphasis(context, color: danger);
  }

  /// 透明边框（次要辅助，仅文字颜色，无描边）
  static ButtonStyle ghostEmphasis(
    BuildContext context, {
    required Color color,
  }) {
    final radius = _radiusOf(context);
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    );
  }
}
