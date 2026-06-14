// lib/core/surround_game/pages/game_page.dart
//
// GamePage: 棋盘全宽 + 上下面板 + 底部重来按钮
//
// 颜色全部从 [BoardTheme.of(context)] 读取 — 主题切换只改令牌，不改代码。
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
import 'replay_page.dart';

/// 主游戏页面
class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final _controller = GameController();

  @override
  void dispose() {
    _controller.stateNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 主题令牌 — 整页统一从 [BoardTheme] 读取
    final theme = BoardTheme.of(context);

    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // 上方面板 — 居中药丸
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Center(
                    child: ValueListenableBuilder<GameUiState>(
                      valueListenable: _controller.stateNotifier,
                      builder: (_, ui, __) => PlayerPanel(
                        notifier: _controller,
                        rotated: true,
                        active: ui.isTopTurn,
                        isTop: true,
                        onUndoRequest: () => _showUndoRequestConfirm(
                            context, theme,
                            isTopPlayer: true),
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
                              ChessBoard(cellSize: cellSize, theme: theme),

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
                                        theme: theme,
                                      ),
                                      PlayerPrompt(
                                        validMoves: gs.validMoves,
                                        cellSize: cellSize,
                                        theme: theme,
                                        visible: ui.targetCellId != null,
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
                                      // 确认阶段：目标格特殊高亮
                                      if (pendingCellId != null)
                                        _PendingHighlight(
                                          cellId: pendingCellId,
                                          cellSize: cellSize,
                                          theme: theme,
                                        ),
                                      WallPrompt(
                                        wallData: ui.previewWall ?? ui.pendingWall,
                                        cellSize: cellSize,
                                        theme: theme,
                                        isValid: ui.wallPreviewValid,
                                        visible: ui.previewWall != null || ui.pendingWall != null,
                                      ),
                                      if (ui.dragOffset != null && ui.targetCellId != null)
                                        _buildFloatingPiece(
                                          ui.dragOffset!,
                                          ui.isTopTurn,
                                          cellSize,
                                          theme,
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

                              // 确认操作按钮 — 就地确认
                              ValueListenableBuilder<GameUiState>(
                                valueListenable: _controller.stateNotifier,
                                builder: (_, ui, __) => ConfirmActions(
                                  ui: ui,
                                  controller: _controller,
                                  cellSize: cellSize,
                                  boardSize: boardSize,
                                  theme: theme,
                                ),
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
                  padding: const EdgeInsets.only(top: 6, bottom: 10),
                  child: Center(
                    child: ValueListenableBuilder<GameUiState>(
                      valueListenable: _controller.stateNotifier,
                      builder: (_, ui, __) => PlayerPanel(
                        notifier: _controller,
                        rotated: false,
                        active: !ui.isTopTurn,
                        isTop: false,
                        onUndoRequest: () => _showUndoRequestConfirm(
                            context, theme,
                            isTopPlayer: false),
                      ),
                    ),
                  ),
                ),

                // 底部操作 — 重新开始
                Padding(
                  padding: const EdgeInsets.only(
                    left: 16, top: 6, bottom: 6, right: 16,
                  ),
                  child: Row(
                    children: [
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
            ValueListenableBuilder<GameUiState>(
              valueListenable: _controller.stateNotifier,
              builder: (_, ui, __) {
                final status = ui.gameState.status;
                if (status == GameStatus.running || status == GameStatus.draw) {
                  return const SizedBox.shrink();
                }

                final isTopWin = status == GameStatus.topWin;
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
                                        history:
                                            List.of(ui.gameState.history),
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
                                onPressed: () => _controller.resetGame(),
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
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 底部小操作项：图标 + 文字，onTap=null 时置灰禁用。
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
              color: theme.btnText.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            // 标题
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
                      _controller.resetGame();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: theme.piecePlayerA,
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

  void _showUndoRequestConfirm(BuildContext context, BoardThemeData theme,
      {required bool isTopPlayer}) {
    final who = isTopPlayer ? '上方' : '下方';
    // bottom 玩家时翻转 180°，使按钮布局与实际位置一致（拒绝在左、同意在右）
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
                        child: Text('拒绝', style: TextStyle(color: theme.btnText)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _controller.undoLastMove();
                        },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: theme.piecePlayerA,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text('同意', style: TextStyle(color: Colors.white)),
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
