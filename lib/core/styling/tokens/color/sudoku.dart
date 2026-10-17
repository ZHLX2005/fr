// Layer 1 — 数独棋盘色板（8 角色 + cellBg/cellText 子结构 DTO）。
//
// 双层结构：
//   · const Color 基础色（无主题时使用，hex 兜底）
//   · scheme 派生方法（有主题时 strategy 默认调用，跟主题走）
//
// 2026-10 自 colors/strategy/sudoku_color_strategy/themes/ 迁入 tokens 层，
// 与 board/chess 分层对齐（strategy → token 单向依赖）。
// SudokuCellBg / SudokuCellText DTO 随迁（SudokuColors.*From 的返回类型，
// 定义在这里避免 token 反向 import strategy）。
//
// 配色设计要点：
//   · cellBg.filled / empty / initial —— 三态格语义，
//     filled（玩家答案）与 initial（题目给出）视觉要可区分
//   · cellText.error —— 用 scheme.error 保持"危险"语义
//   · cellSelected —— scheme.primary 派生（选中行/列高亮）
//   · accent —— scheme.tertiary（与 cellSelected 区分，避免混淆）

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

class SudokuColors {
  SudokuColors._();

  // ─── cellBg 基础色（hex 兜底）───────────────────────────────

  /// 已填格 —— 暖米白
  static const Color cellBgFilled = Color(0xFFEBE5D6);

  /// 空格 —— 略深米色
  static const Color cellBgEmpty = Color(0xFFDCD3BD);

  /// 题目初始格 —— 略浅米色（与 filled 区分，给视觉提示"这是题目给的"）
  static const Color cellBgInitial = Color(0xFFF4F1EA);

  // ─── cellText 基础色 ──────────────────────────────────────

  /// 常规文字 —— 深棕
  static const Color cellTextRegular = Color(0xFF3D3127);

  /// 错误红字 —— 章印朱红
  static const Color cellTextError = Color(0xFFB04650);

  // ─── 单角色基础色 ──────────────────────────────────────────

  /// 选中格 —— sage 绿 @ 35%
  static const Color cellSelected = Color(0x597A9A7E);

  /// 错误格警示 —— 章印朱红（与 cellTextError 同色，保留独立通道）
  static const Color cellError = Color(0xFFB04650);

  /// 初始格文字加粗 —— 深棕（同 cellTextRegular，由 widget 层加粗）
  static const Color cellInitial = Color(0xFF3D3127);

  /// 笔记候选 —— 茶灰
  static const Color cellNote = Color(0x808A8475);

  /// 网格线 —— 暖灰
  static const Color gridLine = Color(0xFF8A8475);

  /// 强调色 —— 鎏金（与 cellSelected 区分）
  static const Color accent = Color(0xFFA07E5A);

  // ─── scheme 派生（跟主题）───────────────────────────────
  //
  // 设计目标：主题切换时，数独棋盘三态格语义、错误警示、
  // 选中高亮始终保持，具体颜色暖度跟随环境色温。

  /// cellBg —— 三态格派生
  static SudokuCellBg cellBgFrom(ColorScheme scheme) => SudokuCellBg(
        filled: scheme.surface,
        empty: scheme.surfaceContainerHighest,
        initial: scheme.surfaceContainerLow,
      );

  /// cellText —— 含 error 派生
  static SudokuCellText cellTextFrom(ColorScheme scheme) => SudokuCellText(
        regular: scheme.onSurface,
        error: scheme.error,
      );

  /// 选中格 —— scheme.primary @ 35% alpha
  static Color cellSelectedFrom(ColorScheme scheme) =>
      scheme.primary.withValues(alpha: 0.35);

  /// 错误格 —— scheme.error
  static Color cellErrorFrom(ColorScheme scheme) => scheme.error;

  /// 初始格文字 —— scheme.onSurface（widget 层加粗区分）
  static Color cellInitialFrom(ColorScheme scheme) => scheme.onSurface;

  /// 笔记候选 —— scheme.onSurfaceVariant @ 50%
  static Color cellNoteFrom(ColorScheme scheme) =>
      scheme.onSurfaceVariant.withValues(alpha: 0.50);

  /// 网格线 —— scheme.outline @ 60% （细线不要太抢眼）
  static Color gridLineFrom(ColorScheme scheme) =>
      scheme.outline.withValues(alpha: 0.6);

  /// 强调色 —— scheme.tertiary（选中行/列高亮，与 cellSelected 区分）
  static Color accentFrom(ColorScheme scheme) => scheme.tertiary;
}
