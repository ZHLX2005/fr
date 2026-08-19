// 默认棋局 ColorStrategy：从 ColorScheme 派生 11 个棋盘 UI 角色。
//
// 映射规则：
//   · background      = scheme.surfaceContainerHighest（棋盘沉到最深容器色）
//   · gridLine        = scheme.outline（细描边）
//   · axisLabel       = scheme.onSurfaceVariant（次级文字色）
//   · player1Stone    = scheme.onSurface（深色棋子）
//   · player2Stone    = scheme.surface（浅色棋子，与 player1Stone 反色）
//   · hint            = scheme.primary @ 40% 透明（落子预览）
//   · winHighlight    = scheme.tertiary（互补色，胜局跳出）
//   · lastMove        = scheme.primaryContainer（最后落子标记）
//   · errorMark       = scheme.error（复用红，保持危险语义）
//   · neutral         = scheme.onSurfaceVariant（中性元素）
//
// 切到任意主题（墨青/夜间/茶禅...）棋盘都自动跟，包括 zen 的米底+绿主题。

import 'package:flutter/material.dart';

import 'board_color_strategy.dart';

class DefaultBoardColorStrategy extends BoardColorStrategy {
  @override
  final ColorScheme scheme;

  static DefaultBoardColorStrategy? _cached;

  factory DefaultBoardColorStrategy.of(ColorScheme scheme) {
    final cached = _cached;
    if (cached != null && cached.scheme == scheme) return cached;
    final instance = DefaultBoardColorStrategy._(scheme);
    _cached = instance;
    return instance;
  }

  const DefaultBoardColorStrategy._(this.scheme);

  @override
  Color get background => scheme.surfaceContainerHighest;

  @override
  Color get gridLine => scheme.outline;

  @override
  Color get axisLabel => scheme.onSurfaceVariant;

  @override
  Color get player1Stone => scheme.onSurface;

  @override
  Color get player2Stone => scheme.surface;

  @override
  Color get hint => scheme.primary.withValues(alpha: 0.4);

  @override
  Color get winHighlight => scheme.tertiary;

  @override
  Color get lastMove => scheme.primaryContainer;

  @override
  Color get errorMark => scheme.error;

  @override
  Color get neutral => scheme.onSurfaceVariant;
}