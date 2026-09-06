// Layer 1 — 俄罗斯方块 native 配色常量（Ash flat well）。
//
// tetris 棋盘配色作为特例独立于 5 主题（玩家靠颜色识别方块）。
// 不从 ColorScheme 派生，所有色值跨主题锁定。
//
// 视觉：中灰井纯色（无渐变）+ 糖果七色立体方块。
// 索引约定：与 engine 一致用 1..7（kPieceI=1 ... kPieceL=7）。
// 用 Map<int, Color> 强制要求显式索引，结构上避免 0..6 列表的 off-by-one。

import 'package:flutter/material.dart';

class TetrisColors {
  TetrisColors._();

  /// 方块顶部薄高光（白 @ 50%）
  static const Color cellHighlight = Color(0x80FFFFFF);

  /// 棋盘井底（Ash 中灰纯色，跨主题锁定，无渐变）
  static const Color pieceBackground = Color(0xFF3A414C);

  /// 网格线（白 @ ~7%）
  static const Color pieceGridLine = Color(0x12FFFFFF);

  /// 7 方块糖果识别色（按 kPieceI..kPieceL 索引 1..7，跨主题锁定）
  static const Map<int, Color> pieceColors = {
    /*kPieceI*/ 1: Color(0xFF2AD4E0), // candy cyan
    /*kPieceO*/ 2: Color(0xFFF5C518), // candy gold
    /*kPieceT*/ 3: Color(0xFFA56BFF), // candy violet
    /*kPieceS*/ 4: Color(0xFF3DD68C), // candy green
    /*kPieceZ*/ 5: Color(0xFFFF5A7A), // candy rose
    /*kPieceJ*/ 6: Color(0xFF4B7BFF), // candy blue
    /*kPieceL*/ 7: Color(0xFFFF9A3D), // candy orange
  };
}
