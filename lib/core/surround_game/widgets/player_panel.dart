// lib/core/surround_game/widgets/player_panel.dart
//
// 操作栏：仿首页底部导航条风格 — Card 药丸形圆角 + elevation
import 'package:flutter/material.dart';
import '../game_ui_state.dart';
import '../game_theme.dart';
import '../surround_game_constants.dart';

/// 玩家操作栏 — 走棋/放墙切换 | 步数 | 剩余木板
///
/// [isTop] 标识此面板属于哪个玩家，显示对应玩家的步数和木板数。
/// 样式参考 xiaodouzi_bottom_bar.dart 的 Card+pill 风格。
class PlayerPanel extends StatelessWidget {
  final GameController notifier;
  final bool rotated;
  final bool active;
  final bool isTop;

  const PlayerPanel({
    super.key,
    required this.notifier,
    this.rotated = false,
    this.active = true,
    this.isTop = true,
  });

  @override
  Widget build(BuildContext context) {
    final ui = notifier.state;
    final gs = ui.gameState;
    final theme = const GameTheme();

    // 确认阶段：当前回合玩家的面板变成 取消/确定
    if (ui.phase == TouchPhase.confirming && isTop == gs.currentPlayerIsTop) {
      return _buildConfirmPanel(theme);
    }

    final opacity = active ? 1.0 : 0.4;
    final isMoveMode = ui.mode == GameMode.move;
    final canWall = ui.canPlaceWall;

    // 本玩家的步数 = history 中 isTopPlayer 匹配的条目数
    final playerSteps = gs.history.where((r) => r.isTopPlayer == isTop).length;

    // 本玩家的剩余木板
    final wallsPlaced = isTop ? gs.topWallsPlaced : gs.bottomWallsPlaced;
    final playerWalls = SurroundGameConstants.wallCountPerPlayer - wallsPlaced;

    // 只有当前回合且在同一面板上时，模式切换按钮才显示在 active 面板中
    final showModeButton = active && isTop == gs.currentPlayerIsTop;

    const barHeight = 48.0;
    const barWidth = 280.0;

    final panel = Opacity(
      opacity: opacity,
      child: SizedBox(
        width: barWidth,
        height: barHeight,
        child: Card(
          elevation: 2,
          margin: EdgeInsets.zero,
          color: theme.panelBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(barHeight / 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showModeButton)
                _ModeButton(
                  isMoveMode: isMoveMode,
                  canWall: canWall,
                  onTap: () => notifier.toggleMode(),
                  theme: theme,
                ),
              if (!showModeButton) const SizedBox(width: 8),
              _PanelButton(
                label: '$playerSteps',
                sub: '步数',
                theme: theme,
              ),
              const SizedBox(width: 8),
              _PanelButton(
                label: '$playerWalls',
                sub: '木板',
                theme: theme,
              ),
            ],
          ),
        ),
      ),
    );

    if (rotated) {
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationZ(3.14159),
        child: panel,
      );
    }
    return panel;
  }

  /// 确认阶段面板 — 取消 / 旋转(墙) / 确定
  Widget _buildConfirmPanel(GameTheme theme) {
    const barHeight = 48.0;
    const barWidth = 280.0;
    final isMove = notifier.state.pendingTargetCellId != null;
    final isHorizontal = notifier.state.pendingWall?.o == WallOrientation.horizontal;

    final panel = SizedBox(
      width: barWidth,
      height: barHeight,
      child: Card(
        elevation: 2,
        margin: EdgeInsets.zero,
        color: theme.panelBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(barHeight / 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 取消
            GestureDetector(
              onTap: () => notifier.cancelAction(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.close, size: 18, color: theme.btnText),
                    Text('取消',
                      style: TextStyle(fontSize: 8, color: theme.btnSub)),
                  ],
                ),
              ),
            ),
            Container(
              width: 1,
              height: 24,
              color: theme.btnBorder.withValues(alpha: 0.3),
            ),
            // 旋转（仅墙模式）
            if (!isMove)
              GestureDetector(
                onTap: () => notifier.rotatePendingWall(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isHorizontal ? Icons.swap_horiz : Icons.swap_vert,
                        size: 18,
                        color: GameTheme.topPlayer,
                      ),
                      Text('旋转',
                        style: TextStyle(
                          fontSize: 8,
                          color: GameTheme.topPlayer,
                          fontWeight: FontWeight.w600,
                        )),
                    ],
                  ),
                ),
              ),
            // 确定
            GestureDetector(
              onTap: () => notifier.confirmAction(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, size: 18,
                      color: GameTheme.topPlayer),
                    Text('确定',
                      style: TextStyle(
                        fontSize: 8,
                        color: GameTheme.topPlayer,
                        fontWeight: FontWeight.w600,
                      )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (rotated) {
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationZ(3.14159),
        child: panel,
      );
    }
    return panel;
  }
}

/// 模式切换按钮 — 药丸内纯文字，无独立边框
class _ModeButton extends StatelessWidget {
  final bool isMoveMode;
  final bool canWall;
  final VoidCallback? onTap;
  final GameTheme theme;

  const _ModeButton({
    required this.isMoveMode,
    required this.canWall,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final icon = isMoveMode ? Icons.near_me : Icons.dashboard;
    final sub = isMoveMode ? '走棋' : '放墙';
    final isActive = isMoveMode || canWall;

    return GestureDetector(
      onTap: isActive ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
              size: 18,
              color: theme.btnText,
            ),
            Text(sub,
              style: TextStyle(
                fontSize: 8,
                color: isActive ? theme.btnSub : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 信息显示按钮 — 纯文字无边框
class _PanelButton extends StatelessWidget {
  final String label;
  final String sub;
  final GameTheme theme;

  const _PanelButton({
    required this.label,
    required this.sub,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.btnText,
            ),
          ),
          Text(sub,
            style: TextStyle(fontSize: 8, color: theme.btnSub),
          ),
        ],
      ),
    );
  }
}
