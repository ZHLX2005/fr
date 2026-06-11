/// 墙壁放置预览组件
///
/// 当玩家拖拽墙壁时显示半透明的预览方块。
import 'package:flutter/material.dart';
import '../surround_game_constants.dart';

/// 墙壁拖拽预览
class WallPrompt extends StatelessWidget {
  final ({int x, int y, WallOrientation o})? wallData;
  final double cellSize;
  final Color color;
  final bool visible;

  const WallPrompt({
    super.key,
    required this.wallData,
    required this.cellSize,
    required this.color,
    this.visible = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible || wallData == null) return const SizedBox.shrink();

    final distance = cellSize * 1.25;
    final isHorizontal = wallData!.o == WallOrientation.horizontal;
    final borderOffset = (cellSize * 0.03).clamp(1.5, 3.0);

    // Swift ChessWall.swift:22-23 原公式：
    //   横墙: left = x*dist - 2,  top = y*dist + cellSize - 2
    //   竖墙: left = x*dist + cellSize - 2,  top = y*dist - 2
    final left = wallData!.x * distance + (isHorizontal ? -borderOffset : cellSize - borderOffset);
    final top = wallData!.y * distance + (isHorizontal ? cellSize - borderOffset : -borderOffset);
    final wallWidth = isHorizontal
        ? cellSize * 2.25 + borderOffset * 2
        : cellSize * 0.25 + borderOffset * 2;
    final wallHeight = isHorizontal
        ? cellSize * 0.25 + borderOffset * 2
        : cellSize * 2.25 + borderOffset * 2;

    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: wallWidth,
        height: wallHeight,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
