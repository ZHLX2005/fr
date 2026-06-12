// lib/core/surround_game/widgets/chess_player.dart
import 'package:flutter/material.dart';

/// 棋子 Widget
///
/// 使用 AnimatedContainer 实现 200ms 弹性动画。
/// 棋子大小 = cellSize * 0.7。
class ChessPlayer extends StatelessWidget {
  final int cellId;
  final double cellSize;
  final Color color;

  const ChessPlayer({
    super.key,
    required this.cellId,
    required this.cellSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final distance = cellSize * 1.25;
    final x = (cellId % 9).toDouble();
    final y = (cellId ~/ 9).toDouble();
    final pieceSize = cellSize * 0.7;
    // Swift ChessPlayer: 棋子中心 = (x*distance + cellSize/2, y*distance + cellSize/2)
    final left = x * distance + (cellSize - pieceSize) / 2;
    final top = y * distance + (cellSize - pieceSize) / 2;

    return Positioned(
      left: left,
      top: top,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
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
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}
