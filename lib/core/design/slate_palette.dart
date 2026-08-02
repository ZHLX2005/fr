import 'package:flutter/material.dart';

/// Slate 设计系统 —— 调色板（单一真相源）
///
/// 设计语言：
/// - **无边框**：全站不出现 1px 描边，靠表面色差 + 柔和阴影分区
/// - **去塑料感**：低饱和靛蓝强调 + 暖灰背景 + 雾面表面，避免高饱和/白卡/硬边
/// - 圆角统一 14px（消息气泡尾角 4px）
///
/// 用法：气泡/卡片/消息组件一律从这里取色，不在组件里写死颜色。
abstract final class SlatePalette {
  // ── Light ────────────────────────────────────────────
  static const Color lightBackground = Color(0xFFF7F7F8); // 暖灰
  static const Color lightSurface = Color(0xFFFFFFFF); // 卡片/白
  static const Color lightSurfaceTint = Color(0xFFF1F1F2); // AI 气泡/浅表面
  static const Color lightTextPrimary = Color(0xFF1A1A1A);
  static const Color lightTextSecondary = Color(0xFF6B7280);
  static const Color lightAccent = Color(0xFF4F46E5); // 低饱和靛蓝
  static const Color lightAccentSoft = Color(0xFFEDEBFB); // 强调色浅底
  static const Color lightOnAccent = Color(0xFFFFFFFF);
  static const Color lightUserBubble = Color(0xFF4F46E5);
  static const Color lightAiBubble = Color(0xFFEEEEF0);
  static const Color lightDivider = Color(0xFFECECEE);
  static const Color lightShadow = Color(0x14000000); // 柔和阴影

  // ── Dark ────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF18181B);
  static const Color darkSurface = Color(0xFF222226);
  static const Color darkSurfaceTint = Color(0xFF2A2A2F); // AI 气泡/浅表面
  static const Color darkTextPrimary = Color(0xFFE8E8EA);
  static const Color darkTextSecondary = Color(0xFF9CA0A8);
  static const Color darkAccent = Color(0xFF6366F1); // 略亮的靛蓝
  static const Color darkAccentSoft = Color(0xFF2E2A55);
  static const Color darkOnAccent = Color(0xFFFFFFFF);
  static const Color darkUserBubble = Color(0xFF6366F1);
  static const Color darkAiBubble = Color(0xFF2A2A2F);
  static const Color darkDivider = Color(0xFF2E2E33);
  static const Color darkShadow = Color(0x40000000);

  /// 通用圆角
  static const double radius = 14;
  static const double radiusTail = 4; // 气泡尾角
}
