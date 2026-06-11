// lib/core/surround_game/pages/game_page.dart
//
// GamePage: 棋盘全宽 + 上下面板 + 底部重来按钮
import 'package:flutter/material.dart';
import '../game_ui_state.dart';
import '../game_theme.dart';
import '../surround_game_constants.dart';
import '../widgets/chess_board.dart';
import '../widgets/chess_player.dart';
import '../widgets/chess_wall.dart';
import '../widgets/player_prompt.dart';
import '../widgets/wall_prompt.dart';
import '../widgets/touch_view.dart';
import '../widgets/player_panel.dart';

/// 主游戏页面
class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final _controller = GameController();
  var _theme = const GameTheme();

  @override
  void dispose() {
    _controller.stateNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _theme.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // 上方面板 — 居中药丸
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Center(
                    child: ValueListenableBuilder<GameUiState>(
                      valueListenable: _controller.stateNotifier,
                      builder: (_, ui, __) => PlayerPanel(
                        notifier: _controller,
                        rotated: true,
                        active: ui.isTopTurn,
                        isTop: true,
                      ),
                    ),
                  ),
                ),

                // 棋盘 — Expanded + Center 居中
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
                              ChessBoard(cellSize: cellSize, theme: _theme),

                              ValueListenableBuilder<GameUiState>(
                                valueListenable: _controller.stateNotifier,
                                builder: (_, ui, __) {
                                  final gs = ui.gameState;

                                  // 确认阶段：棋子预览到目标位置
                                  final pendingCellId = ui.pendingTargetCellId;
                                  final topId = pendingCellId != null && ui.isTopTurn
                                      ? pendingCellId
                                      : gs.topPlayerId;
                                  final bottomId = pendingCellId != null && !ui.isTopTurn
                                      ? pendingCellId
                                      : gs.bottomPlayerId;

                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      ChessWall(
                                        history: gs.history,
                                        cellSize: cellSize,
                                        theme: _theme,
                                      ),
                                      PlayerPrompt(
                                        validMoves: gs.validMoves,
                                        cellSize: cellSize,
                                        theme: _theme,
                                        visible: ui.targetCellId != null,
                                      ),
                                      ChessPlayer(
                                        cellId: topId,
                                        cellSize: cellSize,
                                        color: GameTheme.topPlayer,
                                      ),
                                      ChessPlayer(
                                        cellId: bottomId,
                                        cellSize: cellSize,
                                        color: GameTheme.bottomPlayer,
                                      ),
                                      // 确认阶段：目标格特殊高亮
                                      if (pendingCellId != null)
                                        _PendingHighlight(
                                          cellId: pendingCellId,
                                          cellSize: cellSize,
                                        ),
                                      WallPrompt(
                                        wallData: ui.previewWall ?? ui.pendingWall,
                                        cellSize: cellSize,
                                        color: ui.wallColor,
                                        visible: ui.previewWall != null || ui.pendingWall != null,
                                      ),
                                      if (ui.dragOffset != null && ui.targetCellId != null)
                                        _buildFloatingPiece(
                                          ui.dragOffset!,
                                          ui.isTopTurn,
                                          cellSize,
                                        ),
                                    ],
                                  );
                                },
                              ),

                              TouchView(
                                controller: _controller,
                                cellSize: cellSize,
                                distance: distance,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // 下方面板 — 居中药丸
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Center(
                    child: ValueListenableBuilder<GameUiState>(
                      valueListenable: _controller.stateNotifier,
                      builder: (_, ui, __) => PlayerPanel(
                        notifier: _controller,
                        rotated: false,
                        active: !ui.isTopTurn,
                        isTop: false,
                      ),
                    ),
                  ),
                ),

                // 底部重来按钮
                GestureDetector(
                  onTap: () => _showResetConfirm(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.refresh, size: 14,
                          color: _theme.btnText.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text('重新开始',
                          style: TextStyle(
                            fontSize: 12,
                            color: _theme.btnText.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // 胜利弹层
            ValueListenableBuilder<GameUiState>(
              valueListenable: _controller.stateNotifier,
              builder: (_, ui, __) {
                final status = ui.gameState.status;
                if (status == GameStatus.running || status == GameStatus.draw) {
                  return const SizedBox.shrink();
                }

                final isTopWin = status == GameStatus.topWin;
                final winColor = isTopWin ? GameTheme.topPlayer : GameTheme.bottomPlayer;
                final winLabel = isTopWin ? '上方获胜！' : '下方获胜！';

                return Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
                      decoration: BoxDecoration(
                        color: _theme.panelBg,
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
                          FilledButton(
                            onPressed: () => _controller.resetGame(),
                            style: FilledButton.styleFrom(
                              backgroundColor: winColor,
                            ),
                            child: const Text('再来一局'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showResetConfirm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: _theme.panelBg,
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
            // 顶部指示条
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 图标
            Icon(Icons.refresh, size: 32,
              color: _theme.btnText.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            // 标题
            Text('重新开始',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _theme.btnText,
              ),
            ),
            const SizedBox(height: 4),
            Text('当前对局记录将丢失',
              style: TextStyle(
                fontSize: 13,
                color: _theme.btnSub,
              ),
            ),
            const SizedBox(height: 20),
            // 按钮行
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
                      side: BorderSide(color: _theme.btnBorder),
                    ),
                    child: Text('取消',
                      style: TextStyle(color: _theme.btnText)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _controller.resetGame();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: GameTheme.topPlayer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text('确定', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingPiece(
    Offset offset, bool isTopTurn, double cellSize,
  ) {
    final color = isTopTurn ? GameTheme.topPlayer : GameTheme.bottomPlayer;
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

/// 确认阶段目标格高亮
class _PendingHighlight extends StatelessWidget {
  final int cellId;
  final double cellSize;

  const _PendingHighlight({
    required this.cellId,
    required this.cellSize,
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
          color: Colors.green.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.green.withValues(alpha: 0.7),
            width: 2,
          ),
        ),
      ),
    );
  }
}
