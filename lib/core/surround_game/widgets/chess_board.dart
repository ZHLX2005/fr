// 棋盘背景组件 — 简洁设计版本
//
// 设计理念：三笔两画，用最少的图层实现清晰的棋盘结构
//
// 视觉栈（自下而上）：
//   1. 格子底色  — 纯色填充（cellBase）
//   2. 格子边框  — 1px细线定义边界（cellEdge）
//   3. 内阴影    — 微弱凹陷暗示，仅顶部+左侧（cellFaceShadow）
//   4. 高光点缀  — 中心微光（cellFaceLight，可选）
//
// 颜色全部从 [BoardThemeData] 语义令牌读取，主题切换时绘制代码不动。
import 'package:flutter/material.dart';
import '../board_theme.dart';

/// 棋盘格子背景 — CustomPainter（简洁版）
class ChessBoardPainter extends CustomPainter {
  final double cellSize;
  final BoardThemeData theme;

  /// 待绘制的高亮格子（确认阶段的目标格），可空。
  final int? highlightCellId;

  ChessBoardPainter({
    required this.cellSize,
    required this.theme,
    this.highlightCellId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final distance = cellSize * 1.25;
    final cellSize_ = cellSize - 2;
    final cellRadius = 3.0;

    // Layer 1: 格子底色
    final basePaint = Paint()..color = theme.cellBase;

    // Layer 2: 格子边框（1px细线，半透明）
    final edgePaint = Paint()
      ..color = theme.cellEdge.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Layer 3: 内阴影（仅顶部+左侧，微弱凹陷暗示）
    final shadowPaint = Paint()
      ..color = theme.cellFaceShadow.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    // Layer 4: 确认阶段高亮格子
    Paint? highlightPaint;
    if (highlightCellId != null) {
      highlightPaint = Paint()..color = theme.cellFaceLight.withValues(alpha: 0.25);
    }

    for (int row = 0; row < 9; row++) {
      for (int col = 0; col < 9; col++) {
        final cellId = row * 9 + col;
        final left = col * distance + 1;
        final top = row * distance + 1;
        final cellRect = Rect.fromLTWH(left, top, cellSize_, cellSize_);
        final rrect = RRect.fromRectAndRadius(
          cellRect,
          Radius.circular(cellRadius),
        );

        // Layer 1: 格子底色
        canvas.drawRRect(rrect, basePaint);

        // Layer 3: 内阴影（顶部+左侧边缘）
        _drawInnerShadow(canvas, rrect, shadowPaint);

        // Layer 4: 确认高亮（仅目标格）
        if (highlightPaint != null && cellId == highlightCellId) {
          canvas.drawRRect(rrect, highlightPaint);
        }

        // Layer 2: 格子边框（最后绘制，保持清晰）
        canvas.drawRRect(rrect, edgePaint);
      }
    }
  }

  /// 绘制内阴影 — 仅顶部和左侧边缘
  void _drawInnerShadow(Canvas canvas, RRect rrect, Paint paint) {
    final path = Path()
      ..addRRect(rrect);
    final shadowPath = Path()
      ..addRRect(rrect.shift(const Offset(-0.5, -0.5)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, shadowPath, path),
      paint,
    );
  }

  @override
  bool shouldRepaint(ChessBoardPainter old) =>
      old.theme != theme ||
      old.cellSize != cellSize ||
      old.highlightCellId != highlightCellId;
}

/// ChessBoard Widget
///
/// 接受 [highlightCellId]：当游戏处于确认阶段时，传入目标格 id；
/// 其它时候传 null。Painter 内部据此决定是否绘制二次高亮。
class ChessBoard extends StatelessWidget {
  final double cellSize;
  final BoardThemeData theme;
  final int? highlightCellId;

  const ChessBoard({
    super.key,
    required this.cellSize,
    required this.theme,
    this.highlightCellId,
  });

  @override
  Widget build(BuildContext context) {
    final boardSize = cellSize * 11;
    return SizedBox(
      width: boardSize,
      height: boardSize,
      child: CustomPaint(
        painter: ChessBoardPainter(
          cellSize: cellSize,
          theme: theme,
          highlightCellId: highlightCellId,
        ),
        size: Size(boardSize, boardSize),
      ),
    );
  }
}
