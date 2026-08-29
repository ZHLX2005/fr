// Layer 3 — DefaultChessColorStrategy：从 tokens/color/chess 派生 13 角色。
//
// 13 角色全部用 scheme 派生方法（ChessColors.*From(scheme)），跟主题走。
// 同一 scheme 调用 .of() 多次返回同一实例（scheme 相等缓存去重）。

import 'package:flutter/material.dart';

import '../../../../tokens/color/chess/chess.dart';
import '../chess_color_strategy.dart';

class DefaultChessColorStrategy extends ChessColorStrategy {
  @override
  final ColorScheme scheme;

  const DefaultChessColorStrategy._(this.scheme);

  static DefaultChessColorStrategy? _cached;

  factory DefaultChessColorStrategy.of(ColorScheme scheme) {
    final cached = _cached;
    if (cached != null && cached.scheme == scheme) return cached;
    final instance = DefaultChessColorStrategy._(scheme);
    _cached = instance;
    return instance;
  }

  @override
  Color get lightSquare => ChessColors.lightSquareFrom(scheme);

  @override
  Color get darkSquare => ChessColors.darkSquareFrom(scheme);

  @override
  Color get gridLine => ChessColors.gridLineFrom(scheme);

  @override
  Color get coordinateLabel => ChessColors.coordinateLabelFrom(scheme);

  @override
  Color get selectedSquare => ChessColors.selectedSquareFrom(scheme);

  @override
  Color get lastMoveHighlight => ChessColors.lastMoveHighlightFrom(scheme);

  @override
  Color get legalMoveHint => ChessColors.legalMoveHintFrom(scheme);

  @override
  Color get captureHint => ChessColors.captureHintFrom(scheme);

  @override
  Color get checkWarning => ChessColors.checkWarningFrom(scheme);

  @override
  Color get checkmateOverlay => ChessColors.checkmateOverlayFrom(scheme);

  @override
  Color get promotionOverlay => ChessColors.promotionOverlayFrom(scheme);

  @override
  Color get promotionBorder => ChessColors.promotionBorderFrom(scheme);
}
