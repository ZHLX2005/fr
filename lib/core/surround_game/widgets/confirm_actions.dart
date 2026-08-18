// lib/core/surround_game/widgets/confirm_actions.dart
//
// 确认操作按钮 — 直接显示在棋子/墙放下位置
//
// 设计理念：视线不跳跃，手指不移位，就地确认。
// 边界保护：底行/顶行时按钮收紧到 cell 内部，避免溢出棋盘网格。
// 边界保护：按钮始终在棋盘内，必要时自动翻转定位。
import 'package:flutter/material.dart';
import '../board_theme.dart';
import '../surround_game_constants.dart';
import 'touch_controller.dart';

/// 确认操作按钮组 — 就地确认（✓/✘）
///
/// 在棋子/墙放下位置直接显示确认按钮，消除视线跳跃。
/// 具备边界保护：按钮始终在棋盘内，必要时自动翻转到可见侧。
///
/// 纯展示组件：所有状态通过构造函数传入，操作通过回调回调。
class ConfirmActions extends StatelessWidget {
  final TouchPhase phase;
  final int? pendingTargetCellId;
  final ({int x, int y, WallOrientation o})? pendingWall;
  final bool isTopTurn;
  final double cellSize;
  final double boardSize;
  final BoardThemeData theme;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onRotate; // 仅在 pendingWall 非空时有效

  const ConfirmActions({
    super.key,
    required this.phase,
    required this.pendingTargetCellId,
    required this.pendingWall,
    required this.isTopTurn,
    required this.cellSize,
    required this.boardSize,
    required this.theme,
    required this.onConfirm,
    required this.onCancel,
    this.onRotate,
  });

  @override
  Widget build(BuildContext context) {
    if (phase != TouchPhase.confirming) return const SizedBox.shrink();

    final distance = cellSize * 1.25;
    const buttonSize = 44.0;
    const buttonGap = 12.0;
    final rowWidth = buttonSize * 2 + buttonGap; // 100
    // 棋盘网格实际渲染高度 = 8 * distance = 10 * cellSize
    // boardSize 还包含外圈边距（cellSize*0.5），但 Stack 在棋盘 SizedBox 内
    // Positioned 超出 gridSize 会被外层 Stack 裁掉
    final gridSize = 8.0 * distance;

    // 棋子移动
    if (pendingTargetCellId != null) {
      final cellId = pendingTargetCellId!;
      final x = (cellId % 9).toDouble();
      final y = (cellId ~/ 9).toDouble();

      // 计算目标位置
      var left = x * distance + cellSize * 0.6;
      var top = y * distance + cellSize + 8;

      // 左右边界：按钮组不超出棋盘网格
      left = left.clamp(0.0, gridSize - rowWidth);
      // 底行：按钮下溢出 → 收紧到 cell 内偏下位置
      if (top + buttonSize > gridSize) {
        top = y * distance + cellSize * 0.45;
      } else if (top < 0) {
        // 顶行：按钮上溢出 → 收紧到 cell 内偏上位置
        top = y * distance + cellSize * 0.1;
      }

      return _buildButtons(left, top, false);
    }

    // 放墙
    if (pendingWall != null) {
      final w = pendingWall!;
      final isHorizontal = w.o == WallOrientation.horizontal;

      var left = w.x * distance + (isHorizontal ? cellSize * 0.4 : cellSize + 8);
      var top = w.y * distance + (isHorizontal ? cellSize + 8 : cellSize * 0.3);

      // 左右边界
      left = left.clamp(0.0, gridSize - rowWidth);
      // 顶/底边界
      if (top + buttonSize > gridSize) {
        top = w.y * distance + cellSize * 0.1;
      } else if (top < 0) {
        top = w.y * distance + cellSize * 0.45;
      }

      return _buildButtons(left, top, true);
    }

    return const SizedBox.shrink();
  }

  Widget _buildButtons(double left, double top, bool isWall) {
    return Positioned(
      left: left,
      top: top,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 取消按钮
          _ActionButton(
            icon: Icons.close,
            color: Colors.red.withValues(alpha: 0.85),
            onTap: onCancel,
            // isTopTurn 标志是否需要翻转图标方向
            // false=bottom player视角, true=top player视角（已经翻转过）
            needsFlip: isTopTurn,
          ),
          const SizedBox(width: 12),
          // 确定按钮
          _ActionButton(
            icon: Icons.check,
            color: theme.piecePlayerA,
            onTap: onConfirm,
            needsFlip: isTopTurn,
          ),
        ],
      ),
    );
  }
}

/// 单个操作按钮
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool needsFlip;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.needsFlip,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: needsFlip
            ? Transform.flip(
                flipX: true,
                child: Icon(
                  icon,
                  size: 24,
                  color: Colors.white,
                ),
              )
            : Icon(
                icon,
                size: 24,
                color: Colors.white,
              ),
      ),
    );
  }
}
