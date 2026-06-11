/// 合法落子提示叠加层
///
/// 当选中己方棋子后，在棋盘上以半透明高亮块标记所有合法移动目标格子。
import 'package:flutter/material.dart';
import '../game_theme.dart';

/// validMoves 高亮叠加层
class PlayerPrompt extends StatelessWidget {
  final Set<int> validMoves;
  final double cellSize;
  final GameTheme theme;
  final bool visible;

  const PlayerPrompt({
    super.key,
    required this.validMoves,
    required this.cellSize,
    required this.theme,
    this.visible = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible || validMoves.isEmpty) return const SizedBox.shrink();

    final distance = cellSize * 1.25;
    // 严格对齐 ChessBoard 细胞坐标：x*distance + 1, 大小 = cellSize - 2
    final cellSize_ = cellSize - 2;

    final children = validMoves.map((cellId) {
      final x = (cellId % 9).toDouble();
      final y = (cellId ~/ 9).toDouble();
      final left = x * distance + 1;
      final top = y * distance + 1;

      return Positioned(
        left: left,
        top: top,
        child: Container(
          width: cellSize_,
          height: cellSize_,
          decoration: BoxDecoration(
            color: theme.wall.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: theme.wall.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
        ),
      );
    }).toList();

    return Stack(children: children);
  }
}
