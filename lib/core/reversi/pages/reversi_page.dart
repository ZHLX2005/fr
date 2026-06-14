// lib/core/reversi/pages/reversi_page.dart
//
// 翻转棋主页面
//
// 设计语言（参考 surround_game / BoardTheme 系统）：
//   - 所有颜色从 ReversiTheme.of(context) 语义令牌读取
//   - 棋盘：CustomPainter 4层（底色/高光/暗部/描边）+ Positioned 棋子
//   - 棋子：AnimatedContainer 翻转动画 + 径向渐变立体感
//   - 面板：上下药丸形面板，当前回合方亮起，另一方灰暗
//   - 悔棋：仅当前回合方的面板上有可点 undo 按钮
//
// 布局（自上而下）：
//   [面板A: 黑方 + 悔棋(仅当前方可点)]
//   [面板B: 白方 + 悔棋(仅当前方可点)]
//   [状态提示条]
//   [棋盘(自适应正方形)]
//   [新游戏按钮]
//   [结束弹层(游戏进行时不可见)]
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../board_theme.dart';
import '../models/reversi_board.dart';
import '../providers/reversi_notifier.dart';
import '../providers/reversi_state.dart';
import '../reversi_constants.dart';

class ReversiPage extends StatefulWidget {
  const ReversiPage({super.key});

  @override
  State<ReversiPage> createState() => _ReversiPageState();
}

class _ReversiPageState extends State<ReversiPage> {
  final bool _isDark = false;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        extensions: {
          _isDark ? ReversiTheme.dark : ReversiTheme.classic,
        },
      ),
      child: ChangeNotifierProvider(
        create: (_) => ReversiNotifier(),
        child: _ReversiPageContent(isDark: _isDark),
      ),
    );
  }
}

class _ReversiPageContent extends StatelessWidget {
  final bool isDark;

  const _ReversiPageContent({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final theme = ReversiTheme.of(context);
    final notifier = context.watch<ReversiNotifier>();
    final state = notifier.state;
    final isBlackTurn = state.currentPlayer == PieceType.black;

    return Scaffold(
      backgroundColor: theme.boardSurface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, c) {
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: c.maxWidth,
                  maxHeight: c.maxHeight,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── 面板区 ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          _PlayerPill(
                            name: '黑方',
                            score: state.blackScore,
                            pieceColor: theme.pieceBlack,
                            isActive: isBlackTurn && !state.isOver,
                            canUndo: !state.isOver && state.canUndo,
                            theme: theme,
                            onUndo: notifier.undo,
                          ),
                          const SizedBox(height: 6),
                          _PlayerPill(
                            name: '白方',
                            score: state.whiteScore,
                            pieceColor: theme.pieceWhite,
                            isActive: !isBlackTurn && !state.isOver,
                            canUndo: !state.isOver && state.canUndo,
                            theme: theme,
                            onUndo: notifier.undo,
                          ),
                        ],
                      ),
                    ),

                    // ── 状态提示 ──
                    _StatusBar(state: state, theme: theme),

                    // ── 棋盘（正方形自适应） ──
                    _ReversiBoard(
                      state: state,
                      theme: theme,
                      onTapCell: (pos) {
                        if (state.isOver) return;
                        if (state.board.isLegalMove(pos, state.currentPlayer)) {
                          notifier.placeStone(pos);
                        }
                      },
                      onRestart: notifier.restart,
                    ),

                    // ── 底部新游戏 ──
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _RestartButton(theme: theme, onTap: notifier.restart),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ==================== 药丸形玩家面板 ====================

class _PlayerPill extends StatelessWidget {
  final String name;
  final int score;
  final Color pieceColor;
  final bool isActive;
  final bool canUndo;
  final ReversiThemeData theme;
  final VoidCallback onUndo;

  const _PlayerPill({
    required this.name,
    required this.score,
    required this.pieceColor,
    required this.isActive,
    required this.canUndo,
    required this.theme,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isActive ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 200),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.panelBg,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: isActive ? theme.panelBorder : theme.panelBorder.withValues(alpha: 0.4),
            width: isActive ? 1.5 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // 棋子图标
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: pieceColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0, 1)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // 名字 + 分数
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: theme.btnSub,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '$score',
                    style: TextStyle(
                      color: theme.btnText,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            // 悔棋按钮（仅当前方激活时可点）
            _UndoIconButton(
              enabled: isActive && canUndo,
              theme: theme,
              onTap: onUndo,
            ),
          ],
        ),
      ),
    );
  }
}

