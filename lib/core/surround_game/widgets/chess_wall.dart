/// 墙壁渲染组件
///
/// 遍历 [MoveRecord] 历史中所有墙壁放置记录，将其渲染为
/// 水平或垂直方向的条状方块。
import 'package:flutter/material.dart';
import '../game_theme.dart';
import '../models/game_state.dart';
import '../surround_game_constants.dart';

/// 墙壁渲染层
///
/// 使用 Swift 原始公式定位墙壁：
///   横墙：left = wall.x*distance + cellSize-2,  w = cellSize*2.25+4, h = cellSize*0.25+4
///   竖墙：left = wall.x*distance + cellSize-2,  w = cellSize*0.25+4, h = cellSize*2.25+4
class ChessWall extends StatelessWidget {
  final List<MoveRecord> history;
  final double cellSize;
  final GameTheme theme;

  const ChessWall({
    super.key,
    required this.history,
    required this.cellSize,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final distance = cellSize * 1.25;
    // 墙壁圆角半径：随 cellSize 缩放，但限制在 2-4 范围内
    final wallRadius = (cellSize * 0.06).clamp(2.0, 4.0);
    // 边框宽度等价偏移，随 cellSize 缩放
    final borderOffset = (cellSize * 0.03).clamp(1.5, 3.0);

    final children = <Widget>[];

    for (final record in history) {
      if (!record.isWall || record.orientation == null) continue;

      final isHorizontal = record.orientation == WallOrientation.horizontal;

      // Swift ChessWall.swift:22-23 原公式：
      //   横墙: left = distance * x + cellSize + (-cellSize) - 2 = distance * x - 2
      //          top = distance * y + cellSize + 0 - 2          = distance * y + cellSize - 2
      //   竖墙: left = distance * x + cellSize + 0 - 2          = distance * x + cellSize - 2
      //          top = distance * y + cellSize + (-cellSize) - 2 = distance * y - 2
      final left = record.x * distance + (isHorizontal ? -borderOffset : cellSize - borderOffset);
      final top = record.y * distance + (isHorizontal ? cellSize - borderOffset : -borderOffset);

      final wallWidth = isHorizontal
          ? cellSize * 2.25 + borderOffset * 2
          : cellSize * 0.25 + borderOffset * 2;
      final wallHeight = isHorizontal
          ? cellSize * 0.25 + borderOffset * 2
          : cellSize * 2.25 + borderOffset * 2;

      final wallColor = record.isTopPlayer
          ? GameTheme.topWall
          : GameTheme.bottomWall;

      children.add(Positioned(
        left: left,
        top: top,
        child: Container(
          width: wallWidth,
          height: wallHeight,
          decoration: BoxDecoration(
            color: wallColor,
            borderRadius: BorderRadius.circular(wallRadius),
            boxShadow: [
              BoxShadow(
                color: wallColor.withValues(alpha: 0.3),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ));
    }

    return Stack(children: children);
  }
}
