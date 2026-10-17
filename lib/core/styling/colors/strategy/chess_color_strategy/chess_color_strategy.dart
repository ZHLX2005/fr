// Layer 3: 国际象棋 ColorStrategy 契约。
//
// 与通用 ColorStrategy（context.colors，6 角色）和 board_color_strategy
// （context.boardColors，11 角色）平行，专为国际象棋棋盘 UI 设计：
//   浅色格 / 深色格 / 网格 / 坐标 / 选中 / 上一步 / 走法提示 / 吃子提示
//   / 将军 / 将杀覆盖 / 升变面板 / 升变边框 / scheme
//
// 为什么 chess 不复用 board_color_strategy：
//   · 国际象棋需要"两色格对照"语义（lightSquare + darkSquare），
//     board_color_strategy 的 background 单色底没法表达 8x8 棋盘的两色对照
//   · chess 需要 promotionOverlay + promotionBorder（升变选择面板专用色），
//     其他棋类没有"升变"概念
//   · chess 需要 checkWarning（将军红覆盖）—— 与 board 的 errorMark 同义但
//     语义焦点不同；强独立通道后续可加 animation
//   · 为"识别色锁定"业务（tetris/teamAvatar）专门独立通道，
//     chess 是"scheme 派生"业务，独立通道避免稀释 board_color_strategy
//
// 各棋牌游戏保留自己 constants 里的"语义棋子色"（chess 白/黑方、PIN/FEN
// 标识），那是国际通用识别色，棋子本体最终通过 asset bundle 实现（用户后续提供）。

import 'package:flutter/material.dart';

@immutable
abstract class ChessColorStrategy {
  const ChessColorStrategy();

  // ── 棋盘两色格（核心对照语义）────────────────────────────

  /// 浅色格（国际象棋标准：白方子在右下角的浅格上）
  Color get lightSquare;

  /// 深色格
  Color get darkSquare;

  // ── 棋盘基础结构色 ──────────────────────────────────────

  /// 棋盘格子间细线（描边）
  Color get gridLine;

  /// 坐标轴 / 行列标签文字（a-h / 1-8）
  Color get coordinateLabel;

  // ── 交互高亮（三档强度）────────────────────────────────

  /// 当前选中格高亮（最强）
  Color get selectedSquare;

  /// 上一步落子位置高亮（中）
  Color get lastMoveHighlight;

  /// 合法走法提示（弱，圆点）
  Color get legalMoveHint;

  /// 吃子走法提示（弱，圆圈包住对方子，颜色与 legalMoveHint 区分）
  Color get captureHint;

  // ── 警告与终局 ──────────────────────────────────────────

  /// 将军警告（红色覆盖在被将的王所在格上）
  Color get checkWarning;

  /// 将杀 / 终局覆盖层（深色压住整盘，宣示结束）
  Color get checkmateOverlay;

  // ── 升变（promotion 面板） ────────────────────────────────

  /// 升变选择面板背景
  Color get promotionOverlay;

  /// 升变选择面板边框
  Color get promotionBorder;

  /// 完整 ColorScheme 兜底（保留以与其他 strategy 对称）
  ColorScheme get scheme;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChessColorStrategy &&
          runtimeType == other.runtimeType &&
          lightSquare == other.lightSquare &&
          darkSquare == other.darkSquare &&
          gridLine == other.gridLine &&
          coordinateLabel == other.coordinateLabel &&
          selectedSquare == other.selectedSquare &&
          lastMoveHighlight == other.lastMoveHighlight &&
          legalMoveHint == other.legalMoveHint &&
          captureHint == other.captureHint &&
          checkWarning == other.checkWarning &&
          checkmateOverlay == other.checkmateOverlay &&
          promotionOverlay == other.promotionOverlay &&
          promotionBorder == other.promotionBorder;

  @override
  int get hashCode => Object.hash(
        lightSquare, darkSquare, gridLine, coordinateLabel,
        selectedSquare, lastMoveHighlight, legalMoveHint, captureHint,
        checkWarning, checkmateOverlay, promotionOverlay, promotionBorder,
      );
}
