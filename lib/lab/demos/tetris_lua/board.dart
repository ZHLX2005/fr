// lib/lab/demos/tetris_lua/board.dart
// 俄罗斯方块 — 棋盘与方块预览渲染
//
//   [TetrisBoardView]   主棋盘：堆积 + 下落块 + ghost 落点预览
//   [TetrisMiniBoard]   对方迷你预览：只画堆积（复用主棋盘，无 current/ghost）
//   [TetrisPiecePreview] 单方块预览：Hold / Next 槽用
//
// 所有颜色从 ColorScheme + 主题策略派生：
//   - 棋盘角色（背景/网格/方块顶亮面/方块识别色）→ TetrisColorsStrategy（tetris 专属）
//   - ghost 落点                            → pieceColor + 固定 alpha 派生（动态跟随 piece 色）

import 'dart:math' as math show min;

import 'package:flutter/material.dart';

import '../../../widgets/context_tetris_colors.dart';
import '../../../core/theme/colors/strategy/tetris_colors_strategy/tetris_colors_strategy.dart';
import 'constants.dart';
import 'engine.dart' show TetrisPiece;

class TetrisBoardView extends StatelessWidget {
  const TetrisBoardView({
    super.key,
    required this.grid,
    this.current,
    this.ghostOffset = 0,
  });

  final List<List<int>> grid;
  final TetrisPiece? current;
  final int ghostOffset;

  @override
  Widget build(BuildContext context) {
    // 自适应：在父约束内取最大且不溢出的尺寸（宽高比 cols:rows = 1:2）
    return LayoutBuilder(
      builder: (ctx, c) {
        final ratio = kTetrisCols / kTetrisRows;
        final w = math.min(c.maxWidth, c.maxHeight * ratio);
        return SizedBox(
          width: w,
          height: w / ratio,
          child: CustomPaint(
            painter: _BoardPainter(
              scheme: Theme.of(ctx).colorScheme,
              tc: ctx.tetrisColors,
              pieceColors: ctx.tetrisColors.pieceColors,
              grid: grid,
              current: current,
              ghost: ghostOffset,
            ),
          ),
        );
      },
    );
  }
}

/// 对方迷你预览：只渲染堆积（grid），无下落块。
class TetrisMiniBoard extends StatelessWidget {
  const TetrisMiniBoard({super.key, required this.board});
  final List<List<int>> board;
  @override
  Widget build(BuildContext context) =>
      TetrisBoardView(grid: board, current: null, ghostOffset: 0);
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.scheme,
    required this.tc,
    required this.pieceColors,
    required this.grid,
    this.current,
    this.ghost = 0,
  });
  final ColorScheme scheme;
  final TetrisColorsStrategy tc;
  final List<Color> pieceColors;
  final List<List<int>> grid;
  final TetrisPiece? current;
  final int ghost;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / kTetrisCols;
    final cellH = size.height / kTetrisRows;

    // 背景走 tc.pieceBackground，网格线走 tc.pieceGridLine（tetris 棋盘策略）
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = tc.pieceBackground,
    );
    final linePaint = Paint()
      ..color = tc.pieceGridLine
      ..strokeWidth = 1;
    for (var i = 1; i < kTetrisCols; i++) {
      canvas.drawLine(
        Offset(cellW * i, 0),
        Offset(cellW * i, size.height),
        linePaint,
      );
    }
    for (var i = 1; i < kTetrisRows; i++) {
      canvas.drawLine(
        Offset(0, cellH * i),
        Offset(size.width, cellH * i),
        linePaint,
      );
    }

    // 堆积格
    for (var y = 0; y < grid.length && y < kTetrisRows; y++) {
      final row = grid[y];
      for (var x = 0; x < row.length && x < kTetrisCols; x++) {
        final t = row[x];
        if (t != kEmptyCell) {
          _drawCell(canvas, cellW * x, cellH * y, cellW, cellH, pieceColors[t]);
        }
      }
    }

    final cur = current;
    if (cur == null) return;

    // ghost 落点
    if (ghost > 0) {
      final color = pieceColors[cur.type];
      for (var i = 0; i < cur.matrix.length; i++) {
        for (var j = 0; j < cur.matrix[i].length; j++) {
          if (cur.matrix[i][j] == 0) continue;
          final gy = cur.y + i + ghost;
          if (gy < 0 || gy >= kTetrisRows) continue;
          _drawGhost(canvas, cellW * (cur.x + j), cellH * gy, cellW, cellH, color);
        }
      }
    }

    // 下落块
    final color = pieceColors[cur.type];
    for (var i = 0; i < cur.matrix.length; i++) {
      for (var j = 0; j < cur.matrix[i].length; j++) {
        if (cur.matrix[i][j] == 0) continue;
        final gy = cur.y + i;
        if (gy < 0 || gy >= kTetrisRows) continue;
        _drawCell(canvas, cellW * (cur.x + j), cellH * gy, cellW, cellH, color);
      }
    }
  }

  void _drawCell(Canvas c, double x, double y, double w, double h, Color color) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(x + 1, y + 1, w - 2, h - 2),
      Radius.circular(math.min(w, h) * 0.14),
    );
    c.drawRRect(r, Paint()..color = color);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 2.5, y + 2.5, w - 5, (h - 5) * 0.32),
        const Radius.circular(2),
      ),
      Paint()..color = tc.cellHighlight,
    );
  }

  void _drawGhost(Canvas c, double x, double y, double w, double h, Color color) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(x + 2, y + 2, w - 4, h - 4),
      const Radius.circular(3),
    );
    c.drawRRect(r, Paint()..color = color.withValues(alpha: 0.16));
    c.drawRRect(
      r,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      scheme != old.scheme ||
      tc != old.tc ||
      pieceColors != old.pieceColors ||
      grid != old.grid ||
      current != old.current ||
      ghost != old.ghost;
}

