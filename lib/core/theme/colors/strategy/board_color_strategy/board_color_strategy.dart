// Layer 3: 棋局 ColorStrategy 契约。
//
// 与通用 ColorStrategy（context.colors，6 角色）平行，专为棋盘 UI 设计：
//   棋盘底 / 网格 / 轴 / 玩家1 / 玩家2 / 提示 / 胜负高亮 / 最后落子 / 错误 / 中性 / scheme
//
// 通用 ColorStrategy 不够用：
//   · scheme.surface 同时是页面卡片底，又是棋盘底，角色重叠
//   · scheme.primary 是主题主色，但棋盘要"玩家1=黑/深、玩家2=白/浅"的固定关系
//   · 胜负高亮要跳出主题（用互补色 tertiary），通用没有
//
// 各棋牌游戏保留自己 constants 里的"语义棋子色"（tetris 红蓝绿黄、
// snake 蛇身/食物、2048 数字等），那是国际通用识别色，不归主题管。

import 'package:flutter/material.dart';

@immutable
abstract class BoardColorStrategy {
  const BoardColorStrategy();

  /// 棋盘底色（最深档容器色，让棋盘"沉"在页面里）
  Color get background;

  /// 网格线（细线，浅描边）
  Color get gridLine;

  /// 坐标轴 / 行列标签文字
  Color get axisLabel;

  /// 玩家 1 棋子（深色棋子侧）
  Color get player1Stone;

  /// 玩家 2 棋子（浅色棋子侧，与 player1Stone 反色）
  Color get player2Stone;

  /// 落子预览 / 提示标记
  Color get hint;

  /// 胜负高亮（用互补色，让胜局跳出来）
  Color get winHighlight;

  /// 最后落子位置标记
  Color get lastMove;

  /// 错误 / 非法标记（复用 error 红，保持危险语义）
  Color get errorMark;

  /// 中性元素色（蛇身普通段、装饰等）
  Color get neutral;

  /// 完整 ColorScheme 兜底
  ColorScheme get scheme;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardColorStrategy &&
          runtimeType == other.runtimeType &&
          background == other.background &&
          gridLine == other.gridLine &&
          axisLabel == other.axisLabel &&
          player1Stone == other.player1Stone &&
          player2Stone == other.player2Stone &&
          hint == other.hint &&
          winHighlight == other.winHighlight &&
          lastMove == other.lastMove &&
          errorMark == other.errorMark &&
          neutral == other.neutral;

  @override
  int get hashCode => Object.hash(
        background, gridLine, axisLabel,
        player1Stone, player2Stone, hint,
        winHighlight, lastMove, errorMark, neutral,
      );
}