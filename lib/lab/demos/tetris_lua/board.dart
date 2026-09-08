// lib/lab/demos/tetris_lua/board.dart
// 俄罗斯方块 — 棋盘与方块预览渲染（Ash well · glossy candy cells）
//
//   [TetrisBoardView]   主棋盘：堆积 + 下落块 + ghost 落点预览
//   [TetrisMiniBoard]   对方迷你预览：只画堆积（复用主棋盘，无 current/ghost）
//   [TetrisPiecePreview] 单方块预览：Hold / Next 槽用
//
// 颜色：
//   - 棋盘井纯色 / 网格 / 方块识别色 → TetrisColorsStrategy
//   - 主棋盘格：圆角 + 斜向柔渐变 + 顶部高光（光滑糖果质感）
//   - HOLD/NEXT mini：同系缩小版
//   - ghost 落点 → 固定投影紫（与下落块颜色无关）

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
    this.expand = false,
  });

  final List<List<int>> grid;
  final TetrisPiece? current;
  final int ghostOffset;

  /// true：填满父约束（父已算好 10:20）；false：在父约束内自算最大 10:20。
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final tc = context.tetrisColors;
    final painter = _BoardPainter(
      tc: tc,
      pieceColors: tc.pieceColors,
      grid: grid,
      current: current,
      ghost: ghostOffset,
    );
    if (expand) {
      return CustomPaint(painter: painter, child: const SizedBox.expand());
    }
    // 自适应：在父约束内取最大且不溢出的尺寸（宽高比 cols:rows = 1:2）
    return LayoutBuilder(
      builder: (ctx, c) {
        final maxW = c.maxWidth;
        final maxH = c.maxHeight;
        if (!maxW.isFinite || !maxH.isFinite || maxW <= 0 || maxH <= 0) {
          return const SizedBox.shrink();
        }
        final ratio = kTetrisCols / kTetrisRows;
        var w = math.min(maxW, maxH * ratio);
        if (w <= 0) return const SizedBox.shrink();
        return SizedBox(
          width: w,
          height: w / ratio,
          child: CustomPaint(painter: painter),
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
  Widget build(BuildContext context) => TetrisBoardView(
        grid: board,
        current: null,
        ghostOffset: 0,
        expand: true,
      );
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

    // proto：每格 outline 1px ash-grid（含外缘，与相邻格共享边）
    final linePaint = Paint()
      ..color = tc.pieceGridLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var y = 0; y < kTetrisRows; y++) {
      for (var x = 0; x < kTetrisCols; x++) {
        canvas.drawRect(
          Rect.fromLTWH(cellW * x, cellH * y, cellW, cellH),
          linePaint,
        );
      }
    }

    // 堆积格
    for (var y = 0; y < grid.length && y < kTetrisRows; y++) {
      final row = grid[y];
      for (var x = 0; x < row.length && x < kTetrisCols; x++) {
        final t = row[x];
        if (t != kEmptyCell) {
          _paintGlossCell(
            canvas,
            cellW * x,
            cellH * y,
            cellW,
            cellH,
            pieceColors[t]!,
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
        _paintGlossCell(
          canvas,
          cellW * (cur.x + j),
          cellH * gy,
          cellW,
          cellH,
          color,
        );
      }
    }
  }

  // grid 是 engine 内部 mutate 的同一引用；中途变化引用不变 → 用内容快照不可靠。
  // 俄罗斯方块每秒重绘几次、仅 200 格，直接恒重绘，零漏帧。
  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}

/// 光滑釉面格：小圆角 + 轻斜渐变 + 细高光（避免泡感胖圆角）。
void _paintGlossCell(
  Canvas c,
  double x,
  double y,
  double w,
  double h,
  Color color,
) {
  final gap = math.min(w, h) * 0.05;
  final radius = math.min(w, h) * 0.14;
  final rect = Rect.fromLTWH(
    x + gap,
    y + gap,
    w - gap * 2,
    h - gap * 2,
  );
  if (rect.width <= 0 || rect.height <= 0) return;
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

  final hi = Color.lerp(color, const Color(0xFFFFFFFF), 0.22)!;
  final mid = color;
  final lo = Color.lerp(color, const Color(0xFF000000), 0.18)!;

  c.drawRRect(
    rrect,
    Paint()
      ..shader = ui.Gradient.linear(
        rect.topCenter,
        rect.bottomCenter,
        [hi, mid, lo],
        const [0.0, 0.55, 1.0],
      ),
  );

  // 顶部细高光条（釉面，非厚 bevel）
  final spec = RRect.fromRectAndRadius(
    Rect.fromLTWH(
      rect.left + rect.width * 0.14,
      rect.top + rect.height * 0.1,
      rect.width * 0.72,
      rect.height * 0.22,
    ),
    Radius.circular(radius * 0.7),
  );
  c.drawRRect(
    spec,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(spec.left, spec.top),
        Offset(spec.left, spec.bottom),
        const [Color(0x59FFFFFF), Color(0x00FFFFFF)],
      ),
  );

  c.drawRRect(
    rrect.deflate(0.5),
    Paint()
      ..color = const Color(0x28FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8,
  );
}

/// ghost：同圆角轮廓的半透明紫描边，不抢色。
void _paintGhost(
  Canvas c,
  double x,
  double y,
  double w,
  double h,
) {
  final gap = math.min(w, h) * 0.05;
  final radius = math.min(w, h) * 0.14;
  final rect = Rect.fromLTWH(
    x + gap,
    y + gap,
    w - gap * 2,
    h - gap * 2,
  );
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
  c.drawRRect(rrect, Paint()..color = _kGhostFill);
  c.drawRRect(
    rrect.deflate(0.5),
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
    // 固定 11px 格（proto），在可用尺寸内居中。
    const gap = 1.0;
    const pad = 3.0;
    const cell = 11.0;
    const pitch = cell + gap;
    const grid = pad * 2 + cell * 4 + gap * 3; // 53
    final ox0 = (size.width - grid) / 2;
    final oy0 = (size.height - grid) / 2;

    canvas.drawRect(
      Rect.fromLTWH(ox0, oy0, grid, grid),
      Paint()..color = const Color(0x0FFFFFFF),
    );
    final ash = Paint()..color = tc.pieceBackground;
    for (var r = 0; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        canvas.drawRect(
          Rect.fromLTWH(ox0 + pad + c * pitch, oy0 + pad + r * pitch, cell, cell),
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
    final inner = grid - pad * 2;
    final boxW = (maxC - minC) * pitch + cell;
    final boxH = (maxR - minR) * pitch + cell;
    final ox = ox0 + pad + (inner - boxW) / 2 - minC * pitch;
    final oy = oy0 + pad + (inner - boxH) / 2 - minR * pitch;

    final color = pieceColors[t]!;
    for (var i = 0; i < matLen; i++) {
      for (var j = 0; j < matrix[i].length; j++) {
        if (matrix[i][j] == 0) continue;
        _paintGlossCell(
          canvas,
          ox + j * pitch,
          oy + i * pitch,
          cell,
          cell,
          color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PiecePreviewPainter old) => old.type != type;
}
