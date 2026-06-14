// Reversi (Othello) 黑白翻转棋 - 全局常量
//
// 所有跨组件共享的常量集中在此文件，避免同名常量分散多处
// 修改时只需改一处，减少遗漏导致的 bug
//
// ## 常量使用一览
//
// ### 棋盘规则
// | 常量 | 用途 |
// |------|------|
// | `boardSize` | 棋盘边长（8x8）|
// | `undoSteps` | 一次悔棋撤销的步数（撤 2 步回到当前方决策点）|
//
// ### 配色（reversi_page.dart 专属）
// | 常量 | 用途 |
// |------|------|
// | `boardBackground` | 棋盘底色（经典绿）|
// | `cellLine` | 格线颜色 |
// | `blackPiece` / `whitePiece` | 黑/白棋子颜色 |
// | `legalHint` | 当前方可落子位置的提示点颜色 |
// | `lastMoveHighlight` | 最近一步落子高亮 |
//
// ### 布局尺寸（reversi_page.dart 专属）
// | 常量 | 用途 |
// |------|------|
// | `boardPadding` / `cellSpacing` / `boardRadius` | 棋盘内边距/格间距/圆角 |
// | `pieceRadiusFactor` | 棋子半径相对格子的比例 |
//
// ### 动画（reversi_page.dart 专属）
// | 常量 | 用途 |
// |------|------|
// | `flipDurationMs` | 棋子翻转动画时长 |
// | `placeDurationMs` | 落子动画时长 |

import 'package:flutter/material.dart';

class ReversiConstants {
  // ==================== 棋盘规则 ====================

  /// 棋盘边长（标准 Othello 为 8x8）
  static const int boardSize = 8;

  /// 一次悔棋撤销的半回合数
  /// 翻转棋两人轮流，悔棋需撤 2 步（对手那步 + 自己上一手）才能回到自己的上一个决策点
  /// 撤 1 步只会让对手重下，对当前方无意义
  static const int undoSteps = 2;

  // ==================== 配色 ====================

  /// 棋盘底色（经典 Othello 绿）
  static const Color boardBackground = Color(0xFF1E7A4E);

  /// 格线颜色
  static const Color cellLine = Color(0xFF145A36);

  /// 黑棋颜色
  static const Color blackPiece = Color(0xFF1A1A1A);

  /// 白棋颜色
  static const Color whitePiece = Color(0xFFFAFAFA);

  /// 当前方可落子位置的提示点颜色
  static const Color legalHint = Color(0x55FFFFFF);

  /// 最近一步落子高亮
  static const Color lastMoveHighlight = Color(0x66FFD54F);

  // ==================== 布局尺寸 ====================

  /// 棋盘内边距
  static const double boardPadding = 8.0;

  /// 格子间距
  static const double cellSpacing = 2.0;

  /// 棋盘外圆角
  static const double boardRadius = 10.0;

  /// 棋子半径相对格子短边的比例
  static const double pieceRadiusFactor = 0.42;

  /// 合法步提示点半径相对格子的比例
  static const double legalDotFactor = 0.18;

  // ==================== 动画 ====================

  /// 棋子翻转动画时长 (ms)
  static const int flipDurationMs = 280;

  /// 落子动画时长 (ms)
  static const int placeDurationMs = 160;

  /// 状态提示淡入淡出 (ms)
  static const int statusFadeMs = 200;
}
