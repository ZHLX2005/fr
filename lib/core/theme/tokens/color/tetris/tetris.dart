// Layer 1 — 俄罗斯方块颜色常量（棋盘环境 + 方块识别色）。
//
// 棋盘环境色从 ColorScheme 派生，方块识别色从 BaseColors 锁定。

import 'package:flutter/material.dart';
import '../base/base.dart';

class TetrisColors {
  TetrisColors._();

  /// 方块顶部亮面（3D 立体感）—— scheme.onSurface @ 28% alpha
  static Color cellHighlight(ColorScheme scheme) => scheme.onSurface.withValues(alpha: 0.28);

  /// 棋盘底色 —— scheme.surfaceContainerHighest
  static Color pieceBackground(ColorScheme scheme) => scheme.surfaceContainerHighest;

  /// 网格线 —— scheme.outline
  static Color pieceGridLine(ColorScheme scheme) => scheme.outline;

  /// 7 方块色（识别色锁定，跨主题不变）
  static const List<Color> pieceColors = [
    BaseColors.pieceI, BaseColors.pieceO, BaseColors.pieceT,
    BaseColors.pieceS, BaseColors.pieceZ, BaseColors.pieceJ, BaseColors.pieceL,
  ];
}