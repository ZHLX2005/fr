// Layer 1 — 对弈棋盘 11 角色色板。
//
// 双层结构：
//   · 11 个 const Color 基础色（无主题时使用，hex 兜底）
//   · 11 个 scheme 派生方法（有主题时 strategy 默认调用，跟主题走）
//
// 基础色参考 zen 主题米色系（zen 是范本 light 主题），无主题 fallback。

import 'package:flutter/material.dart';

class BoardColors {
  BoardColors._();

  // ─── 11 角色基础色（hex 兜底，无主题时使用）────────────────

  /// 棋盘底色 —— 米色
  static const Color background = Color(0xFFF4F1EA);

  /// 网格线 —— 暖灰
  static const Color gridLine = Color(0xFFD9D5C8);

  /// 坐标轴 / 行列标签 —— 茶色
  static const Color axisLabel = Color(0xFF8A8475);

  /// 玩家 1 棋子 —— 墨黑（深色棋子）
  static const Color player1Stone = Color(0xFF1A1A1A);

  /// 玩家 2 棋子 —— 纯白（浅色棋子）
  static const Color player2Stone = Color(0xFFFFFFFF);

  /// 落子预览 —— sage 绿 @ 40% alpha (0x66 = 102/255 ≈ 40%)
  static const Color hint = Color(0x667A9A7E);

  /// 胜负高亮 —— 陶土红（互补色跳出主题）
  static const Color winHighlight = Color(0xFFA0594A);

  /// 最后落子位置 —— 浅米绿
  static const Color lastMove = Color(0xFFE8F0E5);

  /// 错误 / 非法标记 —— 章印朱红
  static const Color errorMark = Color(0xFFB04650);

  /// 中性元素色 —— 茶色
  static const Color neutral = Color(0xFF8A8475);

  // ─── 11 角色 scheme 派生（跟主题）────────────────────────

  /// 棋盘底色 —— scheme.surfaceContainerHighest
  static Color backgroundFrom(ColorScheme scheme) => scheme.surfaceContainerHighest;

  /// 网格线 —— scheme.outline
  static Color gridLineFrom(ColorScheme scheme) => scheme.outline;

  /// 坐标轴 —— scheme.onSurfaceVariant
  static Color axisLabelFrom(ColorScheme scheme) => scheme.onSurfaceVariant;

  /// 玩家 1 棋子 —— scheme.onSurface
  static Color player1StoneFrom(ColorScheme scheme) => scheme.onSurface;

  /// 玩家 2 棋子 —— scheme.surface
  static Color player2StoneFrom(ColorScheme scheme) => scheme.surface;

  /// 落子预览 —— scheme.primary @ 40% alpha
  static Color hintFrom(ColorScheme scheme) => scheme.primary.withValues(alpha: 0.4);

  /// 胜负高亮 —— scheme.tertiary
  static Color winHighlightFrom(ColorScheme scheme) => scheme.tertiary;

  /// 最后落子 —— scheme.primaryContainer
  static Color lastMoveFrom(ColorScheme scheme) => scheme.primaryContainer;

  /// 错误标记 —— scheme.error
  static Color errorMarkFrom(ColorScheme scheme) => scheme.error;

  /// 中性 —— scheme.onSurfaceVariant
  static Color neutralFrom(ColorScheme scheme) => scheme.onSurfaceVariant;
}