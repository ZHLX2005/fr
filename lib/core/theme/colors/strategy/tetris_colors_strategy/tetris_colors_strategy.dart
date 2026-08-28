// Layer 2.5: 俄罗斯方块颜色策略契约。
//
// 合并俄罗斯方块的棋盘环境 + 方块识别色为单一 strategy：
//   · 棋盘环境（cellHighlight / pieceBackground / pieceGridLine）—— 从 ColorScheme 派生（跟主题）
//   · 方块识别色（pieceColors）—— 从 BaseColors 锁定（跨主题不变，国际通用识别色）

import 'package:flutter/material.dart';

@immutable
abstract class TetrisColorsStrategy {
  const TetrisColorsStrategy();

  /// 棋盘环境派生源（跟主题用）
  ColorScheme get scheme;

  /// 方块顶部亮面（3D 立体感）—— scheme.onSurface @ 28% alpha
  Color get cellHighlight;

  /// 棋盘底色 —— scheme.surfaceContainerHighest
  Color get pieceBackground;

  /// 网格线 —— scheme.outline
  Color get pieceGridLine;

  /// 7 方块色（按 [PieceType] 索引 0..6：I/O/T/S/Z/J/L）—— 跨主题锁定
  List<Color> get pieceColors;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TetrisColorsStrategy &&
          runtimeType == other.runtimeType &&
          scheme == other.scheme &&
          cellHighlight == other.cellHighlight &&
          pieceBackground == other.pieceBackground &&
          pieceGridLine == other.pieceGridLine &&
          _listEq(pieceColors, other.pieceColors);

  @override
  int get hashCode => Object.hash(
    scheme, cellHighlight, pieceBackground, pieceGridLine,
    Object.hashAll(pieceColors),
  );

  static bool _listEq(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}