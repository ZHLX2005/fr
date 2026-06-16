// lib/core/surround_game/local/local_game_page.dart
//
// 单机热座游戏页面：使用 LocalViewModel + TouchController 替代 GameController。
//
// 整体结构复制自 game_page.dart，但做了以下改造：
//   1. 状态驱动从 GameUiState ValueNotifier 改为 LocalMatchState sealed class。
//   2. 触摸控制从 GameController 拆出独立的 TouchController。
//   3. 组件 API 全部使用新的 props/回调形式（PlayerPanel / ConfirmActions / TouchView）。
import 'package:flutter/material.dart';
import '../board_theme.dart';
import '../game_ui_state.dart';
import '../surround_game_constants.dart';
import '../widgets/chess_board.dart';
import '../widgets/chess_player.dart';
import '../widgets/chess_wall.dart';
import '../widgets/player_prompt.dart';
import '../widgets/wall_prompt.dart';
import '../widgets/touch_view.dart';
import '../widgets/player_panel.dart';
import '../widgets/confirm_actions.dart';
import '../widgets/touch_controller.dart';
import '../engine/game_engine.dart';
import '../models/game_state.dart';
import '../replay/replay_page.dart';
import 'local_view_model.dart';
import 'local_match_state.dart';
import 'local_match_event.dart';

/// 单机热座游戏页面
class LocalGamePage extends StatefulWidget {
  const LocalGamePage({super.key});

  @override
  State<LocalGamePage> createState() => _LocalGamePageState();
}

