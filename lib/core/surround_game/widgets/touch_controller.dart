// lib/core/surround_game/widgets/touch_controller.dart
//
// 纯触摸状态机 — 不依赖 GameUiState / GameController / GameState。
//
// 职责：
//   - 管理触摸阶段（idle / beganMove / beganWall / dragging / confirming）
//   - 管理模式（move / placeWall）
//   - 提供触摸事件处理方法（began / moved / ended / cancelled）
//   - 管理墙预览状态（坐标、方向、合法性）
//   - 管理待确认操作（pendingTargetCellId / pendingWall）
//
// 与引擎的解耦：
//   - 墙预览的合法性校验通过回调 [WallValidator] 注入。
//   - 本身不导入 GameState、GameController、GameUiState。

import 'package:flutter/material.dart';
import '../surround_game_constants.dart';

/// 操作模式 — 显式切换，不自动推断
enum GameMode { move, placeWall }

/// 交互阶段
enum TouchPhase { idle, beganMove, beganWall, dragging, confirming }

/// 墙预览合法性校验回调签名。
///
/// TouchController 不具备 GameState，不能自行校验墙放置合法性。
/// 外部传入此回调，在触摸方法中调用。
typedef WallValidator = bool Function(
  int wx, int wy, WallOrientation orientation,
);

/// 纯触摸状态机
///
/// 管理交互阶段转换和墙预览状态，不接触游戏数据模型。
/// 所有触摸事件处理方法的签名与 GameController 中的同名方法一致。
class TouchController {
  TouchPhase phase = TouchPhase.idle;
  GameMode mode = GameMode.move;
  int? targetCellId;
  ({int x, int y, WallOrientation o})? previewWall;
  bool wallPreviewValid = true;
  Offset? dragOffset;
  int? pendingTargetCellId;
  ({int x, int y, WallOrientation o})? pendingWall;

  /// 重置所有状态到初始值
  void reset() {
    phase = TouchPhase.idle;
    mode = GameMode.move;
    targetCellId = null;
    previewWall = null;
    wallPreviewValid = true;
    dragOffset = null;
    pendingTargetCellId = null;
    pendingWall = null;
  }

  /// 切换 mode（move ↔ placeWall），同时重置触摸相关字段。
  void toggleMode() {
    mode = mode == GameMode.move ? GameMode.placeWall : GameMode.move;
    phase = TouchPhase.idle;
    targetCellId = null;
    previewWall = null;
    wallPreviewValid = true;
    dragOffset = null;
    pendingTargetCellId = null;
    pendingWall = null;
  }

  /// TouchBegan — 开始触摸
  ///
  /// [isRunning]：游戏是否进行中（status == running）
  /// [currentPlayerId]：当前玩家棋子 cellId（仅在 move 模式使用）
  /// [canPlaceWall]：当前玩家是否还有木板可放
  /// [validateWall]：墙预览合法性校验回调
  ///
  /// Swift TouchView touchType=false → delegate?.touchMoveChess
  /// Swift TouchView touchType=true  → delegate?.touchAddWood
  void handleTouchBegan(
    Offset localPosition,
    double cellSize,
    double distance, {
    required bool isRunning,
    required int currentPlayerId,
    required bool canPlaceWall,
    required WallValidator validateWall,
  }) {
    if (!isRunning) return;

    if (mode == GameMode.move) {
      phase = TouchPhase.beganMove;
      targetCellId = currentPlayerId;
      previewWall = null;
      wallPreviewValid = true;
      dragOffset = null;
    } else {
      if (!canPlaceWall) {
        // 无木板 → 自动切回走棋模式
        mode = GameMode.move;
        phase = TouchPhase.beganMove;
        targetCellId = currentPlayerId;
        previewWall = null;
        wallPreviewValid = true;
        dragOffset = null;
        return;
      }
      // Swift wallDataForTouch: Int((loc + cellSize*0.625) / distance - 0.5)
      // 0.625 → +0.5格偏移补偿了 -0.5，效果≈ round()到最近缝隙。
      // 无偏移时用 round() 让触摸格子中心→最近缝隙。
      final wx = ((localPosition.dx / distance) - 0.5).round().clamp(0, 7);
      final wy = ((localPosition.dy / distance) - 0.5).round().clamp(0, 7);
      phase = TouchPhase.beganWall;
      targetCellId = null;
      dragOffset = null;
      _updateWallPreview(wx, wy, validateWall);
    }
  }

  /// TouchMoved — 触摸移动
  void handleTouchMoved(
    Offset localPosition,
    double cellSize,
    double distance, {
    required WallValidator validateWall,
  }) {
    if (phase == TouchPhase.idle) return;

    if (mode == GameMode.move) {
      phase = TouchPhase.dragging;
      dragOffset = localPosition;
    } else {
      phase = TouchPhase.dragging;
      final wx = ((localPosition.dx / distance) - 0.5).floor().clamp(0, 7);
      final wy = ((localPosition.dy / distance) - 0.5).floor().clamp(0, 7);
      _updateWallPreview(wx, wy, validateWall);
    }
  }

  /// TouchEnded — 触摸结束，保存待确认操作
  ///
  /// [isTopTurn]：当前是否为上方玩家回合
  /// [validMoves]：当前玩家合法落子集合（用于 move 模式验证）
  /// [validateWall]：墙预览合法性校验回调
  void handleTouchEnded(
    Offset localPosition,
    double cellSize,
    double distance, {
    required bool isTopTurn,
    required Set<int> validMoves,
    required WallValidator validateWall,
  }) {
    if (mode == GameMode.move) {
      final tx = ((localPosition.dx + cellSize * 0.125) / distance).floor().clamp(0, 8);
      final ty = ((localPosition.dy + cellSize * 0.125) / distance).floor().clamp(0, 8);
      final targetId = ty * 9 + tx;

      // 验证合法性
      if (!validMoves.contains(targetId)) {
        reset();
        return;
      }

      phase = TouchPhase.confirming;
      pendingTargetCellId = targetId;
      targetCellId = null;
      dragOffset = null;
    } else {
      final w = previewWall;
      if (w == null) {
        reset();
        return;
      }

      phase = TouchPhase.confirming;
      pendingWall = w;
      previewWall = null;
      wallPreviewValid = true;
      dragOffset = null;
    }
  }

  /// 取消 — 放弃待定操作
  void cancelAction() {
    reset();
  }

  /// 旋转待定墙的方向
  ///
  /// [validateWall]：墙预览合法性校验回调
  void rotatePendingWall({required WallValidator validateWall}) {
    if (phase != TouchPhase.confirming || pendingWall == null) return;

    final w = pendingWall!;
    final newOrientation = w.o == WallOrientation.horizontal
        ? WallOrientation.vertical
        : WallOrientation.horizontal;

    final valid = validateWall(w.x, w.y, newOrientation);

    pendingWall = (x: w.x, y: w.y, o: newOrientation);
    wallPreviewValid = valid;
  }

  /// TouchCancelled — 触摸取消
  void handleTouchCancelled() {
    reset();
  }

  void _updateWallPreview(int wx, int wy, WallValidator validateWall) {
    final old = previewWall;
    if (old != null && old.x == wx && old.y == wy) return;

    WallOrientation orientation;
    if (old != null) {
      orientation = (wx - old.x).abs() > (wy - old.y).abs()
          ? WallOrientation.horizontal
          : WallOrientation.vertical;
    } else {
      orientation = WallOrientation.horizontal;
    }

    final valid = validateWall(wx, wy, orientation);

    previewWall = (x: wx, y: wy, o: orientation);
    wallPreviewValid = valid;
  }
}
