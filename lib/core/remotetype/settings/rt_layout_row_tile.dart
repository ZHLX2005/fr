// lib/core/remotetype/settings/rt_layout_row_tile.dart
//
// 大卡里的一行：把手 + 图标 + 名字 + 标签 + ⋯ + 激活态。
//
// 与卡片分开：这个行只关心「怎么画一行」，不管它属于哪一组、点了做什么。

import 'package:flutter/material.dart';

import '../../theme/context/colors.dart';
import '../data/rt_prefs.dart' show RtCanvasNamedLayout, RtLayoutKind;

class RtLayoutRowTile extends StatelessWidget {
  const RtLayoutRowTile({
    super.key,
    required this.entry,
    required this.index,
    required this.showTopBorder,
    required this.isActive,
    required this.onSwitch,
    this.onMore,
  });

  final RtCanvasNamedLayout entry;

  /// 组内序号（ReorderableDragStartListener 用）。
  final int index;

  /// 行顶部分隔线（组内第二行起）。
  final bool showTopBorder;

  /// 该朝向正被这张布局使用。
  final bool isActive;

  /// 点行 = 切该组激活。
  final VoidCallback onSwitch;

  /// ⋯ 管理入口；固定布局（写字）为 null——不可编排，标「固定」即可。
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final isWriter = entry.kind == RtLayoutKind.writer;
    return InkWell(
      onTap: onSwitch,
      child: Container(
        height: 48,
        padding: const EdgeInsets.fromLTRB(2, 0, 8, 0),
        decoration: showTopBorder
            ? BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
              )
            : null,
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 8,
                ),
                child: Icon(
                  Icons.drag_indicator,
                  size: 20,
                  color: c.textMuted.withValues(alpha: 0.7),
                ),
              ),
            ),
            Icon(
              isWriter
                  ? Icons.keyboard_alt_outlined
                  : Icons.dashboard_customize_outlined,
              size: 21,
              color: isActive ? cs.primary : c.textMuted,
            ),
            const SizedBox(width: 10),
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
            if (!entry.editable)
              const RtRowBadge(label: '固定')
            else if (entry.builtIn)
              const RtRowBadge(label: '内置')
            else
              const RtRowBadge(label: '自定义'),
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

/// 行尾小徽：固定 / 内置 / 自定义；菜单里也用作朝向徽（accent）。
class RtRowBadge extends StatelessWidget {
  const RtRowBadge({super.key, required this.label, this.accent = false});

  final String label;

  /// true = 主题色徽（菜单里的朝向）；false = 中性徽（内置/固定/自定义）。
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
          color: accent ? cs.onPrimaryContainer : c.textMuted,
        ),
      ),
    );
  }
}