class _UndoIconButton extends StatelessWidget {
  final bool enabled;
  final ReversiThemeData theme;
  final VoidCallback onTap;

  const _UndoIconButton({
    required this.enabled,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          Icons.undo,
          size: 22,
          color: enabled
              ? theme.btnText.withValues(alpha: 0.85)
              : theme.btnSub.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

// ==================== 状态提示条 ====================

class _StatusBar extends StatelessWidget {
  final ReversiState state;
  final ReversiThemeData theme;

  const _StatusBar({required this.state, required this.theme});

  @override
  Widget build(BuildContext context) {
    String text;
    if (state.message != null) {
      text = state.message!;
    } else if (state.isOver) {
      text = '';
    } else {
      final who = state.currentPlayer == PieceType.black ? '黑' : '白';
      text = '$who方回合 · ${state.legalMoves.length} 处可落子';
    }

    return SizedBox(
      height: 20,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: ReversiConstants.statusFadeMs),
        child: Text(
          text,
          key: ValueKey(text),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.btnSub.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// ==================== 棋盘（CustomPainter） ====================

class _ReversiBoard extends StatelessWidget {
  final ReversiState state;
  final ReversiThemeData theme;
  final ValueChanged<Position> onTapCell;
  final VoidCallback onRestart;

  const _ReversiBoard({
    required this.state,
    required this.theme,
    required this.onTapCell,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final legalSet = state.legalMoves.toSet();

    return LayoutBuilder(
      builder: (ctx, c) {
        // 取 min(宽, 高) 确保正方形且不超出可用空间
        final boardPx = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
        final cellPx = boardPx / ReversiConstants.boardSize;

        return GestureDetector(
          onTapDown: (details) {
            final col = (details.localPosition.dx / cellPx).floor();
            final row = (details.localPosition.dy / cellPx).floor();
            if (row >= 0 && row < ReversiConstants.boardSize &&
                col >= 0 && col < ReversiConstants.boardSize) {
              onTapCell(Position(row, col));
            }
          },
          child: Center(
            child: SizedBox(
              width: boardPx,
              height: boardPx,
              child: Stack(
                children: [
                  CustomPaint(
                    size: Size(boardPx, boardPx),
                    painter: _ReversiBoardPainter(
                      theme: theme,
                      boardSize: ReversiConstants.boardSize,
                    ),
                  ),
                  ...List.generate(
                    ReversiConstants.boardSize * ReversiConstants.boardSize,
                    (i) {
                      final row = i ~/ ReversiConstants.boardSize;
                      final col = i % ReversiConstants.boardSize;
                      final pos = Position(row, col);
                      return Positioned(
                        left: col * cellPx,
                        top: row * cellPx,
                        width: cellPx,
                        height: cellPx,
                        child: _ReversiPiece(
                          piece: state.board.cellAt(row, col),
                          cellPx: cellPx,
                          isLastMove: state.lastMove == pos,
                          theme: theme,
                        ),
                      );
                    },
                  ),
                  // 合法步提示：当前方专属颜色（黑回合暖金色，白回合冰蓝色）
                  ...legalSet.map((pos) => Positioned(
                    left: pos.col * cellPx + cellPx * 0.35,
                    top: pos.row * cellPx + cellPx * 0.35,
                    child: Container(
                      width: cellPx * 0.3,
                      height: cellPx * 0.3,
                      decoration: BoxDecoration(
                        color: state.currentPlayer == PieceType.black
                            ? theme.legalHintBlack
                            : theme.legalHintWhite,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )),
                  if (state.isOver)
                    _GameOverOverlay(
                      status: state.status,
                      blackScore: state.blackScore,
                      whiteScore: state.whiteScore,
                      theme: theme,
                      onRestart: onRestart,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReversiBoardPainter extends CustomPainter {
  final ReversiThemeData theme;
  final int boardSize;

  _ReversiBoardPainter({required this.theme, required this.boardSize});

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / boardSize;
    final basePaint = Paint()..color = theme.cellBase;
    final lightPaint = Paint()..color = theme.cellFaceLight;
    final shadowPaint = Paint()
      ..color = theme.cellFaceShadow.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    final edgePaint = Paint()
      ..color = theme.cellEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (var row = 0; row < boardSize; row++) {
      for (var col = 0; col < boardSize; col++) {
        final rect = Rect.fromLTWH(
          col * cellSize,
          row * cellSize,
          cellSize,
          cellSize,
        );

        // 底色
        canvas.drawRect(rect, basePaint);

        // 左上高光（格子凸起感）
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, rect.width * 0.3, 2),
          lightPaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, 2, rect.height * 0.3),
          lightPaint,
        );

        // 右下暗部
        canvas.drawRect(
          Rect.fromLTWH(
            rect.left + rect.width * 0.7,
            rect.bottom - 2,
            rect.width * 0.3,
            2,
          ),
          shadowPaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            rect.right - 2,
            rect.top + rect.height * 0.7,
            2,
            rect.height * 0.3,
          ),
          shadowPaint,
        );

        // 描边
        canvas.drawRect(rect, edgePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_ReversiBoardPainter old) =>
      old.theme != theme || old.boardSize != boardSize;
}

// ==================== 棋子（带翻转动画 + 径向渐变） ====================

class _ReversiPiece extends StatelessWidget {
  final PieceType piece;
  final double cellPx;
  final bool isLastMove;
  final ReversiThemeData theme;

  const _ReversiPiece({
    required this.piece,
    required this.cellPx,
    required this.isLastMove,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (piece == PieceType.empty) return const SizedBox.shrink();

    final isBlack = piece == PieceType.black;
    final pieceSize = cellPx * 0.88;

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: ReversiConstants.flipDurationMs),
        curve: Curves.easeInOut,
        width: pieceSize,
        height: pieceSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.3),
            radius: 0.8,
            colors: isBlack
                ? [
                    theme.pieceBlackHighlight,
                    theme.pieceBlack,
                    theme.pieceBlackRim,
                  ]
                : [
                    theme.pieceWhiteHighlight,
                    theme.pieceWhite,
                    theme.pieceWhiteRim,
                  ],
            stops: const [0.0, 0.5, 1.0],
          ),
          border: Border.all(
            color: isLastMove
                ? theme.lastMoveRing
                : Colors.white.withValues(alpha: isBlack ? 0.15 : 0.6),
            width: isLastMove ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 结束弹层 ====================

class _GameOverOverlay extends StatelessWidget {
  final ReversiStatus status;
  final int blackScore;
  final int whiteScore;
  final ReversiThemeData theme;
  final VoidCallback onRestart;

  const _GameOverOverlay({
    required this.status,
    required this.blackScore,
    required this.whiteScore,
    required this.theme,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    // 胜利强调色用 theme.winAccent（暖金色），无论谁赢都醒目
    final accent = theme.winAccent;
    final (title, _) = switch (status) {
      ReversiStatus.blackWon => ('黑方胜利', theme.pieceBlack),
      ReversiStatus.whiteWon => ('白方胜利', theme.pieceWhite),
      ReversiStatus.draw => ('平局', accent),
      ReversiStatus.playing => ('', accent),
    };

    return Container(
      decoration: BoxDecoration(
        color: theme.boardSurface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                status == ReversiStatus.draw
                    ? Icons.balance
                    : Icons.emoji_events,
                size: 48,
                color: accent,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: accent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$blackScore : $whiteScore',
                style: TextStyle(
                  fontSize: 18,
                  color: theme.btnSub,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onRestart,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text('再来一局'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== 新游戏按钮 ====================

class _RestartButton extends StatelessWidget {
  final ReversiThemeData theme;
  final VoidCallback onTap;

  const _RestartButton({required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.refresh,
              size: 14,
              color: theme.btnSub.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 4),
            Text(
              '新游戏',
              style: TextStyle(
                fontSize: 12,
                color: theme.btnSub.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
