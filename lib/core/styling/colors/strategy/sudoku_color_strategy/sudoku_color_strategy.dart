// Layer 3: 数独 ColorStrategy 契约。
//
// 与通用 ColorStrategy（context.colors，6 角色）、board_color_strategy、
// chess_color_strategy 平行，专为数独棋盘 UI 设计：
//   cellBg (filled/empty/initial) / cellText / cellText.error / cellSelected
//   / cellError / cellInitial / cellNote / gridLine / accent
//
// 为什么 sudoku 不复用 chess_color_strategy：
//   · chess 是"两色格对照"语义（lightSquare / darkSquare），sudoku 是
//     "三态格"语义（filled 已填 / empty 空 / initial 题目给出的初始格），
//     强行复用 chess 的 two-tone 模型会丢失"题目/答案区分"
//   · sudoku 需要 cellNote（笔记候选色，弱灰），chess 没有"候选标记"概念
//   · sudoku 需要 cellText.error（错误填写红字），chess 的 checkWarning
//     是整格覆盖而非文字着色，强独立通道便于后续加动画
//
// 各棋牌游戏保留自己 constants 里的"语义棋子色"（棋子识别色），
// 那是国际通用识别色，棋子本体最终通过 asset bundle 实现（用户后续提供）。

import 'package:flutter/material.dart';

/// 数独格子背景三态。
@immutable
class SudokuCellBg {
  final Color filled;
  final Color empty;
  final Color initial;

  const SudokuCellBg({
    required this.filled,
    required this.empty,
    required this.initial,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SudokuCellBg &&
          filled == other.filled &&
          empty == other.empty &&
          initial == other.initial;

  @override
  int get hashCode => Object.hash(filled, empty, initial);
}

/// 数独格子文字色（含错误态）。
@immutable
class SudokuCellText {
  final Color regular;
  final Color error;

  const SudokuCellText({required this.regular, required this.error});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SudokuCellText && regular == other.regular && error == other.error;

  @override
  int get hashCode => Object.hash(regular, error);
}

@immutable
abstract class SudokuColorStrategy {
  const SudokuColorStrategy();

  // ── 格子背景三态 ──────────────────────────────────────────

  /// 已填写格的背景色（玩家填入的答案）
  SudokuCellBg get cellBg;

  // ── 格子文字 ──────────────────────────────────────────────

  /// 格子内文字色（含错误红字）
  SudokuCellText get cellText;

  // ── 交互高亮 ──────────────────────────────────────────────

  /// 当前选中格高亮
  Color get cellSelected;

  /// 错误格警示（与 cellText.error 同源，保留独立通道便于后续加 overlay 动画）
  Color get cellError;

  /// 题目初始格标记色（与 cellText.regular 区分，通常加粗）
  Color get cellInitial;

  /// 笔记候选色（候选数字的弱色显示）
  Color get cellNote;

  // ── 棋盘基础结构色 ────────────────────────────────────────

  /// 9x9 格子间细线 / 粗线（粗线标 3x3 宫分隔）
  Color get gridLine;

  /// 强调色（选中行 / 列的高亮底色）
  Color get accent;

  /// 完整 ColorScheme 兜底（保留以与其他 strategy 对称）
  ColorScheme get scheme;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SudokuColorStrategy &&
          runtimeType == other.runtimeType &&
          cellBg == other.cellBg &&
          cellText == other.cellText &&
          cellSelected == other.cellSelected &&
          cellError == other.cellError &&
          cellInitial == other.cellInitial &&
          cellNote == other.cellNote &&
          gridLine == other.gridLine &&
          accent == other.accent;

  @override
  int get hashCode => Object.hash(
        cellBg,
        cellText,
        cellSelected,
        cellError,
        cellInitial,
        cellNote,
        gridLine,
        accent,
      );
}