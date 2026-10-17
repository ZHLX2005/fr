// Layer 1 — 对弈棋盘 10 角色派生色板。
//
// 全部角色从 ColorScheme 派生（strategy 默认调用，跟主题走）。
// 历史上的 hex 兜底常量已于 2026-10 删除（0 消费者），
// 单一定义处即本文件的 *From(scheme) 方法。

import 'package:flutter/material.dart';

class BoardColors {
  BoardColors._();

  // ─── 10 角色 scheme 派生（跟主题）────────────────────────

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
