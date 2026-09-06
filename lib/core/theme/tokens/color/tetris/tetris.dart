// Layer 1 — 俄罗斯方块 native 配色常量（Charcoal）。
//
// tetris 棋盘配色作为特例独立于 5 主题（玩家靠颜色识别方块）。
// 不从 ColorScheme 派生，所有色值跨主题锁定。
//
// 视觉：深色灰黑井（非纯黑）+ 干净糖果七色。
// 索引约定：与 engine 一致用 1..7（kPieceI=1 ... kPieceL=7）。
// 用 Map<int, Color> 强制要求显式索引，结构上避免 0..6 列表的 off-by-one。

import 'package:flutter/material.dart';

class TetrisColors {
  TetrisColors._();

  /// 方块顶部薄高光（白 @ 50%）
  static const Color cellHighlight = Color(0x80FFFFFF);

  /// 棋盘井底（标准炭灰深档，跨主题锁定）
  static const Color pieceBackground = Color(0xFF1C1F24);

  /// 棋盘井中档（竖向渐变中间色）
  static const Color wellMid = Color(0xFF252A31);

  /// 棋盘井浅档（竖向渐变顶部）
  static const Color wellLift = Color(0xFF2E343D);

  /// 网格线（白 @ ~4.5%）
  static const Color pieceGridLine = Color(0x0BFFFFFF);

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
