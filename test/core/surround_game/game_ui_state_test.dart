import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/game_ui_state.dart';

/// Swift faithful 触摸坐标：
///   走棋落点: tx = ((dx + cellSize*0.125) / distance).floor()
///   放墙坐标: wx = (dx / distance - 0.5).floor()
Offset touchAtCell(int cx, int cy, double cs, double dist) {
  // 触摸 cell(cx,cy) 的中心：cell 起始 = cx*dist + cs*0.1，中心再 + cs*0.4
  // 简化：中心 ≈ cx*dist + cs*0.5
  return Offset(cx * dist + cs * 0.5, cy * dist + cs * 0.5);
}

void main() {
  const cs = 1.0;
  const dist = 1.0;

  group('GameController', () {
    late GameController controller;

    setUp(() {
      controller = GameController();
    });

    test('初始状态', () {
      final ui = controller.state;
      expect(ui.mode, GameMode.move);
      expect(ui.phase, TouchPhase.idle);
      expect(ui.remainingWalls, greaterThan(0));
    });

    test('toggleMode 切换', () {
      controller.toggleMode();
      expect(controller.state.mode, GameMode.placeWall);
      controller.toggleMode();
      expect(controller.state.mode, GameMode.move);
    });

    test('走棋模式 TouchBegan → beganMove', () {
      controller.handleTouchBegan(touchAtCell(4, 0, cs, dist), cs, dist);
      expect(controller.state.phase, TouchPhase.beganMove);
      expect(controller.state.targetCellId, 4);
    });

    test('放墙模式 TouchBegan → beganWall', () {
      controller.toggleMode();
      // 触摸 cell(0,0) 中心：壁坐标 = (0.5 - 0.5).floor() = 0
      controller.handleTouchBegan(touchAtCell(0, 0, cs, dist), cs, dist);
      expect(controller.state.phase, TouchPhase.beganWall);
      expect(controller.state.previewWall, isNotNull);
      expect(controller.state.previewWall!.x, 0);
      expect(controller.state.previewWall!.y, 0);
    });

    test('走棋 TouchMoved → dragging', () {
      controller.handleTouchBegan(touchAtCell(4, 0, cs, dist), cs, dist);
      controller.handleTouchMoved(touchAtCell(4, 3, cs, dist), cs, dist);
      expect(controller.state.phase, TouchPhase.dragging);
    });

    test('放墙 TouchMoved → dragging + previewWall', () {
      controller.toggleMode();
      controller.handleTouchBegan(touchAtCell(0, 0, cs, dist), cs, dist);
      // 移到 cell(3,3) → 壁坐标 (3.5-0.5).floor=3
      controller.handleTouchMoved(touchAtCell(3, 3, cs, dist), cs, dist);
      expect(controller.state.phase, TouchPhase.dragging);
      expect(controller.state.previewWall, isNotNull);
      expect(controller.state.previewWall!.x, 3);
      expect(controller.state.previewWall!.y, 3);
    });

    test('走棋合法移动→换手', () {
      controller.handleTouchBegan(touchAtCell(4, 0, cs, dist), cs, dist);
      // 拖到 cell(4,1)
      controller.handleTouchEnded(touchAtCell(4, 1, cs, dist), cs, dist);
      final ui = controller.state;
      expect(ui.phase, TouchPhase.idle);
      expect(ui.gameState.currentPlayerIsTop, isFalse); // 换手
      expect(ui.gameState.topPlayerId, 13); // cell(4,1)
    });

    test('走棋非法移动→不换手', () {
      controller.handleTouchBegan(touchAtCell(4, 0, cs, dist), cs, dist);
      // 拖到 cell(0,0) — 非法（不是 top 的 validMoves）
      controller.handleTouchEnded(touchAtCell(0, 0, cs, dist), cs, dist);
      expect(controller.state.gameState.currentPlayerIsTop, isTrue);
      expect(controller.state.gameState.topPlayerId, 4);
    });

    test('合法放墙→换手', () {
      controller.toggleMode();
      // 墙(3,3) horizontal — 合法
      controller.handleTouchBegan(touchAtCell(3, 3, cs, dist), cs, dist);
      controller.handleTouchMoved(touchAtCell(3, 3, cs, dist), cs, dist);
      controller.handleTouchEnded(touchAtCell(3, 3, cs, dist), cs, dist);
      expect(controller.state.gameState.currentPlayerIsTop, isFalse);
      expect(controller.state.gameState.topWallsPlaced, 1);
    });

    test('重叠放墙→不换手', () {
      controller.toggleMode();
      controller.handleTouchBegan(touchAtCell(3, 3, cs, dist), cs, dist);
      controller.handleTouchMoved(touchAtCell(3, 3, cs, dist), cs, dist);
      controller.handleTouchEnded(touchAtCell(3, 3, cs, dist), cs, dist);
      expect(controller.state.gameState.currentPlayerIsTop, isFalse);

      controller.toggleMode();
      controller.handleTouchBegan(touchAtCell(3, 3, cs, dist), cs, dist);
      controller.handleTouchMoved(touchAtCell(3, 3, cs, dist), cs, dist);
      controller.handleTouchEnded(touchAtCell(3, 3, cs, dist), cs, dist);
      expect(controller.state.gameState.currentPlayerIsTop, isFalse);
      expect(controller.state.gameState.bottomWallsPlaced, 0);
    });

    test('handleTouchCancelled', () {
      controller.handleTouchBegan(touchAtCell(4, 0, cs, dist), cs, dist);
      controller.handleTouchCancelled();
      expect(controller.state.phase, TouchPhase.idle);
    });

    test('wallColor 有效→绿', () {
      controller.toggleMode();
      // 触碰空白区域并移动到(5,5)——这是一个合法墙壁位置
      controller.handleTouchBegan(touchAtCell(5, 5, cs, dist), cs, dist);
      expect(controller.state.wallColor, const Color(0xFF7CFFE5));
    });

    test('wallColor 重叠→红', () {
      controller.toggleMode();
      controller.handleTouchBegan(touchAtCell(3, 3, cs, dist), cs, dist);
      controller.handleTouchMoved(touchAtCell(3, 3, cs, dist), cs, dist);
      controller.handleTouchEnded(touchAtCell(3, 3, cs, dist), cs, dist);

      controller.toggleMode();
      controller.handleTouchBegan(touchAtCell(3, 3, cs, dist), cs, dist);
      controller.handleTouchMoved(touchAtCell(3, 3, cs, dist), cs, dist);
      expect(controller.state.wallColor, const Color(0xFFFF7CB8));
    });

    test('墙壁坐标 clamp [0,7]', () {
      controller.toggleMode();
      // 触摸极远处
      controller.handleTouchBegan(touchAtCell(10, 10, cs, dist), cs, dist);
      // wall X = (10.5 - 0.5).floor() = 10 → clamp to 7
      expect(controller.state.previewWall!.x, 7);
      expect(controller.state.previewWall!.y, 7);

      controller.handleTouchCancelled();
      // cancel 重置 mode 为 move，需再切回放墙
      controller.toggleMode();
      // 触摸负坐标
      controller.handleTouchBegan(const Offset(-100, -50), cs, dist);
      expect(controller.state.previewWall!.x, 0);
      expect(controller.state.previewWall!.y, 0);
    });
  });
}
