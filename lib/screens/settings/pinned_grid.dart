// 设置页 · 钉选网格（拖动排序 + 拖入垃圾桶删除）。
//
// 单一拖拽模式：长按格子拖动（原手感，200ms）。
//   · 松手在网格 → 换位排序（ReorderableBuilder 原路）；
//   · 松手在垃圾桶 → 直接删除（无确认，removePin 保底 ≥1 条）。
// 两者落点不同，互不冲突。
//
// 拖起瞬间底部浮现垃圾桶，松手即收。垃圾桶接受与网格换位是两条独立通路：
//   DragTarget.onAccept（先）置 _droppedOnTrash 并 removePin →
//   包的 onReorder（后）看到 flag 直接跳过重排（列表已被删除更新）。
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

/// 拖到垃圾桶的视觉放大。
const double _kTrashHoverScale = 1.08;

class PinnedGrid extends ConsumerStatefulWidget {
  const PinnedGrid({
    super.key,
    required this.entries,
    required this.visibleSlotCount,
  });

  final List<NavEntry> entries;
  final int visibleSlotCount;

  @override
  ConsumerState<PinnedGrid> createState() => _PinnedGridState();
}

class _PinnedGridState extends ConsumerState<PinnedGrid> {
  /// 本次拖拽是否已被垃圾桶接受（onAccept 先于 onReorder 触发）。
  bool _droppedOnTrash = false;

  /// 是否有格子正在被拖动（仅控制垃圾桶显隐）。
  bool _dragging = false;

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

    // Stack 常驻两子：网格 + 拖动中才可见的垃圾桶。结构不随拖动切换，
    // 避免 ReorderableBuilder 在拖拽途中被重建。
    return Stack(
      children: [
        _SortableGrid(
          entries: entries,
          visibleSlotCount: widget.visibleSlotCount,
          onDragStarted: _handleDragStarted,
          onDragEnd: _handleDragEnd,
          onReorder: _handleReorder,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _TrashZone(
            visible: _dragging,
            onAccept: _handleTrashAccept,
          ),
        ),
      ],
    );
  }

  void _handleDragStarted(int index) {
    HapticFeedback.lightImpact();
    _droppedOnTrash = false;
    if (!_dragging) setState(() => _dragging = true);
  }

  void _handleDragEnd(int index) {
    HapticFeedback.mediumImpact();
    if (_dragging) setState(() => _dragging = false);
    // _droppedOnTrash 留给 onReorder 消费（包契约：onDragEnd 先于 onReorder）。
  }

  void _handleReorder(List<String> Function(List<String>) reorderFn) {
    if (_droppedOnTrash) {
      // 已删除：列表由 removePin 更新，跳过基于旧列表的重排。
      _droppedOnTrash = false;
      return;
    }
    ref
        .read(navPinsProvider.notifier)
        .setPins(
          // 必须用网格 children 同源的 entries 派生列表，保证与
          // reorderFn 的 index 逐位对齐（pinIds 里若有未解析 id，
          // entries 会比 pinIds 短，直接喂 pinIds 会错位重排）。
          reorderFn(widget.entries.map((e) => e.id).toList()),
        );
  }

  void _handleTrashAccept(String id) {
    _droppedOnTrash = true;
    HapticFeedback.heavyImpact();
    ref.read(navPinsProvider.notifier).removePin(id);
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

// ── 垃圾桶：DragTarget<String>，拖动中浮现，悬停高亮 + 微放大 ───────────

class _TrashZone extends StatelessWidget {
  const _TrashZone({required this.visible, required this.onAccept});

  /// false 时整棵从树上摘掉（DragTarget 不在 → 不拦截指针）。
  final bool visible;

  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context) {
    return Visibility(
      visible: visible,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: DragTarget<String>(
          onAcceptWithDetails: (details) => onAccept(details.data),
          builder: (context, candidate, rejected) {
            final cs = Theme.of(context).colorScheme;
            final hovering = candidate.isNotEmpty;
            final color = hovering ? cs.errorContainer : cs.surface;
            final onColor = hovering
                ? cs.onErrorContainer
                : cs.onSurfaceVariant;
            final borderColor = hovering ? cs.error : cs.outlineVariant;
            return Center(
              child: AnimatedScale(
                scale: hovering ? _kTrashHoverScale : 1.0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutBack,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 22,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: borderColor,
                      width: hovering ? 2 : 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        color: onColor,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        hovering ? '松手删除' : '拖到这里删除',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: onColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
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