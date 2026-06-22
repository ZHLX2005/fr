// lib/core/jungle_chess/widgets/jungle_host_touch_controller.dart
//
// LAN 模式触摸控制器工厂 — Host 版产出带 y 镜像的 JungleTouchController；
// Client 版用共享基类。
//
// JungleChess 棋盘对称(蓝方在底、红方在顶),Y 镜像实际不影响坐标,
// 但保留镜像实现以保持模板一致性(后续扩展游戏直接复用同一套)。

import 'package:flutter/material.dart';
import 'jungle_touch_controller.dart';
import '../models/game_state.dart';

/// LAN Host 触摸控制器 — 触摸 y 坐标镜像
///
/// 在 onDragStart/Update/End 中将屏幕 y 坐标按 [boardSize] 镜像，
/// 使得用户在翻转后的棋盘上点"视觉下方"时，
/// JungleTouchController 内部的 cellId 映射获得正确的 engine 坐标。
class JungleHostTouchController extends JungleTouchController {
  final double boardSize;

  JungleHostTouchController({required this.boardSize});

  Offset _mirror(Offset p) => Offset(p.dx, boardSize - p.dy);

  // onCellTap 不需要镜像（点击基于 cellIndex，与 Y 坐标无关）
  @override
  void onCellTap(GameState state, int index) {
    super.onCellTap(state, index);
  }

  @override
  void onDragStart(GameState state, int index, Offset fingerPos) {
    super.onDragStart(state, index, _mirror(fingerPos));
  }

  @override
  void onDragUpdate(GameState state, Offset fingerPos) {
    super.onDragUpdate(state, _mirror(fingerPos));
  }

  @override
  void onDragEnd(GameState state, Offset fingerPos) {
    super.onDragEnd(state, _mirror(fingerPos));
  }
}

/// LAN Host 工厂
class JungleHostTouchControllerFactory {
  final double boardSize;

  const JungleHostTouchControllerFactory({required this.boardSize});

  JungleHostTouchController create() =>
      JungleHostTouchController(boardSize: boardSize);
}

/// LAN Client 工厂 — 使用共享基类（不镜像）
class JungleClientTouchControllerFactory {
  const JungleClientTouchControllerFactory();

  JungleTouchController create() => JungleTouchController();
}
