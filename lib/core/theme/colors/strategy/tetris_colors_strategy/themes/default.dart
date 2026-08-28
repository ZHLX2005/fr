// Layer 2 — DefaultTetrisColorsStrategy：从 tokens/color/tetris 派生 4 角色。
//
// 棋盘环境从 scheme 派生，方块识别色从 BaseColors 锁定（跨主题不变）。

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
  Color get cellHighlight => TetrisColors.cellHighlight(scheme);

  @override
  Color get pieceBackground => TetrisColors.pieceBackground(scheme);

  @override
  Color get pieceGridLine => TetrisColors.pieceGridLine(scheme);

  @override
  List<Color> get pieceColors => TetrisColors.pieceColors;
}