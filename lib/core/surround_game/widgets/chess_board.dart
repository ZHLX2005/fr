/// 棋盘背景组件
///
/// 严格对齐 Swift ChessBoard.swift 绘制。
///   格子位置：x * distance + 1
///   格子大小：cellSize - 2
///   圆角：4pt
import 'package:flutter/material.dart';
import '../game_theme.dart';

/// 棋盘格子背景 — CustomPainter
class ChessBoardPainter extends CustomPainter {
  final double cellSize;
  final GameTheme theme;

  ChessBoardPainter({required this.cellSize, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    // 不再绘制棋盘背景 RRect，直接使用 Scaffold 的背景色，
    // 避免背景圆角矩形在纯色背景上产生"边框"视觉效果。
    final distance = cellSize * 1.25;
    final cellPaint = Paint()..color = theme.cellFill;
    final borderPaint = Paint()
      ..color = theme.cellBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final cellSize_ = cellSize - 2; // Swift: cellSize - 2

    for (int row = 0; row < 9; row++) {
      for (int col = 0; col < 9; col++) {
        // Swift ChessBoard.swift: x = CGFloat(x) * distance + 1
        final left = col * distance + 1;
        final top = row * distance + 1;
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, cellSize_, cellSize_),
          const Radius.circular(4), // Swift: cornerRadius: 4
        );
        canvas.drawRRect(rrect, cellPaint);
        canvas.drawRRect(rrect, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(ChessBoardPainter old) =>
      old.theme != theme || old.cellSize != cellSize;
}

/// ChessBoard Widget
class ChessBoard extends StatelessWidget {
  final double cellSize;
  final GameTheme theme;

  const ChessBoard({
    super.key,
    required this.cellSize,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // boardSize 由父级 SizedBox 决定，这里直接委托 CustomPainter
    final boardSize = cellSize * 11;
    return SizedBox(
      width: boardSize,
      height: boardSize,
      child: CustomPaint(
        painter: ChessBoardPainter(
          cellSize: cellSize,
          theme: theme,
        ),
        size: Size(boardSize, boardSize),
      ),
    );
  }
}
