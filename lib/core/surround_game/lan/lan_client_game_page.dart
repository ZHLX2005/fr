// lib/core/surround_game/lan/lan_client_game_page.dart
//
// LAN 客户端游戏页面 — 单面板布局。
//
// 布局：
// ┌────────────────────────────────────────┐
// │ ← 退出   房间名     [● 在线]           │  AppBar
// ├────────────────────────────────────────┤
// │                                        │
// │            棋盘（flipY=false）          │  通过 LanBoardStack
// │                                        │
// ├────────────────────────────────────────┤
// │      自己的 PlayerPanel (isTop=false)   │  底部
// └────────────────────────────────────────┘

import 'package:flutter/material.dart';
import '../board_theme.dart';
import '../surround_game_constants.dart';
import '../widgets/player_panel.dart';
import '../widgets/touch_controller.dart';
import '../engine/game_engine.dart';
import '../models/game_state.dart';
import '../local/local_match_state.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_client_view_model.dart';
import 'widgets/lan_board_stack.dart';

/// LAN 客户端游戏页面
///
/// 单面板布局：棋盘居中（不翻转），底部仅显示 client 自己的 PlayerPanel。
/// touchController 使用普通 [TouchController]（不镜像 y 坐标）。
/// isMyTurn = gs.currentPlayerIsTop == false（client 是 bottom player）。
class LanClientGamePage extends StatefulWidget {
  final String roomId;

  const LanClientGamePage({super.key, required this.roomId});

  @override
  State<LanClientGamePage> createState() => _LanClientGamePageState();
}

class _LanClientGamePageState extends State<LanClientGamePage> {
  late final LanClientViewModel _viewModel;
  final _touchController = TouchController();

  @override
  void initState() {
    super.initState();
    _viewModel = LanClientViewModel();
  }

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
      appBar: _buildAppBar(theme),
      body: SafeArea(
        child: ValueListenableBuilder<LanClientState>(
          valueListenable: _viewModel,
          builder: (_, state, __) => switch (state) {
            ClientInGame(:final gameState) => _buildGameScreen(
                gameState,
                theme,
              ),
            ClientFinished(:final finalState, :final result) =>
              _buildGameScreen(
                finalState,
                theme,
                overlay: _buildVictoryOverlay(finalState, result, theme),
              ),
            _ => _buildWaitingScreen(theme),
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BoardThemeData theme) {
    return AppBar(
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: theme.btnText),
        onPressed: () => _showExitConfirm(context, theme),
      ),
      title: Text(
        '房间 ${widget.roomId}',
        style: TextStyle(color: theme.btnText, fontSize: 14),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '在线',
                style: TextStyle(color: theme.btnSub, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
      backgroundColor: theme.boardSurface,
      elevation: 0,
    );
  }

  Widget _buildWaitingScreen(BoardThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '等待游戏开始...',
            style: TextStyle(fontSize: 18, color: theme.btnText),
          ),
          const SizedBox(height: 8),
          Text(
            '房间 ${widget.roomId}',
            style: TextStyle(fontSize: 14, color: theme.btnSub),
          ),
        ],
      ),
    );
  }

  Widget _buildGameScreen(
    GameState gs,
    BoardThemeData theme, {
    Widget? overlay,
  }) {
    final isRunning = gs.status == GameStatus.running;
    // Client 是 bottom player，轮到 bottom 时为 myTurn
    final isMyTurn = !gs.currentPlayerIsTop;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cellSize = w / 11;

        return Stack(
          children: [
            Column(
              children: [
                // 棋盘
                Expanded(
                  child: Center(
                    child: LanBoardStack(
                      gameState: gs,
                      touchController: _touchController,
                      theme: theme,
                      cellSize: cellSize,
                      flipY: false, // client 不翻转
                      isMyTurn: isMyTurn,
                      onChanged: () => setState(() {}),
                      onConfirm: _onConfirm(gs),
                      onCancel: _onCancel,
                      validateWall: _validateWall,
                    ),
                  ),
                ),
                // 底部 PlayerPanel
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Center(
                    child: _buildPlayerPanel(
                      gs: gs,
                      theme: theme,
                      isTop: false,
                      isTopTurn: gs.currentPlayerIsTop,
                      isRunning: isRunning,
                    ),
                  ),
                ),
                // 退出按钮
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    top: 6,
                    bottom: 6,
                    right: 16,
                  ),
                  child: Row(
                    children: [
                      _bottomAction(
                        icon: Icons.exit_to_app,
                        label: '退出',
                        theme: theme,
                        onTap: () => _showExitConfirm(context, theme),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (overlay != null) overlay,
          ],
        );
      },
    );
  }

  // ═══════════════════ PlayerPanel ═══════════════════

  Widget _buildPlayerPanel({
    required GameState gs,
    required BoardThemeData theme,
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

    return PlayerPanel(
      rotated: false,
      active: active,
      isTop: isTop,
      mode: toc.mode,
      phase: toc.phase,
      canPlaceWall: remainingWalls > 0,
      playerSteps: playerSteps,
      remainingWalls: remainingWalls,
      canRequestUndo: false,
      onToggleMode: active ? () => _toggleMode() : null,
      onUndoRequest: null,
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

  // ═══════════════════ Touch 与 Action ═══════════════════

  // 触摸事件由 LanBoardStack 内部转发到 touchController。

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

      _viewModel.dispatch(ClientMoveCommitted((
        toc.pendingTargetCellId ?? 0, wx, wy, wo,
      )));
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

  // ═══════════════════ Dialogs ═══════════════════

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
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(Icons.exit_to_app,
                size: 32, color: theme.btnText.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            Text('退出游戏',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: theme.btnText)),
            const SizedBox(height: 4),
            Text('当前对局记录将丢失',
                style: TextStyle(fontSize: 13, color: theme.btnSub)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
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
                      Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: theme.piecePlayerA,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24)),
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

  // ═══════════════════ Victory overlay ═══════════════════

  Widget _buildVictoryOverlay(
    GameState finalState,
    GameResult result,
    BoardThemeData theme,
  ) {
    final isTopWin = result == GameResult.topWin;
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
                      color: winColor)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  _touchController.reset();
                  Navigator.of(context).pop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: winColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
