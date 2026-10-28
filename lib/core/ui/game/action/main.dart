// game/action —— 联机对局底部动作件（2026-10-28 自 3 个 lua demo 抽离）。
//
// 三个 lua 联机游戏（go / gomoku / surround_game）的对局页底部动作行各抄了一份
// 逐字相同的「图标 + 文案」按钮：图标 14px、间距 4px、文字 12px，颜色取棋盘主题
// 的 btnText，禁用态降到 25% 透明。属联机游戏域的通用形态 → 落 ui/game/action/。

import 'package:flutter/material.dart';

/// 对局页底部动作按钮：图标 + 文案，禁用态自动降透明度。
class GameBottomAction extends StatelessWidget {
  const GameBottomAction({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  /// 动作图标。
  final IconData icon;

  /// 动作文案。
  final String label;

  /// 主色（通常取棋盘主题的 btnText）；禁用时自动降透明度。
  final Color color;

  /// 点击回调；null = 禁用态。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color.withValues(alpha: onTap != null ? 0.6 : 0.25);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }
}
