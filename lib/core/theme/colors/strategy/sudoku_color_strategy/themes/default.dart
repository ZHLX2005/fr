// Layer 3 — DefaultSudokuColorStrategy：从 sudoku_colors 派生 8 角色。
//
// 8 角色全部用 scheme 派生方法（SudokuColors.*From(scheme)），跟主题走。
// 同一 scheme 调用 .of() 多次返回同一实例（scheme 相等缓存去重）。
//
// 5 主题（zen/purple/ink/rose/lemon）切换时，scheme 变了会重新派生，
// 因此本类天然支持"全主题覆盖"而无需 per-theme 文件 —— 与 chess 行为一致。

import 'package:flutter/material.dart';

import '../sudoku_color_strategy.dart';
import 'sudoku_colors.dart';

class DefaultSudokuColorStrategy extends SudokuColorStrategy {
  @override
  final ColorScheme scheme;

  const DefaultSudokuColorStrategy._(this.scheme);

  static DefaultSudokuColorStrategy? _cached;

  factory DefaultSudokuColorStrategy.of(ColorScheme scheme) {
    final cached = _cached;
    if (cached != null && cached.scheme == scheme) return cached;
    final instance = DefaultSudokuColorStrategy._(scheme);
    _cached = instance;
    return instance;
  }

  @override
  SudokuCellBg get cellBg => SudokuColors.cellBgFrom(scheme);

  @override
  SudokuCellText get cellText => SudokuColors.cellTextFrom(scheme);

  @override
  Color get cellSelected => SudokuColors.cellSelectedFrom(scheme);

  @override
  Color get cellError => SudokuColors.cellErrorFrom(scheme);

  @override
  Color get cellInitial => SudokuColors.cellInitialFrom(scheme);

  @override
  Color get cellNote => SudokuColors.cellNoteFrom(scheme);

  @override
  Color get gridLine => SudokuColors.gridLineFrom(scheme);

  @override
  Color get accent => SudokuColors.accentFrom(scheme);
}