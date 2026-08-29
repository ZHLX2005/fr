// Layer 1 — 俄罗斯方块 native 配色常量。
//
// tetris 棋盘配色作为特例独立于 5 主题（玩家靠颜色识别方块）。
// 不从 ColorScheme 派生，所有色值跨主题锁定。
//
// 索引约定：与 engine 一致用 1..7（kPieceI=1 ... kPieceL=7）。
// 用 Map<int, Color> 强制要求显式索引，结构上避免 0..6 列表的 off-by-one。

import 'package:flutter/material.dart';

class TetrisColors {
  TetrisColors._();

  /// 方块顶部 3D 亮面（深色棋盘上用白 @ 28%，跨主题锁定）
  static const Color cellHighlight = Color(0xB3FFFFFF); // white @ 0.28 alpha

  /// 棋盘底色（slate-900 深色，跨主题锁定）
  static const Color pieceBackground = Color(0xFF0F172A);

  /// 网格线（白色 5% 透明，跨主题锁定）
  static const Color pieceGridLine = Color(0x0DFFFFFF); // white @ 0.05 alpha

  /// 7 方块识别色（按 kPieceI..kPieceL 索引 1..7，跨主题锁定）
  /// Map 强制要求显式索引，结构上避免 0..6 列表的 off-by-one。
  static const Map<int, Color> pieceColors = {
    /*kPieceI*/1: Color(0xFF22D3EE), // cyan-400
    /*kPieceO*/2: Color(0xFFFACC15), // yellow-400
    /*kPieceT*/3: Color(0xFFA855F7), // purple-500
    /*kPieceS*/4: Color(0xFF22C55E), // green-500
    /*kPieceZ*/5: Color(0xFFEF4444), // red-500
    /*kPieceJ*/6: Color(0xFF3B82F6), // blue-500
    /*kPieceL*/7: Color(0xFFF97316), // orange-500
  };
}
