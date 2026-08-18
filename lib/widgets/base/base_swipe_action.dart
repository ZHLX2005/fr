// Layer 4: BaseSwipeAction 原子组件。
//
// 80px 宽的滑动操作按钮：纯色背景 + 白字 + icon。
// [leftRounded] 把最左按钮嵌进卡片右圆角。

import 'package:flutter/material.dart';

class BaseSwipeAction extends StatelessWidget {
  const BaseSwipeAction({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.leftRounded = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool leftRounded;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: leftRounded
              ? const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  bottomLeft: Radius.circular(6),
                )
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.surface, size: 22),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(color: Theme.of(context).colorScheme.surface, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}