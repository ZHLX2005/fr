// game/board —— 联机棋盘通用绘制件（2026-10-28 自 go/gomoku 两个 lua demo 抽离）。
//
// 两个 demo 的 `_GridPainter` 除棋盘格数常量（围棋 kGoSize / 五子棋 kGomokuSize）
// 外**逐字相同**：横竖各画 size 条 1px 网格线，再按 starPoints 画星位圆点。
// 棋种差异只有「格数」与「星位坐标」，故把格数提为参数后归一到这里。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 棋盘网格线 + 星位绘制器。
class GameGridPainter extends CustomPainter {
  const GameGridPainter({
    required this.size,
    required this.step,
    required this.padding,
    required this.lineColor,
    required this.starPoints,
    required this.starColor,
  });

  /// 棋盘格数（每边格数：围棋 19、五子棋 15）。
  final int size;

  /// 每格像素步长。
  final double step;

  /// 棋盘边距（网格起点偏移）。
  final double padding;

  /// 网格线颜色。
  final Color lineColor;

  /// 星位坐标（格坐标 (x, y)）。
  final List<(int, int)> starPoints;

  /// 星位颜色。
  final Color starColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final n = this.size;
    for (var i = 0; i < n; i++) {
      final y = padding + i * step;
      canvas.drawLine(
        Offset(padding, y),
        Offset(padding + (n - 1) * step, y),
        paint,
      );
    }
    for (var i = 0; i < n; i++) {
      final x = padding + i * step;
      canvas.drawLine(
        Offset(x, padding),
        Offset(x, padding + (n - 1) * step),
        paint,
      );
    }
    final starPaint = Paint()..color = starColor;
    const starRadius = 3.5;
    for (final (x, y) in starPoints) {
      final cx = padding + x * step;
      final cy = padding + y * step;
      canvas.drawCircle(Offset(cx, cy), starRadius, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GameGridPainter oldDelegate) =>
      size != oldDelegate.size ||
      step != oldDelegate.step ||
      padding != oldDelegate.padding ||
      lineColor != oldDelegate.lineColor ||
      starColor != oldDelegate.starColor ||
      !listEquals(oldDelegate.starPoints, starPoints);
}
