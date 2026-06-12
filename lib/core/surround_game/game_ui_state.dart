// lib/core/surround_game/game_ui_state.dart
//
// 游戏状态 + 显式模式切换（走棋/放墙），消除自动判断冲突。

import 'package:flutter/material.dart';
import 'engine/game_engine.dart';
import 'models/game_state.dart';
import 'surround_game_constants.dart';

/// 操作模式 — 显式切换，不自动推断
enum GameMode { move, placeWall }

/// 交互阶段
enum TouchPhase { idle, beganMove, beganWall, dragging, confirming }

/// 单一不可变 UI 状态
class GameUiState {
  final GameState gameState;
  final GameMode mode;
  final TouchPhase phase;
  final int? targetCellId;
  final ({int x, int y, WallOrientation o})? previewWall;
  final Color wallColor;
  final Offset? dragOffset;

  // 待确认的走棋/放墙
  final int? pendingTargetCellId;
  final ({int x, int y, WallOrientation o})? pendingWall;

  const GameUiState({
    required this.gameState,
    this.mode = GameMode.move,
    this.phase = TouchPhase.idle,
    this.targetCellId,
    this.previewWall,
    this.wallColor = const Color(0xFF7CFFE5),
    this.dragOffset,
    this.pendingTargetCellId,
    this.pendingWall,
  });

  factory GameUiState.initial() => GameUiState(
        gameState: QuoridorEngine.initialize(),
      );

  bool get isTopTurn => gameState.currentPlayerIsTop;
  bool get canPlaceWall => remainingWalls > 0;

  int get remainingWalls =>
      SurroundGameConstants.wallCountPerPlayer -
      (gameState.currentPlayerIsTop
          ? gameState.topWallsPlaced
          : gameState.bottomWallsPlaced);

  GameUiState copyWith({
    GameState? gameState,
    GameMode? mode,
    TouchPhase? phase,
    int? targetCellId,
    ({int x, int y, WallOrientation o})? previewWall,
    Color? wallColor,
    Offset? dragOffset,
    int? pendingTargetCellId,
    ({int x, int y, WallOrientation o})? pendingWall,
    bool clearTarget = false,
    bool clearPreview = false,
    bool clearDrag = false,
    bool clearPending = false,
  }) =>
      GameUiState(
        gameState: gameState ?? this.gameState,
        mode: mode ?? this.mode,
        phase: phase ?? this.phase,
        targetCellId: clearTarget ? null : (targetCellId ?? this.targetCellId),
        previewWall: clearPreview ? null : (previewWall ?? this.previewWall),
        wallColor: wallColor ?? this.wallColor,
        dragOffset: clearDrag ? null : (dragOffset ?? this.dragOffset),
        pendingTargetCellId: clearPending
            ? null
            : (pendingTargetCellId ?? this.pendingTargetCellId),
        pendingWall: clearPending ? null : (pendingWall ?? this.pendingWall),
      );
}

/// 游戏控制器
///
/// 坐标转换严格对齐 Swift FrameCalculator.swift：
/// - 走棋：playerDataFromTouch → Int((x + cellSize*0.125) / distance)
/// - 放墙：wallDataForTouch  → Int(x / distance - 0.5)
/// - 渲染：ChessWall.swift   → left = x*distance + cellSize-2
class GameController {
  final ValueNotifier<GameUiState> stateNotifier;

  GameController() : stateNotifier = ValueNotifier(GameUiState.initial());

  GameUiState get state => stateNotifier.value;

  void resetGame() {
    stateNotifier.value = GameUiState.initial();
  }

  bool undoLastMove() => false;

  void toggleMode() {
    final s = state;
    if (!s.canPlaceWall) return;
    stateNotifier.value = s.copyWith(
      mode: s.mode == GameMode.move ? GameMode.placeWall : GameMode.move,
      clearPreview: true,
      clearTarget: true,
      clearDrag: true,
      phase: TouchPhase.idle,
    );
  }

  /// TouchBegan
  void handleTouchBegan(Offset localPosition, double cellSize, double distance) {
    final s = state;
    // 终局后不允许任何触摸操作
    if (s.gameState.status != GameStatus.running) return;

    final currentId = s.isTopTurn
        ? s.gameState.topPlayerId
        : s.gameState.bottomPlayerId;

    if (s.mode == GameMode.move) {
      stateNotifier.value = s.copyWith(
        phase: TouchPhase.beganMove,
        targetCellId: currentId,
        clearPreview: true,
        clearDrag: true,
      );
    } else {
      if (!s.canPlaceWall) {
        stateNotifier.value = s.copyWith(
          mode: GameMode.move,
          phase: TouchPhase.beganMove,
          targetCellId: currentId,
          clearPreview: true,
          clearDrag: true,
        );
        return;
      }
      // Swift TouchView: touchType=true → delegate?.touchAddWood
      // Swift wallDataForTouch: Int((loc + cellSize*0.625) / distance - 0.5)
      // 0.625 → +0.5格偏移补偿了 -0.5，效果≈ round()到最近缝隙。
      // 无偏移时用 round() 让触摸格子中心→最近缝隙。
      final wx = ((localPosition.dx / distance) - 0.5).round().clamp(0, 7);
      final wy = ((localPosition.dy / distance) - 0.5).round().clamp(0, 7);
      stateNotifier.value = s.copyWith(
        phase: TouchPhase.beganWall,
        clearTarget: true,
        clearDrag: true,
      );
      _updateWallPreview(wx, wy);
    }
  }

