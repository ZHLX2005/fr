import 'package:flutter/material.dart';
import '../../surround_game_constants.dart';

/// 方向控制按键
///
/// 十字布局：上/左/右/下 四个圆角按钮
class DirectionPad extends StatelessWidget {
  final void Function(Direction direction)? onDirection;
  final double size;

  const DirectionPad({super.key, this.onDirection, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final btnSize = size;
    final theme = Theme.of(context);

    return SizedBox(
      width: btnSize * 3,
      height: btnSize * 3,
      child: Stack(
        children: [
          // 上
          Positioned(
            top: 0,
            left: btnSize,
            child: _DirButton(
              icon: Icons.arrow_upward,
              size: btnSize,
              color: theme.colorScheme.primary,
              onTap: () => onDirection?.call(Direction.up),
            ),
          ),
          // 左
          Positioned(
            top: btnSize,
            left: 0,
            child: _DirButton(
              icon: Icons.arrow_back,
              size: btnSize,
              color: theme.colorScheme.primary,
              onTap: () => onDirection?.call(Direction.left),
            ),
          ),
          // 右
          Positioned(
            top: btnSize,
            left: btnSize * 2,
            child: _DirButton(
              icon: Icons.arrow_forward,
              size: btnSize,
              color: theme.colorScheme.primary,
              onTap: () => onDirection?.call(Direction.right),
            ),
          ),
          // 下
          Positioned(
            top: btnSize * 2,
            left: btnSize,
            child: _DirButton(
              icon: Icons.arrow_downward,
              size: btnSize,
              color: theme.colorScheme.primary,
              onTap: () => onDirection?.call(Direction.down),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback onTap;

  const _DirButton({
    required this.icon,
    required this.size,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(size / 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 3),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: size * 0.45),
        ),
      ),
    );
  }
}
