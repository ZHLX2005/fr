// lib/core/surround_game/widgets/player_panel.dart
//
// 操作栏：仿首页底部导航条风格 — Card 药丸形圆角 + elevation
//
// 颜色全部从 [BoardThemeData] 语义令牌读取，主题切换只改令牌。
import 'package:flutter/material.dart';
import '../board_theme.dart';
import '../surround_game_constants.dart';
import 'touch_controller.dart';

/// 玩家操作栏尺寸令牌
///
/// 普通面板 / 确认面板 / 模式按钮共用同一组尺寸，
/// 避免散落硬编码。放大后触摸目标全部 ≥ 44pt 安全区。
class _PanelMetrics {
  static const double height = 64.0; // 48 → 64
  static const double width = 340.0; // 280 → 340（仍小于棋盘全宽）
  static const double radius = height / 2; // 完美药丸：圆角 = 高度 / 2

  static const double segPadH = 14.0; // 段内水平 padding 6 → 14
  static const double segGap = 8.0; // 段间留白
  static const double segInnerRadius = 18.0; // active 胶囊圆角

  static const double iconSize = 24.0; // 18 → 24
  static const double numSize = 22.0; // 14 → 22
  static const double subSize = 11.0; // 8 → 11

  static const double dividerHeight = 30.0; // 24 → 30
  static const double dividerWidth = 1.0;
}

/// 玩家操作栏 — 走棋/放墙切换 | 步数 | 剩余木板
///
/// [isTop] 标识此面板属于哪个玩家，显示对应玩家的步数和木板数。
/// 样式参考 xiaodouzi_bottom_bar.dart 的 Card+pill 风格。
///
/// 纯展示组件：所有状态通过构造函数传入，操作通过回调回调。
class PlayerPanel extends StatelessWidget {
  final bool rotated;
  final bool active;
  final bool isTop;
  final GameMode mode;
  final TouchPhase phase;
  final bool canPlaceWall;
  final int playerSteps;
  final int remainingWalls;
  final bool canRequestUndo;
  final VoidCallback? onToggleMode;
  final VoidCallback? onUndoRequest;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final VoidCallback? onRotate;
  final ({int x, int y, WallOrientation o})? pendingWall;