class _LocalGamePageState extends State<LocalGamePage> {
  final _viewModel = LocalViewModel();
  final _touchController = TouchController();
  bool _touchInitialized = false;

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);

    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: ValueListenableBuilder<LocalMatchState>(
          valueListenable: _viewModel,
          builder: (_, matchState, __) => switch (matchState) {
            LocalIdle() => _buildIdleScreen(theme),
            LocalInGame() => _buildGameScreen(matchState, theme),
            LocalFinished() => _buildGameScreen(
                // 使用已结束的 GameState 渲染最终棋盘
                LocalInGame(matchState.finalState),
                theme,
                overlay: _buildVictoryOverlay(matchState, theme),
              ),
          },
        ),
      ),
    );
  }

  /// 闲置状态 — 开始界面
  Widget _buildIdleScreen(BoardThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sports_esports, size: 64, color: theme.piecePlayerA),
          const SizedBox(height: 16),
          Text(
            '本地热座',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: theme.btnText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '两位玩家轮流使用同一设备',
            style: TextStyle(fontSize: 14, color: theme.btnSub),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () {
              _touchController.reset();
              _viewModel.dispatch(const LocalStartPressed());
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('开始游戏'),
            style: FilledButton.styleFrom(
              backgroundColor: theme.piecePlayerA,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 游戏进行中（或已结束）的棋盘界面
  ///
  /// [overlay] 可选：终局后覆盖在棋盘上的胜利弹层（由 LocalFinished 状态传入）。
  Widget _buildGameScreen(
    LocalInGame inGame,
    BoardThemeData theme, {
    Widget? overlay,
  }) {
    final gs = inGame.gameState;
    final isRunning = gs.status == GameStatus.running;

    return Stack(
      children: [
        Column(
          children: [
            // 上方面板 — 上方玩家
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Center(
                child: _buildPlayerPanel(
                  gs: gs,
                  theme: theme,
                  rotated: true,
                  isTop: true,
                  isTopTurn: gs.currentPlayerIsTop,
                  isRunning: isRunning,
                ),
              ),
            ),

            // 棋盘
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final cellSize = w / 11;
                  final distance = cellSize * 1.25;
                  final boardSize = w;

                  return Center(
                    child: SizedBox(
                      width: boardSize,
                      height: boardSize,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ChessBoard(cellSize: cellSize, theme: theme),

                          // 棋子 + 墙壁 + 提示叠加
                          _buildBoardOverlay(
                            gs: gs,
                            cellSize: cellSize,
                            theme: theme,
                          ),

                          // 触摸捕获层
                          if (isRunning)
                            TouchView(
                              cellSize: cellSize,
                              distance: distance,
                              onPointerDown: (pos, cs, dist) =>
                                  _onPointerDown(pos, cs, dist, gs),
                              onPointerMove: (pos, cs, dist) =>
                                  _onPointerMove(pos, cs, dist, gs),
                              onPointerUp: (pos, cs, dist) =>
                                  _onPointerUp(pos, cs, dist, gs),
                              onPointerCancel: () =>
                                  _onPointerCancel(),
                            ),

                          // 就地确认按钮
                          ConfirmActions(
                            phase: _touchController.phase,
                            pendingTargetCellId:
                                _touchController.pendingTargetCellId,
                            pendingWall: _touchController.pendingWall,
                            isTopTurn: gs.currentPlayerIsTop,
                            cellSize: cellSize,
                            boardSize: boardSize,
                            theme: theme,
                            onConfirm: _onConfirm(gs),
                            onCancel: _onCancel,
                            onRotate: _onRotate(gs),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // 下方面板 — 下方玩家
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 10),
              child: Center(
                child: _buildPlayerPanel(
                  gs: gs,
                  theme: theme,
                  rotated: false,
                  isTop: false,
                  isTopTurn: gs.currentPlayerIsTop,
                  isRunning: isRunning,
                ),
              ),
            ),

            // 底部操作 — 重新开始 / 返回
            Padding(
              padding: const EdgeInsets.only(
                left: 16, top: 6, bottom: 6, right: 16,
              ),
              child: Row(
                children: [
                  _bottomAction(
                    icon: Icons.arrow_back,
                    label: '返回',
                    theme: theme,
                    onTap: () => _showExitConfirm(context, theme),
                  ),
                  const SizedBox(width: 16),
                  _bottomAction(
                    icon: Icons.refresh,
                    label: '重新开始',
                    theme: theme,
                    onTap: () => _showResetConfirm(context, theme),
                  ),
                ],
              ),
            ),
          ],
        ),

        // 胜利弹层
        if (overlay != null) overlay,
      ],
    );
  }

  /// 棋盘叠加层：墙 + 合法步提示 + 棋子 + 高亮 + 墙预览 + 浮动棋子
  Widget _buildBoardOverlay({
    required GameState gs,
    required double cellSize,
    required BoardThemeData theme,
  }) {
    final toc = _touchController;

    // 确认阶段预览的棋子位置
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
        // 确认阶段目标格特殊高亮
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
      ],
    );
  }

  /// 构建单侧玩家操作栏
  Widget _buildPlayerPanel({
    required GameState gs,
    required BoardThemeData theme,
    required bool rotated,
    required bool isTop,
    required bool isTopTurn,
    required bool isRunning,
  }) {
    final toc = _touchController;
    final isCurrentTurn = isTop == gs.currentPlayerIsTop;
    final active = isRunning && isCurrentTurn;

    final playerSteps = gs.history
        .where((m) => !m.isWall && m.isTopPlayer == isTop)
        .length;
    final wallsPlaced =
        isTop ? gs.topWallsPlaced : gs.bottomWallsPlaced;
    final remainingWalls =
        SurroundGameConstants.wallCountPerPlayer - wallsPlaced;

    final canUndo = isRunning &&
        GameController.canRequestUndo(gs, isTopPlayer: isTop);

    return PlayerPanel(
      rotated: rotated,
      active: active,
      isTop: isTop,
      mode: toc.mode,
      phase: toc.phase,
      canPlaceWall: remainingWalls > 0,
      playerSteps: playerSteps,
      remainingWalls: remainingWalls,
      canRequestUndo: canUndo,
      onToggleMode: active ? () => _toggleMode() : null,
      onUndoRequest: canUndo
          ? () => _showUndoRequestConfirm(
                context,
                theme,
                isTopPlayer: isTop,
              )
          : null,
      onConfirm: (toc.phase == TouchPhase.confirming && active)
          ? _onConfirm(gs)
          : null,
      onCancel: (toc.phase == TouchPhase.confirming && active)
          ? _onCancel
          : null,
      onRotate: (toc.phase == TouchPhase.confirming && active)
          ? _onRotate(gs)
          : null,
      pendingWall: toc.pendingWall,
    );
  }

  // ═══════════════════════════ 触摸事件转发 ═══════════════════════════

  void _ensureTouchInitialized(GameState gs) {
    if (_touchInitialized) return;
    // 首次触摸时初始化 touch controller 的 mode 为 GameMode.move
    // TouchController 初始状态就是 idle + move，无需额外初始化
    _touchInitialized = true;
  }

  void _onPointerDown(
    Offset pos, double cellSize, double distance, GameState gs,
  ) {
    _ensureTouchInitialized(gs);
    final currentId = gs.currentPlayerIsTop
        ? gs.topPlayerId
        : gs.bottomPlayerId;
    final wallsPlaced = gs.currentPlayerIsTop
        ? gs.topWallsPlaced
        : gs.bottomWallsPlaced;
    final remainingWalls =
        SurroundGameConstants.wallCountPerPlayer - wallsPlaced;

    _touchController.handleTouchBegan(
      pos, cellSize, distance,
      isRunning: gs.status == GameStatus.running,
      currentPlayerId: currentId,
      canPlaceWall: remainingWalls > 0,
      validateWall: (wx, wy, o) => _validateWall(gs, wx, wy, o),
    );
    setState(() {});
  }

  void _onPointerMove(
    Offset pos, double cellSize, double distance, GameState gs,
  ) {
    _touchController.handleTouchMoved(
      pos, cellSize, distance,
      validateWall: (wx, wy, o) => _validateWall(gs, wx, wy, o),
    );
    setState(() {});
  }

  void _onPointerUp(
    Offset pos, double cellSize, double distance, GameState gs,
  ) {
    _touchController.handleTouchEnded(
      pos, cellSize, distance,
      isTopTurn: gs.currentPlayerIsTop,
      validMoves: gs.validMoves,
      validateWall: (wx, wy, o) => _validateWall(gs, wx, wy, o),
    );
    setState(() {});
  }

  void _onPointerCancel() {
    _touchController.handleTouchCancelled();
    setState(() {});
  }

  // ═══════════════════════════ 操作回调 ═══════════════════════════

  bool _validateWall(
    GameState gs, int wx, int wy, WallOrientation o,
  ) {
    return QuoridorEngine.isWallPlacementValid(
      gs.wallGrid, gs.adjacency,
      gs.topPlayerId, gs.bottomPlayerId,
      wx, wy, o,
    );
  }

  VoidCallback _onConfirm(GameState gs) {
    return () {
      final toc = _touchController;
      if (toc.phase != TouchPhase.confirming) return;

      int? wx, wy;
      WallOrientation? wo;
      if (toc.pendingWall != null) {
        wx = toc.pendingWall!.x;
        wy = toc.pendingWall!.y;
        wo = toc.pendingWall!.o;
      }

      _viewModel.dispatch(LocalMoveCommitted(
        targetCellId: toc.pendingTargetCellId ?? 0,
        wallX: wx,
        wallY: wy,
        wallOrientation: wo,
      ));
      toc.reset();
      setState(() {});
    };
  }

  VoidCallback get _onCancel {
    return () {
      _touchController.cancelAction();
      setState(() {});
    };
  }

  VoidCallback _onRotate(GameState gs) {
    return () {
      _touchController.rotatePendingWall(
        validateWall: (wx, wy, o) => _validateWall(gs, wx, wy, o),
      );
      setState(() {});
    };
  }

  void _toggleMode() {
    _touchController.toggleMode();
    setState(() {});
  }

  // ═══════════════════════ 确认对话框 ═══════════════════════

  Widget _bottomAction({
    required IconData icon,
    required String label,
    required BoardThemeData theme,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final color = theme.btnText.withValues(alpha: enabled ? 0.5 : 0.25);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  void _showResetConfirm(BuildContext context, BoardThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: theme.panelBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(Icons.refresh, size: 32,
              color: theme.btnText.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            Text('重新开始',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: theme.btnText,
              ),
            ),
            const SizedBox(height: 4),
            Text('当前对局记录将丢失',
              style: TextStyle(
                fontSize: 13,
                color: theme.btnSub,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      side: BorderSide(color: theme.btnBorder),
                    ),
                    child: Text('取消',
                      style: TextStyle(color: theme.btnText)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _touchController.reset();
                      _viewModel.dispatch(const LocalResetRequested());
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: theme.piecePlayerA,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text('确定',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showExitConfirm(BuildContext context, BoardThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: theme.panelBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(Icons.exit_to_app, size: 32,
              color: theme.btnText.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            Text('退出游戏',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: theme.btnText,
              ),
            ),
            const SizedBox(height: 4),
            Text('当前对局记录将丢失',
              style: TextStyle(
                fontSize: 13,
                color: theme.btnSub,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      side: BorderSide(color: theme.btnBorder),
                    ),
                    child: Text('取消',
                      style: TextStyle(color: theme.btnText)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _touchController.reset();
                      _viewModel.dispatch(const LocalExitRequested());
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: theme.piecePlayerA,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Text('确定',
                      style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showUndoRequestConfirm(BuildContext context, BoardThemeData theme,
      {required bool isTopPlayer}) {
    final who = isTopPlayer ? '上方' : '下方';
    final rotated = !isTopPlayer;
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Transform(
          alignment: Alignment.center,
          transform: rotated
              ? (Matrix4.identity()..rotateZ(3.14159))
              : Matrix4.identity(),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.panelBg,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.undo, size: 40, color: theme.piecePlayerA),
                const SizedBox(height: 12),
                Text('$who请求悔棋',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.btnText,
                  ),
                ),
                const SizedBox(height: 6),
                Text('将撤销上一步，回合回到上一步的执行者',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: theme.btnSub),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          side: BorderSide(color: theme.btnBorder),
                        ),
                        child: Text('拒绝',
                            style: TextStyle(color: theme.btnText)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _viewModel.dispatch(
                              const LocalUndoRequested());
                        },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: theme.piecePlayerA,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text('同意',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════ 胜利覆盖层 ═══════════════════════

  Widget _buildVictoryOverlay(LocalFinished finished, BoardThemeData theme) {
    final isTopWin = finished.result == GameResult.topWin;
    final winColor = isTopWin ? theme.piecePlayerA : theme.piecePlayerB;
    final winLabel = isTopWin ? '上方获胜！' : '下方获胜！';

    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          decoration: BoxDecoration(
            color: theme.panelBg,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events, size: 48, color: winColor),
              const SizedBox(height: 12),
              Text(winLabel,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: winColor,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReplayPage(
                            history: List.of(finished.finalState.history),
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: winColor,
                      side: BorderSide(color: winColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    child: const Text('观看回放'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      _touchController.reset();
                      _viewModel.dispatch(const LocalResetRequested());
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: winColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: const Text('再来一局'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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

/// 确认阶段目标格高亮 — 使用 [BoardThemeData.validMoveRing] 令牌，
/// 与合法落子提示保持视觉一致。
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
    final cellSize_ = cellSize - 2;

    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: cellSize_,
        height: cellSize_,
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
