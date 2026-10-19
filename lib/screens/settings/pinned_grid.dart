// 设置页 · 钉选网格（含编辑态 + 垃圾桶）。
//
// 双态：
//   · 排序态（默认）：短按拖动 = 排序；长按 2s 无位移 = 进编辑态。
//   · 编辑态：单元格长按可拖 → 底部垃圾桶 DragTarget 接受 = 拔钉（直接删）。
//
// 编辑态切回排序态：右上角「完成」按钮。
// 退出编辑态不影响钉选列表；拔钉走 nav_pins_notifier.removePin（至少留 1 条）。
//
// 手动长按 2s 检测走 Listener + Timer，绕开 ReorderableBuilder 包内部的
// LongPressDraggable/Draggable 手势竞争；判「未移动」用 12px 阈值。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_lifecycle/press_bounce_curve.dart';
import '../../core/nav/nav_catalog.dart';
import '../../core/nav/nav_pins_notifier.dart';
import '../../core/ui/shell/nav_entry_icon.dart';
import 'const_settings.dart';

/// 长按 2s 进编辑态的时间窗口。
const Duration _kEnterEditModeHold = Duration(seconds: 2);

/// 长按判定未移动的位移阈值（屏幕 px）。
const double _kEnterEditModeMoveThreshold = 12.0;

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
  bool _editMode = false;

  void _enterEdit() {
    if (_editMode) return;
    HapticFeedback.mediumImpact();
    setState(() => _editMode = true);
  }

  void _exitEdit() {
    if (!_editMode) return;
    setState(() => _editMode = false);
  }

  Future<void> _removePin(String id) async {
    HapticFeedback.heavyImpact();
    await ref.read(navPinsProvider.notifier).removePin(id);
  }

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

    return Stack(
      children: [
        if (_editMode)
          _EditableGrid(
            entries: entries,
            visibleSlotCount: widget.visibleSlotCount,
          )
        else
          _SortableGrid(
            entries: entries,
            visibleSlotCount: widget.visibleSlotCount,
            onLongHold: _enterEdit,
          ),
        if (_editMode)
          Positioned(
            top: 4,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(right: 16, top: 0),
                child: FilledButton.icon(
                  onPressed: _exitEdit,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('完成'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_editMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _TrashZone(onAccept: _removePin),
            ),
          ),
      ],
    );
  }
}

// ── 排序态网格：ReorderableBuilder + Listener 监测 2s 长按 ──────────────

class _SortableGrid extends ConsumerWidget {
  const _SortableGrid({
    required this.entries,
    required this.visibleSlotCount,
    required this.onLongHold,
  });