// ══════════════════════════════════════════════════════════════
// 单方块预览
// ══════════════════════════════════════════════════════════════

class TetrisPiecePreview extends StatelessWidget {
  const TetrisPiecePreview({super.key, this.type});
  final int? type;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _PiecePreviewPainter(
          scheme: Theme.of(context).colorScheme,
          tc: context.tetrisColors,
          pieceColors: context.tetrisColors.pieceColors,
          type: type,
        ),
      ),
    );
  }
}

class _PiecePreviewPainter extends CustomPainter {
  _PiecePreviewPainter({
    required this.scheme,
    required this.tc,
    required this.pieceColors,
    required this.type,
  });
  final ColorScheme scheme;
  final TetrisColorsStrategy tc;
  final List<Color> pieceColors;
  final int? type;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      Paint()..color = tc.pieceBackground,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      Paint()
        ..color = tc.pieceGridLine
        ..style = PaintingStyle.stroke,
    );

    final t = type;
    if (t == null) return;
    final matrix = kPieceMatrices[t];
    if (matrix == null) return;

    final n = 4.0;
    final cell = size.shortestSide / n;
    final matLen = matrix.length;
    var minR = matLen, maxR = -1, minC = 99, maxC = -1;
    for (var i = 0; i < matLen; i++) {
      for (var j = 0; j < matrix[i].length; j++) {
        if (matrix[i][j] != 0) {
          if (i < minR) minR = i;
          if (i > maxR) maxR = i;
          if (j < minC) minC = j;
          if (j > maxC) maxC = j;
        }
      }
    }
    final boxW = (maxC - minC + 1) * cell;
    final boxH = (maxR - minR + 1) * cell;
    final ox = (size.width - boxW) / 2 - minC * cell;
    final oy = (size.height - boxH) / 2 - minR * cell;

    final color = pieceColors[t];
    final paint = Paint()..color = color;
    for (var i = 0; i < matLen; i++) {
      for (var j = 0; j < matrix[i].length; j++) {
        if (matrix[i][j] == 0) continue;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(ox + j * cell + 1, oy + i * cell + 1, cell - 2, cell - 2),
            Radius.circular(cell * 0.14),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PiecePreviewPainter old) =>
      scheme != old.scheme ||
      tc != old.tc ||
      pieceColors != old.pieceColors ||
      type != old.type;
}