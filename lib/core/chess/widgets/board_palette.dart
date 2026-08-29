// lib/core/chess/widgets/board_palette.dart
//
// 自定义棋盘配色模型 —— 棋盘渲染层的可选覆盖色。
//
// 优先级（本文件存在的核心语义）：
//   boardPalette?.X ?? context.chessColors.X
//   （用户自定义 > 主题默认 —— 用户改过的颜色永远优先，没改的跟随主题）
//
// 设计：
//   · 所有字段可空 —— null = "不覆盖，用主题默认"（context.chessColors.X）
//   · 至少实现 lightSquare / darkSquare 两主格色（用户最常改的两项），
//     其余角色同样可覆盖（预留给未来扩展）
//   · @immutable 值类，==/hashCode 按字段实现
//
// 持久化：BoardColorPrefs（board_color_prefs.dart）只 round-trip
// lightSquare / darkSquare（v1 主线），其余字段内存态可用。

import 'package:flutter/material.dart';

/// 自定义棋盘配色。所有字段可空 —— null 表示"用主题默认"（context.chessColors）。
///
/// 优先级：`boardPalette?.X ?? context.chessColors.X`（用户自定义 > 主题）。
@immutable
class BoardPalette {
  /// 浅色格（覆盖主题 lightSquare）。
  final Color? lightSquare;

  /// 深色格（覆盖主题 darkSquare）。
  final Color? darkSquare;

  /// 格子描边（覆盖主题 gridLine）。
  final Color? gridLine;

  /// 选中格高亮（覆盖主题 selectedSquare）。
  final Color? selectedSquare;

  /// 上一步 from/to 高亮（覆盖主题 lastMoveHighlight）。
  final Color? lastMoveHighlight;

  /// 合法走法圆点提示（覆盖主题 legalMoveHint）。
  final Color? legalMoveHint;

  /// 吃子走法圆圈提示（覆盖主题 captureHint）。
  final Color? captureHint;

  /// 将军警告红覆盖（覆盖主题 checkWarning）。
  final Color? checkWarning;

  const BoardPalette({
    this.lightSquare,
    this.darkSquare,
    this.gridLine,
    this.selectedSquare,
    this.lastMoveHighlight,
    this.legalMoveHint,
    this.captureHint,
    this.checkWarning,
  });

  /// 全部字段为 null（完全跟随主题）→ true。
  bool get isEmpty =>
      lightSquare == null &&
      darkSquare == null &&
      gridLine == null &&
      selectedSquare == null &&
      lastMoveHighlight == null &&
      legalMoveHint == null &&
      captureHint == null &&
      checkWarning == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardPalette &&
          lightSquare == other.lightSquare &&
          darkSquare == other.darkSquare &&
          gridLine == other.gridLine &&
          selectedSquare == other.selectedSquare &&
          lastMoveHighlight == other.lastMoveHighlight &&
          legalMoveHint == other.legalMoveHint &&
          captureHint == other.captureHint &&
          checkWarning == other.checkWarning;

  @override
  int get hashCode => Object.hash(
        lightSquare,
        darkSquare,
        gridLine,
        selectedSquare,
        lastMoveHighlight,
        legalMoveHint,
        captureHint,
        checkWarning,
      );
}
