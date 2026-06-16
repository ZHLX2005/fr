// lib/core/surround_game/lan/widgets/lan_board_stack.dart
//
// LAN 专用棋盘组合组件 — 封装翻转逻辑。
//
// 与单机 [LocalGamePage] 的棋盘 Stack 区别：
//   1. [flipY] 控制是否对绘制子树做 y 翻转（host=true / client=false）
//   2. [isMyTurn] 控制触摸层是否响应（非本方回合不响应）
//   3. 不包含 PlayerPanel（Page 在底部单独放自己的 PlayerPanel）
//
// 触摸坐标镜像由 [TouchController] 子类负责（LanHostTouchController），
// 所以本组件内部回调不做坐标转换，保持简单。

import 'package:flutter/material.dart';

import '../../board_theme.dart';
import '../../models/game_state.dart';
import '../../surround_game_constants.dart';
import '../../widgets/chess_board.dart';
import '../../widgets/chess_player.dart';
import '../../widgets/chess_wall.dart';
import '../../widgets/confirm_actions.dart';
import '../../widgets/player_prompt.dart';
import '../../widgets/touch_controller.dart';
import '../../widgets/touch_view.dart';
import '../../widgets/wall_prompt.dart';

/// LAN 棋盘组合组件
///
/// 翻转：[flipY] 为 true 时（host），用 [Transform.flip] 翻转绘制子树，
/// TouchView 和 ConfirmActions 在 Transform **外部**（按钮可见性由
/// ConfirmActions 内部基于 cellId/wallXY 的几何计算决定，
/// 翻转后其视觉位置会随翻转自动正确）。
///
/// 注意：因为 ConfirmActions 放在 Transform 外部，它内部用 engine
/// 坐标（cellId/wallXY）算 [Positioned] 位置。翻转后 engine 坐标
/// 不变，但视觉上 host 看到 cellId 对应的是翻转后的格子位置 ——
/// 不正确。所以本组件选择把 ConfirmActions 也放进 Transform 内部
/// （见 [_buildDrawingLayer]），让它跟随翻转，视觉位置正确。
/// Icon 的视觉倒转（host 恒 isTopTurn=true，按钮 Icon 不再旋转）
/// 可接受。
class LanBoardStack extends StatelessWidget {
  final GameState gameState;
  final TouchController touchController;
  final BoardThemeData theme;
  final double cellSize;

  /// host=true / client=false
  final bool flipY;

  /// 是否轮到自己（控制触摸层是否响应）
  final bool isMyTurn;

  /// 触摸事件后通知 Page 重建
  final VoidCallback onChanged;

  /// 确认走棋 — 由 Page 注入（负责 dispatch 给 ViewModel + reset controller）
  final VoidCallback onConfirm;

  /// 取消（重置 controller） — 由 Page 注入，便于保持 Page 一致性
  final VoidCallback onCancel;

  /// 墙合法性校验回调
  final bool Function(GameState gs, int wx, int wy, WallOrientation o)
      validateWall;

  const LanBoardStack({
    super.key,
    required this.gameState,
    required this.touchController,
    required this.theme,
    required this.cellSize,
    required this.flipY,
    required this.isMyTurn,
    required this.onChanged,
    required this.onConfirm,
    required this.onCancel,
    required this.validateWall,
  });

