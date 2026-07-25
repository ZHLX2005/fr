// lib/lab/demos/surround_game_lua/touch_controller.dart
// 互联网双人对战触摸控制器：host 镜像（与 LAN host 一致）

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/touch_controller.dart';

/// Host 端触摸控制器 — 把触摸 y 坐标沿 boardSize 中线镜像
///
/// 原理：服务端 `currentPlayerIsTop` 是 host（topPlayer = y=0），
/// 但 host 在自己设备上看到的是 y 翻转后的棋盘（自己棋子在视觉下方）。
/// 所以触摸坐标必须镜像后，才能跟 TouchController 内的 cellId 计算对齐。
class SgHostTouchController extends TouchController {
  SgHostTouchController({required this.boardSize});
  final double boardSize;

  Offset _mirror(Offset p) => Offset(p.dx, boardSize - p.dy);

  @override
  void handleTouchBegan(
    Offset localPosition,
    double cellSize,
    double distance, {
    required bool isRunning,
    required int currentPlayerId,
    required bool canPlaceWall,
    required WallValidator validateWall,
  }) {
    super.handleTouchBegan(
      _mirror(localPosition), cellSize, distance,
      isRunning: isRunning,
      currentPlayerId: currentPlayerId,
      canPlaceWall: canPlaceWall,
      validateWall: validateWall,
    );
  }

  @override
  void handleTouchMoved(
    Offset localPosition,
    double cellSize,
    double distance, {
    required WallValidator validateWall,
  }) {
    super.handleTouchMoved(
      _mirror(localPosition), cellSize, distance,
      validateWall: validateWall,
    );
  }

  @override
  void handleTouchEnded(
    Offset localPosition,
    double cellSize,
    double distance, {
    required bool isTopTurn,
    required Set<int> validMoves,
    required WallValidator validateWall,
  }) {
    super.handleTouchEnded(
      _mirror(localPosition), cellSize, distance,
      isTopTurn: isTopTurn,
      validMoves: validMoves,
      validateWall: validateWall,
    );
  }
}