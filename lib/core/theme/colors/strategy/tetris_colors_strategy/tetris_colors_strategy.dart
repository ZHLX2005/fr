// Layer 2.5: 俄罗斯方块颜色策略契约。
//
// tetris 棋盘配色作为 5 主题特例 —— 跨主题锁定，不跟主题切换。
// 抽象保留以保持与 ColorStrategy / BoardColorStrategy / TeamAvatarStrategy /
// TorchProtectStrategy 的架构对称；实现层走 native const。
//
// pieceColors 用 Map<int, Color> 索引 1..7（与 engine / Lua 协议一致），
// 结构上防止 0..6 列表的 off-by-one（之前 L 块 type 7 越界 → "方块消失"）。

import 'package:flutter/material.dart';

@immutable
abstract class TetrisColorsStrategy {
  const TetrisColorsStrategy();

  /// 当前 ColorScheme（保留接口契约，tetris 实现下不参与派生）。
  ColorScheme get scheme;

  /// 方块顶部 3D 亮面
  Color get cellHighlight;

  /// 棋盘底色
  Color get pieceBackground;

  /// 网格线
  Color get pieceGridLine;

  /// 7 方块识别色（按 kPieceI..kPieceL 索引 1..7）
  Map<int, Color> get pieceColors;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TetrisColorsStrategy &&
          runtimeType == other.runtimeType &&
          scheme == other.scheme &&
          cellHighlight == other.cellHighlight &&
          pieceBackground == other.pieceBackground &&
          pieceGridLine == other.pieceGridLine &&
          _mapEq(pieceColors, other.pieceColors);

  @override
  int get hashCode => Object.hash(
    scheme, cellHighlight, pieceBackground, pieceGridLine,
    Object.hashAllUnordered(
      pieceColors.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  static bool _mapEq(Map<int, Color> a, Map<int, Color> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || a[k] != b[k]) return false;
    }
    return true;
  }
}