  @override
  Widget build(BuildContext context) {
    final boardSize = cellSize * 11;
    final distance = cellSize * 1.25;

    return SizedBox(
      width: boardSize,
      height: boardSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 翻转的绘制子树（包含 ConfirmActions，跟随翻转）
          if (flipY)
            Transform.flip(
              flipY: true,
              child: _buildDrawingLayer(boardSize, distance),
            )
          else
            _buildDrawingLayer(boardSize, distance),

          // 不翻转的触摸层 — 仅在本方回合时挂载
          if (isMyTurn)
            TouchView(
              cellSize: cellSize,
              distance: distance,
              onPointerDown: (pos, cs, dist) =>
                  _onPointerDown(pos, cs, dist),
              onPointerMove: (pos, cs, dist) =>
                  _onPointerMove(pos, cs, dist),
              onPointerUp: (pos, cs, dist) =>
                  _onPointerUp(pos, cs, dist),
              onPointerCancel: _onPointerCancel,
            ),
        ],
      ),
    );
  }

  // ═══════════════════ 绘制子树（翻转层） ═══════════════════

  Widget _buildDrawingLayer(double boardSize, double distance) {
    final gs = gameState;
    final toc = touchController;
    final pendingCellId = toc.pendingTargetCellId;
    final topId = pendingCellId != null && gs.currentPlayerIsTop
        ? pendingCellId
        : gs.topPlayerId;
    final bottomId = pendingCellId != null && !gs.currentPlayerIsTop
        ? pendingCellId
        : gs.bottomPlayerId;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ChessBoard(cellSize: cellSize, theme: theme),
        ChessWall(
          history: gs.history,
          cellSize: cellSize,
          theme: theme,
        ),
        PlayerPrompt(
          validMoves: gs.validMoves,
          cellSize: cellSize,
          theme: theme,
          visible: toc.targetCellId != null,
        ),
        ChessPlayer(
          cellId: topId,
          cellSize: cellSize,
          color: theme.piecePlayerA,
        ),
        ChessPlayer(
          cellId: bottomId,
          cellSize: cellSize,
          color: theme.piecePlayerB,
        ),
        if (pendingCellId != null)
          _PendingHighlight(
            cellId: pendingCellId,
            cellSize: cellSize,
            theme: theme,
          ),
        WallPrompt(
          wallData: toc.previewWall ?? toc.pendingWall,
          cellSize: cellSize,
          theme: theme,
          isValid: toc.wallPreviewValid,
          visible: toc.previewWall != null || toc.pendingWall != null,
        ),
        if (toc.dragOffset != null && toc.targetCellId != null)
          _buildFloatingPiece(
            toc.dragOffset!,
            gs.currentPlayerIsTop,
            cellSize,
            theme,
          ),
        // ConfirmActions 放进翻转层 — 跟随翻转，视觉位置正确
        // Host 端：外层已 flipY，内层图标需要再 flipY 抵消（双重翻转=正常）
        // Client 端：不翻转，需要根据 isTopTurn 决定是否翻转
        ConfirmActions(
          phase: toc.phase,
          pendingTargetCellId: toc.pendingTargetCellId,
          pendingWall: toc.pendingWall,
          isTopTurn: flipY ? true : gs.currentPlayerIsTop,
          cellSize: cellSize,
          boardSize: boardSize,
          theme: theme,
          onConfirm: () => _onConfirm(),
          onCancel: _onCancel,
          onRotate: _onRotate,
        ),
      ],
    );
  }

  // ═══════════════════ 触摸事件转发 ═══════════════════

  void _onPointerDown(Offset pos, double cellSize, double distance) {
    final gs = gameState;
    if (!isMyTurn) return;
    final currentId = gs.currentPlayerIsTop
        ? gs.topPlayerId
        : gs.bottomPlayerId;
    final wallsPlaced = gs.currentPlayerIsTop
        ? gs.topWallsPlaced
        : gs.bottomWallsPlaced;
    final remainingWalls =
        SurroundGameConstants.wallCountPerPlayer - wallsPlaced;

    touchController.handleTouchBegan(
      pos,
      cellSize,
      distance,
      isRunning: gs.status == GameStatus.running,
      currentPlayerId: currentId,
      canPlaceWall: remainingWalls > 0,
      validateWall: (wx, wy, o) => validateWall(gs, wx, wy, o),
    );
    onChanged();
  }

  void _onPointerMove(Offset pos, double cellSize, double distance) {
    final gs = gameState;
    if (!isMyTurn) return;
    touchController.handleTouchMoved(
      pos,
      cellSize,
      distance,
      validateWall: (wx, wy, o) => validateWall(gs, wx, wy, o),
    );
    onChanged();
  }

  void _onPointerUp(Offset pos, double cellSize, double distance) {
    final gs = gameState;
    if (!isMyTurn) return;
    touchController.handleTouchEnded(
      pos,
      cellSize,
      distance,
      isTopTurn: gs.currentPlayerIsTop,
      validMoves: gs.validMoves,
      validateWall: (wx, wy, o) => validateWall(gs, wx, wy, o),
    );
    onChanged();
  }

  void _onPointerCancel() {
    if (!isMyTurn) return;
    touchController.handleTouchCancelled();
    onChanged();
  }

  // ═══════════════════ ConfirmActions 回调（委托给 Page 注入的回调） ═══════════════════

  void _onConfirm() {
    onConfirm();
  }

  void _onCancel() {
    onCancel();
  }

  void _onRotate() {
    final gs = gameState;
    touchController.rotatePendingWall(
      validateWall: (wx, wy, o) => validateWall(gs, wx, wy, o),
    );
    onChanged();
  }

  // ═══════════════════ 拖动棋子（同 local/client page） ═══════════════════

  Widget _buildFloatingPiece(
    Offset offset, bool isTopTurn, double cellSize, BoardThemeData theme,
  ) {
    final color = isTopTurn ? theme.piecePlayerA : theme.piecePlayerB;
    final pieceSize = cellSize * 0.7;
    final dx = offset.dx - pieceSize / 2;
    final dy = offset.dy - pieceSize / 2;

    return Positioned(
      left: dx,
      top: dy,
      child: Container(
        width: pieceSize,
        height: pieceSize,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.75),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }
}

/// 待确认高亮（同 host/client page 内的私有实现，本组件内复用）
class _PendingHighlight extends StatelessWidget {
  final int cellId;
  final double cellSize;
  final BoardThemeData theme;

  const _PendingHighlight({
    required this.cellId,
    required this.cellSize,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final distance = cellSize * 1.25;
    final x = (cellId % 9).toDouble();
    final y = (cellId ~/ 9).toDouble();
    final left = x * distance + 1;
    final top = y * distance + 1;
    final sz = cellSize - 2;

    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: sz,
        height: sz,
        decoration: BoxDecoration(
          color: theme.validMoveRing.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: theme.validMoveRing.withValues(alpha: 0.7),
            width: 2,
          ),
        ),
      ),
    );
  }
}
