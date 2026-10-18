// 应用设置：钉选快捷区（OS 通知栏快捷开关式编排）。
//
// 主页面只显示当前已钉的入口格子：点按打开、长按拖拽排序（lab 收藏面板
// 拖拽手感，参数对齐 ⋯ 溢出面板的 q 弹配置，见 const_settings）。
// 全量清单（tag 分组 + 搜索 + 点选钉/拔）收进右上「管理」拉起的圆角弹窗，
// 见 pin_editor_sheet.dart。通用项（主题 / 底栏容量）保留为底部一组卡片。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_lifecycle/press_bounce_curve.dart';
import '../../core/nav/nav_catalog.dart';
import '../../core/nav/nav_pins_notifier.dart';
import '../../core/theme/state/theme_provider.dart';
import '../../core/ui/shell/nav_entry_icon.dart';
import '../../core/ui/shell/quick_nav_bottom_bar.dart';
import '../profile/theme/theme_page.dart';
import 'const_settings.dart';
import 'pin_editor_sheet.dart';

class AppSettingsPage extends ConsumerStatefulWidget {
  const AppSettingsPage({super.key});

  @override
  ConsumerState<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends ConsumerState<AppSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pins = ref.watch(navPinsProvider);
    final themeMode = ref.watch(themeNotifierProvider);
    final entries = pins.pinIds
        .map(navEntryById)
        .whereType<NavEntry>()
        .toList();

    return Scaffold(
      // 页底 highest，卡面 surface —— 靠明度分层，不用投影。
      backgroundColor: cs.surfaceContainerHighest,
      // 底栏浮层：勿 SafeArea(bottom)，否则留白露出 Scaffold 色条。
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + QuickNavBottomBar.bodyBottomReserve(context),
          ),
          children: [
            _Header(onManage: () => showPinEditorSheet(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
              child: Text(
                '点按打开 · 长按拖动排序',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            _PinnedGrid(
              entries: entries,
              visibleSlotCount: pins.visibleSlotCount,
            ),
            _GeneralCard(
              themeLabel: AppTheme.getThemeDisplayName(themeMode),
              capacity: pins.capacity,
              onCapacity: (c) =>
                  ref.read(navPinsProvider.notifier).setCapacity(c),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          '设置',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const Spacer(),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: cs.surface,
            foregroundColor: cs.onSurface,
          ),
          onPressed: onManage,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune, size: 16),
              SizedBox(width: 6),
              Text('管理', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

/// 已钉快捷格子网格：顺序 = 底栏 → ⋯，整表拖拽排序。
class _PinnedGrid extends ConsumerWidget {
  const _PinnedGrid({required this.entries, required this.visibleSlotCount});

  final List<NavEntry> entries;
  final int visibleSlotCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    if (entries.isEmpty) {
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

    return RepaintBoundary(
      child: ReorderableBuilder<String>.builder(
        longPressDelay: kSettingsDragLongPressDelay,
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
                _PinnedCell(
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
                i,
              );
            },
          );
        },
      ),
    );
  }
}

/// 已钉格子：surface 卡面 + 角标（首页 / ⋯ 槽位）；按压 iOS 弹性缩放。
class _PinnedCell extends StatefulWidget {
  const _PinnedCell({
    super.key,
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

/// 通用项（非钉选目录内的系统设置）。
class _GeneralCard extends StatelessWidget {
  const _GeneralCard({
    required this.themeLabel,
    required this.capacity,
    required this.onCapacity,
  });

  final String themeLabel;
  final int capacity;
  final ValueChanged<int> onCapacity;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Material(
        color: cs.surface,
        elevation: 0,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('主题'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    themeLabel,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const ThemePage()));
              },
            ),
            ListTile(
              title: const Text('底栏容量（含 ⋯）'),
              trailing: SegmentedButton<int>(
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return cs.onPrimary;
                    }
                    return cs.onSurfaceVariant;
                  }),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return cs.primary;
                    }
                    return cs.surfaceContainerHighest;
                  }),
                ),
                segments: const [
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 4, label: Text('4')),
                ],
                selected: {capacity},
                onSelectionChanged: (s) => onCapacity(s.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
