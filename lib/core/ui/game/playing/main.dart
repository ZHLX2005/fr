// game/playing —— 联机对局中页面外壳（2026-10-28 自 go/gomoku 两个 lua demo 抽离）。
//
// 两个 demo 的 _buildPlaying() 外壳逐字相同：Scaffold（棋盘主题底色）+ SafeArea +
// 纵向四段（顶部回合条 / 棋盘区 / 待确认槽 / 连接条）+ 底部动作条。差异只在
// 棋盘 widget、回合条内容与可用动作项 —— 故外壳抽到此处，游戏私有部分走插槽。
//
// 依赖方向：ui/game/playing → ui/global/*（共享件）。

import 'package:flutter/material.dart';

import '../action/main.dart';

/// 底部动作项：图标 + 文案 + 点击回调（null = 禁用）。
class GamePlayingAction {
  const GamePlayingAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

/// 对局中页面外壳：顶部条 + 棋盘区 + 待确认槽 + 连接条 + 底部动作条。
class GamePlayingScaffold extends StatelessWidget {
  const GamePlayingScaffold({
    super.key,
    required this.backgroundColor,
    required this.turnBar,
    required this.board,
    required this.confirmSlot,
    required this.actions,
    required this.actionColor,
    this.connectionBar,
  });

  /// 页面底色（通常取棋盘主题的 boardSurface）。
  final Color backgroundColor;

  /// 顶部回合状态条。
  final Widget turnBar;

  /// 棋盘区；回调收到画布约束，棋盘据此换算格距。
  final Widget Function(BuildContext context, BoxConstraints constraints) board;

  /// 待确认槽（固定占位，避免出现/消失撑动棋盘）。
  final Widget confirmSlot;

  /// 底部动作项。
  final List<GamePlayingAction> actions;

  /// 底部动作项的主色（棋盘主题的 btnText）。
  final Color actionColor;

  /// 连接状态条（relay 房间页）。
  final Widget? connectionBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            turnBar,
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) => board(context, constraints),
                ),
              ),
            ),
            confirmSlot,
            if (connectionBar != null) connectionBar!,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 16),
                    GameBottomAction(
                      icon: actions[i].icon,
                      label: actions[i].label,
                      color: actionColor,
                      onTap: actions[i].onTap,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
