// lib/lab/demos/reversi_lua/board.dart
//
// 黑白翻转棋棋盘 widget — 复用 core/reversi 的 4 层 painter 和立体棋子渲染，
// 但 props 改成接 `cells` 二维矩阵 + `lastMove` + `legalHints` + `currentIsBlack`，
// 不依赖 ReversiState / ReversiNotifier。

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/reversi/board_theme.dart';
import 'package:xiaodouzi_fr/core/reversi/models/reversi_board.dart';

import 'constants.dart';

/// 8x8 棋盘。`cells[row][col]` = 棋子类型；`lastMove` 高亮；`legalHints` 渲染合法步提示点。
class ReversiBoardWidget extends StatelessWidget {
  final List<List<PieceType>> cells;
  final Position? lastMove;
  final Set<Position> legalHints;
  final bool currentIsBlack;

  const ReversiBoardWidget({
    super.key,
    required this.cells,
    required this.lastMove,
    required this.legalHints,
    required this.currentIsBlack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ReversiTheme.of(context);

    return LayoutBuilder(
      builder: (ctx, c) {
        // 取 min(宽, 高) 确保正方形
        final boardPx = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
        final cellPx = boardPx / kReversiSize;

        return GestureDetector(
          onTapDown: (details) {
            // 上层将 GestureDetector 的回调放在此 widget 外部处理 pending + 确认
            // 此处仅返回坐标（通过 layout callback）— 但本 widget 故意不接 onTap
            // 由父层用 LayoutBuilder + GestureDetector 自行包装。
          },
          child: SizedBox(
            width: boardPx,
            height: boardPx,
            child: Stack(
              children: [
                CustomPaint(
                  size: Size(boardPx, boardPx),
                  painter: _BoardPainter(
                    theme: theme,
                    boardSize: kReversiSize,
                  ),
                ),
                ...List.generate(
                  kReversiSize * kReversiSize,
                  (i) {
                    final row = i ~/ kReversiSize;
                    final col = i % kReversiSize;
                    final pos = Position(row, col);
                    return Positioned(
                      left: col * cellPx,
                      top: row * cellPx,
                      width: cellPx,
                      height: cellPx,
                      child: _Piece(
                        piece: cells[row][col],
                        cellPx: cellPx,
                        isLastMove: lastMove == pos,
                        theme: theme,
                      ),
                    );
                  },
                ),
                // 合法步提示：当前方专属颜色
                ...legalHints.map((pos) => Positioned(
                      left: pos.col * cellPx + cellPx * 0.35,
                      top: pos.row * cellPx + cellPx * 0.35,
                      child: Container(
                        width: cellPx * 0.3,
                        height: cellPx * 0.3,
                        decoration: BoxDecoration(
                          color: currentIsBlack
                              ? theme.legalHintBlack
                              : theme.legalHintWhite,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── 内部 painter（4 层格子：底色/高光/暗部/描边）──

class _BoardPainter extends CustomPainter {
  final ReversiThemeData theme;
  final int boardSize;

  _BoardPainter({required this.theme, required this.boardSize});

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
        canvas.drawRect(rect, basePaint);
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, rect.width * 0.3, 2),
          lightPaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, 2, rect.height * 0.3),
          lightPaint,
        );
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
        canvas.drawRect(rect, edgePaint);
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.theme != theme || old.boardSize != boardSize;
}

// ── 棋子 widget（径向渐变 + 翻转动画）──

class _Piece extends StatelessWidget {
  final PieceType piece;
  final double cellPx;
  final bool isLastMove;
  final ReversiThemeData theme;

  const _Piece({
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
        duration: const Duration(milliseconds: 280),
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