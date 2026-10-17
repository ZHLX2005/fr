// Layer 3 — DefaultBoardColorStrategy：从 tokens/color/board 派生 11 角色。
//
// 11 角色全部用 scheme 派生方法（BoardColors.*From(scheme)），跟主题走。
// 同一 scheme 调用 .of() 多次返回同一实例（scheme 相等缓存去重）。

import 'package:flutter/material.dart';

import '../../../../tokens/color/board/board.dart';
import '../board_color_strategy.dart';

class DefaultBoardColorStrategy extends BoardColorStrategy {
  @override
  final ColorScheme scheme;

  const DefaultBoardColorStrategy._(this.scheme);

  static DefaultBoardColorStrategy? _cached;

  factory DefaultBoardColorStrategy.of(ColorScheme scheme) {
    final cached = _cached;
    if (cached != null && cached.scheme == scheme) return cached;
    final instance = DefaultBoardColorStrategy._(scheme);
    _cached = instance;
    return instance;
  }

  @override
  Color get background => BoardColors.backgroundFrom(scheme);

  @override
  Color get gridLine => BoardColors.gridLineFrom(scheme);

  @override
  Color get axisLabel => BoardColors.axisLabelFrom(scheme);

  @override
  Color get player1Stone => BoardColors.player1StoneFrom(scheme);

  @override
  Color get player2Stone => BoardColors.player2StoneFrom(scheme);

  @override
  Color get hint => BoardColors.hintFrom(scheme);

  @override
  Color get winHighlight => BoardColors.winHighlightFrom(scheme);

  @override
  Color get lastMove => BoardColors.lastMoveFrom(scheme);

  @override
  Color get errorMark => BoardColors.errorMarkFrom(scheme);

  @override
  Color get neutral => BoardColors.neutralFrom(scheme);
}