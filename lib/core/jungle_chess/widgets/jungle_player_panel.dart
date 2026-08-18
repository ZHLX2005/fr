// lib/core/jungle_chess/widgets/jungle_player_panel.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../constants/jungle_constants.dart';
import '../models/piece.dart';

/// 单侧玩家面板（热座对称布局的上/下两块）。
///
/// 「轮到谁走」由面板自身表达：当前回合方描边加粗 + 淡色底 + 「走棋中」标识，
/// 非当前方整体降透明度。所以页面不再需要单独一条顶部回合卡。
///
/// [rotated] 为 true 时整块面板旋转 180°，给坐在棋盘另一头的玩家正向阅读，
/// 面板内的悔棋按钮也跟着转过去 —— 两侧玩家都能读懂、都够得着自己的操作。
class JunglePlayerPanel extends StatelessWidget {
  final PlayerColor color;

  /// 是否旋转 180°（上方玩家传 true）
  final bool rotated;

  /// 是否轮到该方走棋
  final bool isCurrent;

  /// 该方存活棋子数
  final int aliveCount;

  /// 该方已吃掉的对方棋子数
  final int capturedCount;

  /// 悔棋回调；为 null 表示当前不可悔棋（置灰）
  final VoidCallback? onUndo;

  const JunglePlayerPanel({
    super.key,
    required this.color,
    required this.isCurrent,
    required this.aliveCount,
    required this.capturedCount,
    this.rotated = false,
    this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final tint = playerTint(color);

    final panel = Container(
      height: kPanelHeight,
      margin: const EdgeInsets.symmetric(horizontal: kPanelHMargin),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: isCurrent ? tint.withValues(alpha: 0.08) : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(kPanelRadius),
        border: Border.all(
          color: isCurrent ? tint.withValues(alpha: 0.55) : kPanelBorder(context),
          width: isCurrent ? 2 : 1,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: tint.withValues(alpha: 0.18),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // 玩家色圆点
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint,
              boxShadow: isCurrent
                  ? [BoxShadow(color: tint.withValues(alpha: 0.6), blurRadius: 8)]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                playerName(color),
                style: TextStyle(
                  color: isCurrent ? tint : kTextNormal(context),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            _Badge(label: '走棋中', tint: tint),
          ],
          const Spacer(),
          _Stat(icon: Icons.pets_rounded, value: aliveCount, tint: tint),
          const SizedBox(width: 10),
          _Stat(
            icon: Icons.restaurant_rounded,
            value: capturedCount,
            tint: kTextMuted(context),
          ),
          const SizedBox(width: 6),
          _UndoButton(tint: tint, onTap: onUndo),
        ],
      ),
    );

    final faded = isCurrent
        ? panel
        : Opacity(opacity: kPanelIdleOpacity, child: panel);

    if (!rotated) return faded;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.rotationZ(math.pi),
      child: faded,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color tint;
  const _Badge({required this.label, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: tint,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 图标 + 数字统计（存活子数 / 已吃子数）
class _Stat extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color tint;
  const _Stat({required this.icon, required this.value, required this.tint});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: tint),
        const SizedBox(width: 3),
        Text(
          '$value',
          style: TextStyle(
            color: tint,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _UndoButton extends StatelessWidget {
  final Color tint;
  final VoidCallback? onTap;
  const _UndoButton({required this.tint, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      tooltip: '悔棋',
      icon: Icon(
        Icons.undo_rounded,
        size: 20,
        color: enabled ? tint : kTextMuted(context).withValues(alpha: 0.5),
      ),
    );
  }
}
