import 'package:flutter/material.dart';
import '../board_theme.dart';
import '../models/game_state.dart';
import '../surround_game_constants.dart';

/// 墙壁渲染组件 — 简洁版
///
/// 遍历 [MoveRecord] 历史中所有墙壁放置记录，将其渲染为
/// 水平或垂直方向的简洁条状方块。
///
/// 视觉拆解（每块墙由 2 层叠成）：
///   1. drop shadow   — 下方柔影
///   2. solid body   — 纯色主体（wallPlayerA/wallPlayerB）
///   3. inner edge    — 极淡的白色内描边
///
/// 颜色全部从 [BoardThemeData] 语义令牌读取。

/// 墙壁渲染层
class ChessWall extends StatelessWidget {
  final List<MoveRecord> history;
  final double cellSize;
  final BoardThemeData theme;

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

      // 从语义令牌里取双方各自的颜色
      final baseColor = record.isTopPlayer
          ? theme.wallPlayerA
          : theme.wallPlayerB;

      children.add(Positioned(
        left: left,
        top: top,
        child: Container(
          width: wallWidth,
          height: wallHeight,
          decoration: BoxDecoration(
            // Layer 1 — 纯色主体
            color: baseColor,
            borderRadius: BorderRadius.circular(wallRadius),
            // Layer 0 — 投影：简单柔和的阴影
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
            // Layer 2 — 极淡的白色内描边
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1.0,
            ),
          ),
        ),
      ));
    }

    return Stack(children: children);
  }
}
