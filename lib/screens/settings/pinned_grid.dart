// 设置页 · 钉选网格（拖动排序 + 拖入垃圾桶删除）。
//
// 单一拖拽模式：长按格子拖动（原手感，200ms）。
//   · 松手在网格 → 换位排序（ReorderableBuilder 原路）；
//   · 松手在垃圾桶（屏幕底部投放条）→ 直接删除（无确认，removePin 保底 ≥1 条）。
// 两者落点不同，互不冲突。
//
// 删除/换位时序冲突的解法：onReorder 见「当前 provider 列表已比拖起时短」
// 直接跳过本次重排，避免把已删 id 写回。垃圾桶是宿主 (AppSettingsPage)
// 的页面级浮层（不进 Scaffold FAB 槽），本网格仅通过 onDraggingChanged
// 通知宿主显隐。
//
// data 传递靠包提供的 CustomDraggable（包内 Draggable 的 data 仅从
// CustomDraggable 读取，普通子节点恒 null，DragTarget 收不到候选）。
// 顶层 key 契约：itemBuilder 直接子节点必须带 ValueKey（CustomDraggable 承担）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_lifecycle/press_bounce_curve.dart';
import '../../core/nav/nav_catalog.dart';
import '../../core/nav/nav_pins_notifier.dart';
import '../../core/ui/shell/nav_entry_icon.dart';
import 'const_settings.dart';

class PinnedGrid extends ConsumerStatefulWidget {
  const PinnedGrid({
    super.key,
    required this.entries,
    required this.visibleSlotCount,
    required this.onDraggingChanged,
  });

  final List<NavEntry> entries;
  final int visibleSlotCount;

  /// 拖动开始/结束（宿主据此显隐屏幕底部垃圾桶 FAB）。
  final ValueChanged<bool> onDraggingChanged;

  @override
  ConsumerState<PinnedGrid> createState() => _PinnedGridState();
}

class _PinnedGridState extends ConsumerState<PinnedGrid> {
  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    if (entries.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            '还没有钉选任何入口',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return _SortableGrid(
      entries: entries,
      visibleSlotCount: widget.visibleSlotCount,
      onDragStarted: _handleDragStarted,
      onDragEnd: _handleDragEnd,
      onReorder: _handleReorder,
    );
  }

  void _handleDragStarted(int index) {
    HapticFeedback.lightImpact();
    widget.onDraggingChanged(true);
  }

  void _handleDragEnd(int index) {
    HapticFeedback.mediumImpact();
    widget.onDraggingChanged(false);
  }

  void _handleReorder(List<String> Function(List<String>) reorderFn) {
    final entriesIds = widget.entries.map((e) => e.id).toList();
    // 拖拽途中格子被垃圾桶删走 → provider 列表已比拖起时短。此时基于旧
    // entries 重排会把已删 id 写回，跳过本次 onReorder（列表保持删后状态）。
    if (ref.read(navPinsProvider).pinIds.length < entriesIds.length) return;
    ref
        .read(navPinsProvider.notifier)
        .setPins(
          // 必须用网格 children 同源的 entries 派生列表，保证与
          // reorderFn 的 index 逐位对齐（pinIds 里若有未解析 id，
          // entries 会比 pinIds 短，直接喂 pinIds 会错位重排）。
          reorderFn(entriesIds),
        );
  }
}

// ── 拖拽网格：ReorderableBuilder + CustomDraggable 携带 id ──────────────

class _SortableGrid extends ConsumerWidget {
  const _SortableGrid({
    required this.entries,
    required this.visibleSlotCount,
    required this.onDragStarted,
    required this.onDragEnd,
    required this.onReorder,
  });

  final List<NavEntry> entries;
  final int visibleSlotCount;
  final ItemCallback onDragStarted;
  final ItemCallback onDragEnd;
  final void Function(List<String> Function(List<String>)) onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: ReorderableBuilder<String>.builder(
        // 原长按手感（200ms）：区分点按打开 / 拖动，编辑弹窗同一参数。
        longPressDelay: kSettingsDragLongPressDelay,
        feedbackScaleFactor: kSettingsDragFeedbackScale,
        animationConfig: kSettingsDragConfig,
        dragChildBoxDecoration: settingsDragChildDecoration(cs.onSurface),
        onDragStarted: onDragStarted,
        // 跨格换位 tick（包契约：仅真正换位时回调，非逐帧）
        onUpdatedDraggedChild: (_) => HapticFeedback.selectionClick(),
        onDragEnd: onDragEnd,
        onReorder: onReorder,
        itemCount: entries.length,
        childBuilder: (itemBuilder) {
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: kSettingsCellCrossAxisCount,
              mainAxisSpacing: kSettingsCellSpacing,
              crossAxisSpacing: kSettingsCellSpacing,
              childAspectRatio: kSettingsCellAspectRatio,
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              return itemBuilder(
                // 顶层 key 契约放这里；data 让包内 Draggable 带上 id，
                // 垃圾桶 DragTarget<String> 才能接受候选。
                CustomDraggable(
                  key: ValueKey(entries[i].id),
                  data: entries[i].id,
                  child: _PinnedCell(
                    entry: entries[i],
                    isHome: i == 0,
                    inOverflow: i >= visibleSlotCount,
                    onTap: () {
                      Navigator.of(
                        context,
                      ).push(MaterialPageRoute(builder: entries[i].builder));
                    },
                  ),
                ),
                i,
              );
            },
          );
        },
      ),
    );
  }
}

// ── 已钉格子卡面 ────────────────────────────────────────────────────────

/// 已钉格子：surface 卡面 + 角标（首页 / ⋯ 槽位）；按压 iOS 弹性缩放。
class _PinnedCell extends StatefulWidget {
  const _PinnedCell({
    required this.entry,
    required this.isHome,
    required this.inOverflow,
    required this.onTap,
  });

  final NavEntry entry;
  final bool isHome;
  final bool inOverflow;
  final VoidCallback onTap;

  @override
  State<_PinnedCell> createState() => _PinnedCellState();
}

class _PinnedCellState extends State<_PinnedCell>
    with SingleTickerProviderStateMixin {
  static final Curve _pressCurve = const PressBounceCurve();

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    lowerBound: 0,
    upperBound: 1,
  );

  bool _pressed = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleHighlightChanged(bool down) {
    if (_pressed == down) return;
    setState(() => _pressed = down);
    if (down) {
      _ctrl.forward(from: 0);
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(kSettingsCellRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(kSettingsCellRadius),
        onTap: widget.onTap,
        onHighlightChanged: _handleHighlightChanged,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final t = _pressed ? _ctrl.value : 1 - _ctrl.value;
            final scale = 1 + (1.06 - 1) * _pressCurve.transform(t);
            return Transform.scale(
              scale: scale,
              alignment: Alignment.center,
              child: child,
            );
          },
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: kSettingsCellIconBoxSize,
                        height: kSettingsCellIconBoxSize,
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(
                            kSettingsCellIconBoxRadius,
                          ),
                        ),
                        child: Center(
                          // 设置页钉选约定：tint = onPrimaryContainer 主轮廓，
                          // 强调点走 NavEntryIcon 主题自适应
                          child: NavEntryIcon(
                            entry: widget.entry,
                            size: kSettingsCellIconSize,
                            tint: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: kSettingsCellLabelSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.isHome)
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '首页',
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ),
              if (widget.inOverflow)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '⋯',
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.0,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}