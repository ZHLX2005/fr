// lib/core/surround_game/lan/widgets/touch_controller_factory.dart
//
// LAN 模式触摸控制器工厂 — Host 版产出带 y 镜像的 TouchController；
// Client 版用共享基类。

import 'package:flutter/material.dart';

import '../../mode_factory.dart';
import '../../widgets/touch_controller.dart';

/// LAN Host 触摸控制器 — 触摸 y 坐标镜像
///
/// 在 handleTouchBegan/Moved/Ended 中将屏幕 y 坐标按 [boardSize] 镜像，
/// 使得用户在翻转后的棋盘上点"视觉下方"时，
/// TouchController 内部的 cellId 映射获得正确的 engine 坐标
/// （对应 top player，因为 host 端 currentPlayerIsTop 恒为 true）。
class LanHostTouchController extends TouchController {
  final double boardSize;

  LanHostTouchController({required this.boardSize});

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
      _mirror(localPosition),
      cellSize,
      distance,
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
      _mirror(localPosition),
      cellSize,
      distance,
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
      _mirror(localPosition),
      cellSize,
      distance,
      isTopTurn: isTopTurn,
      validMoves: validMoves,
      validateWall: validateWall,
    );
  }
}

/// LAN Host 工厂
class LanHostTouchControllerFactory implements TouchControllerFactory {
  final double boardSize;

  const LanHostTouchControllerFactory({required this.boardSize});

  @override
  TouchController create() => LanHostTouchController(boardSize: boardSize);
}

/// LAN Client 工厂 — 使用共享基类（不镜像）
class LanClientTouchControllerFactory implements TouchControllerFactory {
  const LanClientTouchControllerFactory();

  @override
  TouchController create() => TouchController();
}
