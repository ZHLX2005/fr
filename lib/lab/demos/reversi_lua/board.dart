// lib/lab/demos/reversi_lua/board.dart
//
// 黑白翻转棋棋盘 widget — 全量 CustomPainter 绘制（含棋子 + 高亮 + 提示点），
// 配合 RepaintBoundary 隔离。仅在 cells/lastMove/legalHints/currentIsBlack 变化时
// 触发整张 painter 一次重绘，避免 64 个 Positioned + 64 个 _Piece 反复重建。

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/reversi/board_theme.dart';
import 'package:xiaodouzi_fr/core/reversi/models/reversi_board.dart';

import 'constants.dart';

/// 8x8 棋盘。`cells[row][col]` = 棋子类型；`lastMove` 高亮；`legalHints` 渲染合法步提示点。
/// `boardSize` 是父级 LayoutBuilder 算好的边长（px），避免内层再 LayoutBuilder 引发
/// 双重布局导致命中测试错位 / 点击不响应。
class ReversiBoardWidget extends StatelessWidget {
  final List<List<PieceType>> cells;
  final Position? lastMove;
  final Set<Position> legalHints;
  final bool currentIsBlack;
  final double boardSize;

  const ReversiBoardWidget({
    super.key,
    required this.cells,
    required this.lastMove,
    required this.legalHints,
    required this.currentIsBlack,
    required this.boardSize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ReversiTheme.of(context);
    final cellPx = boardSize / kReversiSize;

    return RepaintBoundary(
      child: SizedBox(
        width: boardSize,
        height: boardSize,
        child: Stack(
          children: [
            // 1. 格子底色（4 层 painter：底色/高光/暗部/描边）
            CustomPaint(
              size: Size(boardSize, boardSize),
              painter: _BoardPainter(
                theme: theme,
                boardSize: kReversiSize,
              ),
            ),
            // 2. 棋子 + 高亮 + 合法步提示（单 painter 一次画完 64 格）
            CustomPaint(
              size: Size(boardSize, boardSize),
              painter: _PiecesPainter(
                theme: theme,
                cells: cells,
                cellPx: cellPx,
                lastMove: lastMove,
                legalHints: legalHints,
                currentIsBlack: currentIsBlack,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 内部 painter 1：格子底色（4 层）──

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

// ── 内部 painter 2：棋子 + lastMove 高亮 + 合法步提示（一次画完）──

class _PiecesPainter extends CustomPainter {
  final ReversiThemeData theme;
  final List<List<PieceType>> cells;
  final double cellPx;
  final Position? lastMove;
  final Set<Position> legalHints;
  final bool currentIsBlack;

  _PiecesPainter({
    required this.theme,
    required this.cells,
    required this.cellPx,
    required this.lastMove,
    required this.legalHints,
    required this.currentIsBlack,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hintPaint = Paint()
      ..color = currentIsBlack ? theme.legalHintBlack : theme.legalHintWhite;

    for (var row = 0; row < kReversiSize; row++) {
      for (var col = 0; col < kReversiSize; col++) {
        final pos = Position(row, col);
        final cx = col * cellPx + cellPx / 2;
        final cy = row * cellPx + cellPx / 2;
        final piece = cells[row][col];

        // 合法步提示
        if (legalHints.contains(pos)) {
          canvas.drawCircle(
            Offset(cx, cy),
            cellPx * 0.15,
            hintPaint,
          );
        }

        // 棋子
        if (piece == PieceType.empty) continue;
        final pieceR = cellPx * 0.42;

        // 立体感：径向渐变 + 阴影
        final pieceRect = Rect.fromCircle(center: Offset(cx, cy), radius: pieceR);
        final isBlack = piece == PieceType.black;
        final grad = RadialGradient(
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
        );
        final piecePaint = Paint()..shader = grad.createShader(pieceRect);
        canvas.drawCircle(Offset(cx, cy), pieceR, piecePaint);

        // 描边：lastMove 高亮 vs 普通
        final ringColor = lastMove == pos
            ? theme.lastMoveRing
            : Colors.white.withValues(alpha: isBlack ? 0.15 : 0.6);
        final stroke = Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = lastMove == pos ? 2.5 : 1;
        canvas.drawCircle(Offset(cx, cy), pieceR, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_PiecesPainter old) {
    if (old.theme != theme) return true;
    if (old.currentIsBlack != currentIsBlack) return true;
    if (old.lastMove != lastMove) return true;
    if (old.cellPx != cellPx) return true;
    if (!identical(old.cells, cells)) {
      // 引用变了通常意味着 _cells 内容变了（list contents may equal but identity 不同）
      for (var r = 0; r < kReversiSize; r++) {
        for (var c = 0; c < kReversiSize; c++) {
          if (old.cells[r][c] != cells[r][c]) return true;
        }
      }
    }
    if (old.legalHints.length != legalHints.length) return true;
    if (!old.legalHints.containsAll(legalHints)) return true;
    return false;
  }
}