  final List<NavEntry> entries;
  final int visibleSlotCount;
  final VoidCallback onLongHold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: ReorderableBuilder<String>.builder(
        // 短按立即拖（长按抬起手延迟 = 0）—— 长按 2s 进编辑态走
        // 外层 Listener + Timer，跟包内 drag 完全不冲突。
        longPressDelay: Duration.zero,
        feedbackScaleFactor: kSettingsDragFeedbackScale,
        animationConfig: kSettingsDragConfig,
        dragChildBoxDecoration: settingsDragChildDecoration(cs.onSurface),
        onDragStarted: (_) => HapticFeedback.lightImpact(),
        // 跨格换位 tick（包契约：仅真正换位时回调，非逐帧）
        onUpdatedDraggedChild: (_) => HapticFeedback.selectionClick(),
        onDragEnd: (_) => HapticFeedback.mediumImpact(),
        onReorder: (reorderFn) {
          ref
              .read(navPinsProvider.notifier)
              .setPins(
                // 必须用网格 children 同源的 entries 派生列表，保证与
                // reorderFn 的 index 逐位对齐（pinIds 里若有未解析 id，
                // entries 会比 pinIds 短，直接喂 pinIds 会错位重排）。
                reorderFn(entries.map((e) => e.id).toList()),
              );
        },
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
                _LongHoldDetector(
                  onLongHold: onLongHold,
                  child: _PinnedCell(
                    key: ValueKey(entries[i].id),
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

/// 2s 长按检测：手指按下 2s 内未越过 12px → 触发 [onLongHold]。
/// 走 Listener + Timer，不进手势竞技场，不影响 ReorderableBuilder 的 drag。
class _LongHoldDetector extends StatefulWidget {
  const _LongHoldDetector({required this.onLongHold, required this.child});

  final VoidCallback onLongHold;
  final Widget child;

  @override
  State<_LongHoldDetector> createState() => _LongHoldDetectorState();
}

class _LongHoldDetectorState extends State<_LongHoldDetector> {
  Offset? _pressStart;
  Timer? _holdTimer;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _startHold(Offset pos) {
    _pressStart = pos;
    _holdTimer?.cancel();
    _holdTimer = Timer(_kEnterEditModeHold, () {
      _pressStart = null;
      widget.onLongHold();
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _pressStart = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _startHold(e.position),
      onPointerMove: (e) {
        final start = _pressStart;
        if (start == null) return;
        if ((e.position - start).distance > _kEnterEditModeMoveThreshold) {
          _cancelHold();
        }
      },
      onPointerUp: (_) => _cancelHold(),
      onPointerCancel: (_) => _cancelHold(),
      child: widget.child,
    );
  }
}

// ── 编辑态网格：每格 LongPressDraggable（数据 = id），底部 DragTarget ───

class _EditableGrid extends StatelessWidget {
  const _EditableGrid({
    required this.entries,
    required this.visibleSlotCount,
  });

  final List<NavEntry> entries;
  final int visibleSlotCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 给底部垃圾桶预留空间，避免最末行格子被压住。
    const double kTrashReserve = 84;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: kTrashReserve),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: kSettingsCellCrossAxisCount,
        mainAxisSpacing: kSettingsCellSpacing,
        crossAxisSpacing: kSettingsCellSpacing,
        childAspectRatio: kSettingsCellAspectRatio,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return LongPressDraggable<String>(
          data: entry.id,
          delay: const Duration(milliseconds: 150),
          feedback: Container(
            decoration: settingsDragChildDecoration(cs.onSurface),
            child: _PinnedCell(
              entry: entry,
              isHome: i == 0,
              inOverflow: i >= visibleSlotCount,
              onTap: () {},
              scale: kSettingsDragFeedbackScale,
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.28,
            child: _PinnedCell(
              entry: entry,
              isHome: i == 0,
              inOverflow: i >= visibleSlotCount,
              onTap: () {},
            ),
          ),
          child: _PinnedCell(
            key: ValueKey(entry.id),
            entry: entry,
            isHome: i == 0,
            inOverflow: i >= visibleSlotCount,
            onTap: () {}, // 编辑态：tap = no-op；退出编辑态再开
          ),
        );
      },
    );
  }
}

// ── 垃圾桶：DragTarget<String>，悬停时高亮 + 微放大 ─────────────────────

class _TrashZone extends StatelessWidget {
  const _TrashZone({required this.onAccept});

  final ValueChanged<String> onAccept;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DragTarget<String>(
        onAcceptWithDetails: (details) => onAccept(details.data),
        builder: (context, candidate, rejected) {
          final hovering = candidate.isNotEmpty;
          final color = hovering ? cs.errorContainer : cs.surface;
          final onColor = hovering ? cs.onErrorContainer : cs.onSurfaceVariant;
          final borderColor = hovering ? cs.error : cs.outlineVariant;
          return AnimatedScale(
            scale: hovering ? _kTrashHoverScale : 1.0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutBack,
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 24,
              ),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: borderColor,
                  width: hovering ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    color: onColor,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hovering ? '松手删除' : '拖到这里删除',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: onColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── 共享：已钉格子卡面（排序 / 编辑两态） ───────────────────────────────

class _PinnedCell extends StatefulWidget {
  const _PinnedCell({
    super.key,
    required this.entry,
    required this.isHome,
    required this.inOverflow,
    required this.onTap,
    this.scale = 1.0,
  });

  final NavEntry entry;
  final bool isHome;
  final bool inOverflow;
  final VoidCallback onTap;

  /// 拖动反馈图层的额外缩放（1.0 = 原尺寸）。
  final double scale;

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
    final card = _buildCard(cs);
    if (widget.scale != 1.0) {
      // 拖动反馈：禁用 InkWell onTap 也保持弹性，但跳过 onHighlightChanged。
      return Transform.scale(scale: widget.scale, child: card);
    }
    return card;
  }

  Widget _buildCard(ColorScheme cs) {
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
            final press = 1 + (1.06 - 1) * _pressCurve.transform(t);
            return Transform.scale(
              scale: press,
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