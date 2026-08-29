// Layer 2 — DefaultTetrisColorsStrategy：tetris 棋盘 4 角色走 native const。
//
// tetris 是 5 主题特例，所有角色从 TetrisColors 跨主题锁定的 const 取，
// 不再从 ColorScheme 派生。scheme 仍保留作接口契约（不变入派生）。

import 'package:flutter/material.dart';

import '../../../../tokens/color/tetris/tetris.dart';
import '../tetris_colors_strategy.dart';

class DefaultTetrisColorsStrategy extends TetrisColorsStrategy {
  @override
  final ColorScheme scheme;

  static DefaultTetrisColorsStrategy? _cached;

  factory DefaultTetrisColorsStrategy.of(ColorScheme scheme) {
    final cached = _cached;
    if (cached != null && cached.scheme == scheme) return cached;
    final instance = DefaultTetrisColorsStrategy._(scheme);
    _cached = instance;
    return instance;
  }

  const DefaultTetrisColorsStrategy._(this.scheme);

  @override
  Color get cellHighlight => TetrisColors.cellHighlight;

  @override
  Color get pieceBackground => TetrisColors.pieceBackground;

  @override
  Color get pieceGridLine => TetrisColors.pieceGridLine;

  @override
  Map<int, Color> get pieceColors => TetrisColors.pieceColors;
}