  /// TouchMoved
  void handleTouchMoved(Offset localPosition, double cellSize, double distance) {
    final s = state;
    if (s.phase == TouchPhase.idle) return;

    if (s.mode == GameMode.move) {
      stateNotifier.value = s.copyWith(
        phase: TouchPhase.dragging,
        dragOffset: localPosition,
      );
    } else {
      stateNotifier.value = s.copyWith(phase: TouchPhase.dragging);
      final wx = ((localPosition.dx / distance) - 0.5).floor().clamp(0, 7);
      final wy = ((localPosition.dy / distance) - 0.5).floor().clamp(0, 7);
      _updateWallPreview(wx, wy);
    }
  }

  /// TouchEnded — 先保存待确认，不直接落子/放墙
  void handleTouchEnded(Offset localPosition, double cellSize, double distance) {
    final s = state;

    if (s.mode == GameMode.move) {
      final tx = ((localPosition.dx + cellSize * 0.125) / distance).floor().clamp(0, 8);
      final ty = ((localPosition.dy + cellSize * 0.125) / distance).floor().clamp(0, 8);
      final targetId = ty * 9 + tx;

      // 验证合法性
      if (!s.gameState.validMoves.contains(targetId)) {
        stateNotifier.value = GameUiState(gameState: s.gameState);
        return;
      }

      stateNotifier.value = s.copyWith(
        phase: TouchPhase.confirming,
        pendingTargetCellId: targetId,
        clearTarget: true,
        clearDrag: true,
      );
    } else {
      final w = s.previewWall;
      if (w == null) {
        stateNotifier.value = GameUiState(gameState: s.gameState);
        return;
      }

      stateNotifier.value = s.copyWith(
        phase: TouchPhase.confirming,
        pendingWall: w,
        clearPreview: true,
        clearDrag: true,
      );
    }
  }

  /// 确认 — 执行待定的走棋/放墙
  void confirmAction() {
    final s = state;
    if (s.phase != TouchPhase.confirming) return;

    GameState? result;

    if (s.pendingTargetCellId != null) {
      result = QuoridorEngine.movePiece(s.gameState, s.pendingTargetCellId!);
    } else if (s.pendingWall != null) {
      final w = s.pendingWall!;
      result = QuoridorEngine.placeWall(s.gameState, w.x, w.y, w.o);
    }

    if (result != null) {
      stateNotifier.value = GameUiState(
        gameState: QuoridorEngine.switchTurn(result),
      );
    } else {
      // 不应该发生，但防御性处理
      stateNotifier.value = GameUiState(gameState: s.gameState);
    }
  }

  /// 取消 — 放弃待定操作
  void cancelAction() {
    stateNotifier.value = GameUiState(gameState: state.gameState);
  }

  /// 旋转待定墙的方向
  void rotatePendingWall() {
    final s = state;
    if (s.phase != TouchPhase.confirming || s.pendingWall == null) return;

    final w = s.pendingWall!;
    final newOrientation = w.o == WallOrientation.horizontal
        ? WallOrientation.vertical
        : WallOrientation.horizontal;

    // 重新校验
    final valid = QuoridorEngine.isWallPlacementValid(
      s.gameState.wallGrid, s.gameState.adjacency,
      s.gameState.topPlayerId, s.gameState.bottomPlayerId,
      w.x, w.y, newOrientation,
    );

    stateNotifier.value = s.copyWith(
      pendingWall: (x: w.x, y: w.y, o: newOrientation),
      wallColor: valid
          ? const Color(0xFF7CFFE5)
          : const Color(0xFFFF7CB8),
    );
  }

  void handleTouchCancelled() {
    stateNotifier.value = GameUiState(gameState: state.gameState);
  }

  void _updateWallPreview(int wx, int wy) {
    final s = state;
    final old = s.previewWall;
    if (old != null && old.x == wx && old.y == wy) return;

    // Swift wallDataForTouch horizon = Int((x - cellSize*0.3125) / (cellSize*0.625)) % 2 == 0
    // Approximated: orientation based on delta from previous
    WallOrientation orientation;
    if (old != null) {
      orientation = (wx - old.x).abs() > (wy - old.y).abs()
          ? WallOrientation.horizontal
          : WallOrientation.vertical;
    } else {
      orientation = WallOrientation.horizontal;
    }

    final valid = QuoridorEngine.isWallPlacementValid(
      s.gameState.wallGrid, s.gameState.adjacency,
      s.gameState.topPlayerId, s.gameState.bottomPlayerId,
      wx, wy, orientation,
    );

    stateNotifier.value = s.copyWith(
      previewWall: (x: wx, y: wy, o: orientation),
      wallColor: valid
          ? const Color(0xFF7CFFE5)
          : const Color(0xFFFF7CB8),
    );
  }
}
