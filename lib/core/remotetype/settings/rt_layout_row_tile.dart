// lib/core/remotetype/settings/rt_layout_row_tile.dart
//
// 大卡里的一行：把手 + 图标井 + 名字 + 标签 + ⋯ + 激活态。
//
// 视觉（C 形态定稿）：激活行不整行染色——激活的图标进 primaryContainer
// 圆角井、名称转 primary/w700、✓ 实心；色彩只用于标出当前在用的布局。

import 'package:flutter/material.dart';

import '../../theme/context/colors.dart';
import '../data/rt_prefs.dart' show RtCanvasNamedLayout, RtLayoutKind;

class RtLayoutRowTile extends StatelessWidget {
  const RtLayoutRowTile({
    super.key,
    required this.entry,
    required this.index,
    required this.isActive,
    required this.onSwitch,
    this.onMore,
  });

  final RtCanvasNamedLayout entry;

  /// 组内序号（ReorderableDragStartListener 用）。
  final int index;

  /// 该朝向正被这张布局使用。
  final bool isActive;

  /// 点行 = 切该组激活。
  final VoidCallback onSwitch;

  /// ⋯ 管理入口；固定布局（写字）为 null——不可编排（无菜单项可给）。
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final isWriter = entry.kind == RtLayoutKind.writer;
    return InkWell(
      onTap: onSwitch,
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              // 把手只负责拖：吞掉点按，避免「点了把手却切了布局」。
              child: GestureDetector(
                onTap: () {},
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 19,
                    color: c.textMuted.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
            // 图标井：激活 = primaryContainer + primary 图标；非激活 = 极浅灰井。
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: isActive
                    ? cs.primaryContainer
                    : cs.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                isWriter
                    ? Icons.keyboard_alt_outlined
                    : Icons.dashboard_customize_outlined,
                size: 18,
                color: isActive ? cs.primary : c.textMuted,
              ),
            ),
            Expanded(
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? cs.primary : c.text,
                ),
              ),
            ),
            if (!entry.builtIn) const RtRowBadge(label: '自定义'),
            if (onMore != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '管理',
                icon: Icon(Icons.more_horiz, size: 20, color: c.textMuted),
                onPressed: onMore,
              )
            else
              const SizedBox(width: 10),
            Icon(
              isActive ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: isActive
                  ? cs.primary
                  : c.textMuted.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}

/// 行尾小徽：仅自定义布局有（primaryContainer + primary）；内置/固定不带标识。
class RtRowBadge extends StatelessWidget {
  const RtRowBadge({super.key, required this.label, this.accent = false});

  final String label;

  /// true = 主题色徽（自定义）。
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: accent ? FontWeight.w600 : FontWeight.w500,
          color: accent ? cs.primary : c.textMuted,
        ),
      ),
    );
  }
}