  const PlayerPanel({
    super.key,
    this.rotated = false,
    this.active = true,
    this.isTop = true,
    required this.mode,
    required this.phase,
    required this.canPlaceWall,
    required this.playerSteps,
    required this.remainingWalls,
    required this.canRequestUndo,
    this.onToggleMode,
    this.onUndoRequest,
    this.onConfirm,
    this.onCancel,
    this.onRotate,
    this.pendingWall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);

    // 确认阶段：当前回合玩家的面板变成 取消/旋转/确定
    if (phase == TouchPhase.confirming && active) {
      return _buildConfirmPanel(theme);
    }

    final opacity = active ? 1.0 : 0.4;

    // 只有当前回合且在同一面板上时，模式切换按钮才显示在 active 面板中
    final showModeButton = active;

    // 渐变色：基于 panelBg 上下浮动 6%，保持换肤一致性
    final bg = theme.panelBg;
    final bgTop = Color.lerp(bg, Colors.white, 0.06)!;
    final bgBottom = Color.lerp(bg, Colors.black, 0.06)!;
    // active 模式按钮的橙色胶囊
    final activeCapsule = theme.piecePlayerA.withValues(alpha: 0.16);

    final panel = Opacity(
      opacity: opacity,
      child: SizedBox(
        width: _PanelMetrics.width,
        height: _PanelMetrics.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bgTop, bg, bgBottom],
            ),
            borderRadius: BorderRadius.circular(_PanelMetrics.radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            boxShadow: [
              // 顶部 inset 高光
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.6),
                blurRadius: 0,
                spreadRadius: 0,
                offset: const Offset(0, 1),
              ),
              // 主体柔投影
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
              // 近距硬投影
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showModeButton) ...[
                _ModeSegmentedBar(
                  mode: mode,
                  canWall: canPlaceWall,
                  onToggle: onToggleMode ?? () {},
                  theme: theme,
                  activeCapsule: activeCapsule,
                ),
                const SizedBox(width: _PanelMetrics.segGap),
                _PanelDivider(theme: theme),
                const SizedBox(width: _PanelMetrics.segGap),
              ],
              _PanelButton(
                label: '$playerSteps',
                sub: '步数',
                theme: theme,
              ),
              const SizedBox(width: _PanelMetrics.segGap),
              _PanelDivider(theme: theme),
              const SizedBox(width: _PanelMetrics.segGap),
              _PanelButton(
                label: '$remainingWalls',
                sub: '木板',
                theme: theme,
              ),
              const SizedBox(width: _PanelMetrics.segGap),
              _PanelDivider(theme: theme),
              const SizedBox(width: _PanelMetrics.segGap),
              _UndoButton(
                enabled: canRequestUndo,
                onTap: onUndoRequest,
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
  Widget _buildConfirmPanel(BoardThemeData theme) {
    // 确认阶段强调色 — 始终用玩家 A 主题色（当前回合玩家在 UI 上为上方面板）
    final accent = theme.piecePlayerA;

    // 渐变 + 双层投影，与普通面板一致
    final bg = theme.panelBg;
    final bgTop = Color.lerp(bg, Colors.white, 0.06)!;
    final bgBottom = Color.lerp(bg, Colors.black, 0.06)!;

    // pendingWall 非空 → 这是墙模式确认（显示旋转按钮）
    final showRotate = pendingWall != null;
    final rotateIcon = pendingWall?.o == WallOrientation.horizontal
        ? Icons.swap_horiz
        : Icons.swap_vert;

    final panel = SizedBox(
      width: _PanelMetrics.width,
      height: _PanelMetrics.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgTop, bg, bgBottom],
          ),
          borderRadius: BorderRadius.circular(_PanelMetrics.radius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.6),
              offset: const Offset(0, 1),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 取消
            _ConfirmButton(
              icon: Icons.close,
              label: '取消',
              iconColor: theme.btnText,
              labelColor: theme.btnSub,
              onTap: onCancel ?? () {},
            ),
            const SizedBox(width: _PanelMetrics.segGap),
            _PanelDivider(theme: theme),
            const SizedBox(width: _PanelMetrics.segGap),
            // 旋转（仅墙模式）
            if (showRotate) ...[
              _ConfirmButton(
                icon: rotateIcon,
                label: '旋转',
                iconColor: accent,
                labelColor: accent,
                onTap: onRotate ?? () {},
              ),
              const SizedBox(width: _PanelMetrics.segGap),
              _PanelDivider(theme: theme),
              const SizedBox(width: _PanelMetrics.segGap),
            ],
            // 确定
            _ConfirmButton(
              icon: Icons.check_circle,
              label: '确定',
              iconColor: accent,
              labelColor: accent,
              onTap: onConfirm ?? () {},
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

/// 模式分段切换条 — 走棋/放墙 同时可见，当前模式高亮胶囊（导航栏式）。
///
/// 替代旧的单按钮 [_ModeButton]：两个段始终可见，选中段填充 [activeCapsule]
/// 并使用 [BoardThemeData.btnText]，未选中段透明、使用 [BoardThemeData.btnSub]。
/// 仅当前回合（active）面板渲染。
class _ModeSegmentedBar extends StatelessWidget {
  final GameMode mode;
  final bool canWall;
  final VoidCallback onToggle;
  final BoardThemeData theme;
  final Color activeCapsule;

  const _ModeSegmentedBar({
    required this.mode,
    required this.canWall,
    required this.onToggle,
    required this.theme,
    required this.activeCapsule,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.btnBg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(_PanelMetrics.segInnerRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeSegment(
            icon: Icons.near_me,
            label: '走棋',
            selected: mode == GameMode.move,
            enabled: true,
            onTap: mode == GameMode.move ? null : onToggle,
            theme: theme,
            activeCapsule: activeCapsule,
          ),
          const SizedBox(width: 4),
          _ModeSegment(
            icon: Icons.dashboard,
            label: '放墙',
            selected: mode == GameMode.placeWall,
            enabled: canWall,
            onTap: (mode != GameMode.placeWall && canWall) ? onToggle : null,
            theme: theme,
            activeCapsule: activeCapsule,
          ),
        ],
      ),
    );
  }
}

/// 单个模式段 — 选中态填充 [activeCapsule]，未选中透明。
class _ModeSegment extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final BoardThemeData theme;
  final Color activeCapsule;

  const _ModeSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.theme,
    required this.activeCapsule,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? theme.btnText
        : (enabled ? theme.btnSub : theme.btnSub.withValues(alpha: 0.4));
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? activeCapsule : Colors.transparent,
          borderRadius: BorderRadius.circular(_PanelMetrics.segInnerRadius - 4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: _PanelMetrics.iconSize, color: color),
            Text(label,
              style: TextStyle(
                fontSize: _PanelMetrics.subSize,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 悔棋按钮 — 始终渲染（双方胶囊都有），仅图标；不可请求时置灰禁用。
///
/// 启用态使用 [BoardThemeData.btnText]，禁用态 [BoardThemeData.btnSub]
/// 并叠加 [Opacity] + [IgnorePointer]，使其明显"惰性"。
class _UndoButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;
  final BoardThemeData theme;

  const _UndoButton({
    required this.enabled,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 30,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.undo,
                  size: _PanelMetrics.iconSize,
                  color: enabled ? theme.btnText : theme.btnSub,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 信息显示按钮 — 放大后的数字 + 副标
class _PanelButton extends StatelessWidget {
  final String label;
  final String sub;
  final BoardThemeData theme;

  const _PanelButton({
    required this.label,
    required this.sub,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _PanelMetrics.segPadH),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
            style: TextStyle(
              fontSize: _PanelMetrics.numSize,
              fontWeight: FontWeight.w700,
              color: theme.btnText,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(sub,
            style: TextStyle(fontSize: _PanelMetrics.subSize, color: theme.btnSub),
          ),
        ],
      ),
    );
  }
}

/// 确认阶段图标按钮 — 复用放大后的尺寸
class _ConfirmButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color labelColor;
  final VoidCallback onTap;

  const _ConfirmButton({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _PanelMetrics.segPadH),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: _PanelMetrics.iconSize, color: iconColor),
            const SizedBox(height: 2),
            Text(label,
              style: TextStyle(
                fontSize: _PanelMetrics.subSize,
                color: labelColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 段间细分隔线
class _PanelDivider extends StatelessWidget {
  final BoardThemeData theme;
  const _PanelDivider({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _PanelMetrics.dividerWidth,
      height: _PanelMetrics.dividerHeight,
      color: theme.btnBorder.withValues(alpha: 0.3),
    );
  }
}
