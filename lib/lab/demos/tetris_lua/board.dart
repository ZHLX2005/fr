// lib/lab/demos/tetris_lua/board.dart
// 俄罗斯方块 — 棋盘与方块预览渲染（Ash flat well）
//
//   [TetrisBoardView]   主棋盘：堆积 + 下落块 + ghost 落点预览
//   [TetrisMiniBoard]   对方迷你预览：只画堆积（复用主棋盘，无 current/ghost）
//   [TetrisPiecePreview] 单方块预览：Hold / Next 槽用
//
// 颜色：
//   - 棋盘井纯色（无渐变）/ 网格 / 高光 / 方块识别色 → TetrisColorsStrategy
//   - 主棋盘方块格保留斜向立体高光
//   - HOLD/NEXT mini 预览：4×4 网格 + 纯色平格（proto .minip，无 jewel 渐变）
//   - ghost 落点 → 固定投影紫（proto .c.g，与下落块颜色无关）

import 'dart:math' as math show min;
import 'dart:ui' as ui show Gradient;

import 'package:flutter/material.dart';

import '../../../widgets/context_tetris_colors.dart';
import '../../../core/theme/colors/strategy/tetris_colors_strategy/tetris_colors_strategy.dart';
import 'constants.dart';
import 'engine.dart' show TetrisPiece;

// proto .board-wrap .c.g — 固定投影紫：落点预览不能读作任何方块色。
const Color _kGhostStroke = Color(0xB3A56BFF); // rgba(165,107,255,0.7)
const Color _kGhostFill = Color(0x2EA56BFF); // rgba(165,107,255,0.18)

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
    required this.tc,
    required this.pieceColors,
    required this.grid,
    this.current,
    this.ghost = 0,
  });
  final TetrisColorsStrategy tc;
  final Map<int, Color> pieceColors;
  final List<List<int>> grid;
  final TetrisPiece? current;
  final int ghost;

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / kTetrisCols;
    final cellH = size.height / kTetrisRows;
    final boardRect = Offset.zero & size;

    // Ash 中灰井：纯色平面，无渐变
    canvas.drawRect(boardRect, Paint()..color = tc.pieceBackground);

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
          _paintJewelCell(
            canvas,
            cellW * x,
            cellH * y,
            cellW,
            cellH,
            pieceColors[t]!,
            tc.cellHighlight,
          );
        }
      }
    }

    final cur = current;
    if (cur == null) return;

    // ghost 落点
    if (ghost > 0) {
      for (var i = 0; i < cur.matrix.length; i++) {
        for (var j = 0; j < cur.matrix[i].length; j++) {
          if (cur.matrix[i][j] == 0) continue;
          final gy = cur.y + i + ghost;
          if (gy < 0 || gy >= kTetrisRows) continue;
          _paintGhost(
            canvas,
            cellW * (cur.x + j),
            cellH * gy,
            cellW,
            cellH,
          );
        }
      }
    }

    // 下落块
    final color = pieceColors[cur.type]!;
    for (var i = 0; i < cur.matrix.length; i++) {
      for (var j = 0; j < cur.matrix[i].length; j++) {
        if (cur.matrix[i][j] == 0) continue;
        final gy = cur.y + i;
        if (gy < 0 || gy >= kTetrisRows) continue;
        _paintJewelCell(
          canvas,
          cellW * (cur.x + j),
          cellH * gy,
          cellW,
          cellH,
          color,
          tc.cellHighlight,
        );
      }
    }
  }

  // grid 是 engine 内部 mutate 的同一引用；中途变化引用不变 → 用内容快照不可靠。
  // 俄罗斯方块每秒重绘几次、仅 200 格，直接恒重绘，零漏帧。
  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}

/// 糖果立体格：斜向渐变 + 薄高光条（井底保持纯色）。
void _paintJewelCell(
  Canvas c,
  double x,
  double y,
  double w,
  double h,
  Color color,
  Color highlight,
) {
  final radius = Radius.circular(math.min(w, h) * 0.16);
  final r = RRect.fromRectAndRadius(
    Rect.fromLTWH(x + 1.2, y + 1.2, w - 2.4, h - 2.4),
    radius,
  );
  final bounds = r.outerRect;
  c.drawRRect(
    r,
    Paint()
      ..shader = ui.Gradient.linear(
        bounds.topLeft,
        bounds.bottomRight,
        [
          Color.lerp(color, Colors.white, 0.32)!,
          color,
          Color.lerp(color, Colors.black, 0.22)!,
        ],
        const [0.0, 0.42, 1.0],
      ),
  );
  // 顶部薄高光
  final hiH = (h - 5) * 0.24;
  if (hiH > 1) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + w * 0.18, y + 2.8, w * 0.64, hiH),
        const Radius.circular(99),
      ),
      Paint()..color = highlight,
    );
  }
}

void _paintGhost(
  Canvas c,
  double x,
  double y,
  double w,
  double h,
) {
  final r = RRect.fromRectAndRadius(
    Rect.fromLTWH(x + 2, y + 2, w - 4, h - 4),
    Radius.circular(math.min(w, h) * 0.14),
  );
  c.drawRRect(r, Paint()..color = _kGhostFill);
  c.drawRRect(
    r,
    Paint()
      ..color = _kGhostStroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1,
  );
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
    required this.tc,
    required this.pieceColors,
    required this.type,
  });
  final TetrisColorsStrategy tc;
  final Map<int, Color> pieceColors;
  final int? type;

  @override
  void paint(Canvas canvas, Size size) {
    // proto .minip：4×4 网格，1px 间隙透出白色 6% 底，空格填 ash
    const gap = 1.0;
    const pad = 3.0;
    final inner = size.width - pad * 2;
    final cell = (inner - gap * 3) / 4;
    final pitch = cell + gap;

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x0FFFFFFF));
    final ash = Paint()..color = tc.pieceBackground;
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        canvas.drawRect(
          Rect.fromLTWH(pad + c * pitch, pad + r * pitch, cell, cell),
          ash,
        );
      }
    }

    final t = type;
    if (t == null) return;
    final matrix = kPieceMatrices[t];
    if (matrix == null) return;

    // 把 piece 的 bounding box 居中放进 4×4
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
    final boxW = (maxC - minC) * pitch + cell;
    final boxH = (maxR - minR) * pitch + cell;
    final ox = pad + (inner - boxW) / 2 - minC * pitch;
    final oy = pad + (inner - boxH) / 2 - minR * pitch;

    final color = pieceColors[t]!;
    for (var i = 0; i < matLen; i++) {
      for (var j = 0; j < matrix[i].length; j++) {
        if (matrix[i][j] == 0) continue;
        _paintMiniCell(
          canvas,
          ox + j * pitch,
          oy + i * pitch,
          cell,
          color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PiecePreviewPainter old) => old.type != type;
}

/// proto .minip .c.f — mini 格：纯色 + 1px 白 32% 顶带（无 jewel 渐变，
/// 避免小尺寸下 J/L 等方块因高光糊在一起）。
void _paintMiniCell(Canvas c, double x, double y, double s, Color color) {
  c.drawRect(Rect.fromLTWH(x, y, s, s), Paint()..color = color);
  c.drawRect(Rect.fromLTWH(x, y, s, 1), Paint()..color = const Color(0x52FFFFFF));
}
