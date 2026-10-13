// 主壳：可配置快捷底栏。
//
// - 首页 = 钉选列表第 1 项
// - 可见槽 IndexedStack + RepaintBoundary（性能）
// - 无溢出时末位槽直连「设置」；有溢出时末位为 ⋯：Modal sheet，按需 push / 切换
// - iOS 手感：弹簧胶囊 + 轻量页切换

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/entities/reorderable_animation_config.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/nav/nav_catalog.dart';
import '../core/nav/nav_pins_notifier.dart';
import '../widgets/nav_entry_icon.dart';
import '../widgets/quick_nav_bottom_bar.dart';
import 'apk_auto_update_host.dart';
import 'press_bounce_curve.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  String? _selectedId;
  final Map<String, Widget> _pageCache = {};

  @override
  void initState() {
    super.initState();
    // 目录依赖 lab bootstrap；首次进页时清缓存确保完整
    invalidateNavCatalogCache();
  }

  String _resolveSelected(NavPinsState pins) {
    final id = _selectedId;
    // 允许未钉选但仍有效的入口（⋯ 里的「设置」等），不能只认 pinIds，
    // 否则选中后下一帧会被打回 homeId，表现为「设置点了没反应」。
    if (id != null && navEntryById(id) != null) return id;
    return pins.homeId;
  }

  Widget _pageFor(String id) {
    return _pageCache.putIfAbsent(id, () {
      final entry = navEntryById(id);
      final child = entry?.builder(context) ??
          const Center(child: Text('入口不存在'));
      return RepaintBoundary(child: child);
    });
  }

  void _select(String id) {
    if (navEntryById(id) == null) return;
    setState(() => _selectedId = id);
  }

  Future<void> _openMore(NavPinsState initialPins) async {
    // Consumer 包 sheet 让 grid 在 setPins 后实时重建——用户拖完一项
    // 列表立刻反映新顺序，不必先关弹窗再开。
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final cs = Theme.of(ctx).colorScheme;
          final pins = ref.watch(navPinsProvider);
          final overflow = pins.overflowIds
              .map(navEntryById)
              .whereType<NavEntry>()
              .toList();
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
                      child: Row(
                        children: [
                          Text(
                            '更多',
                            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                _select(kSettingsNavId);
                              });
                            },
                            child: const Text('设置'),
                          ),
                        ],
                      ),
                    ),
                    if (overflow.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                        child: Text(
                          '没有溢出快捷。在设置里打开更多入口，或把容量调成 3。',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                        // 拖拽排序：复用 lab 收藏同款 ReorderableBuilder，但
                        // longPressDelay 缩短到 200ms 提速、feedback 放 1.06
                        // 微弹（iOS 触控反馈），拖动项带阴影（lab 收藏关闭
                        // 阴影是为适应面板暗底，这里 sheet 明底需要浮起）。
                        child: ReorderableBuilder<String>.builder(
                          longPressDelay: const Duration(milliseconds: 200),
                          feedbackScaleFactor: 1.06,
                          animationConfig: const ReorderableAnimationConfig(
                            dragFeedbackDuration: Duration.zero,
                          ),
                          dragChildBoxDecoration: BoxDecoration(
                            color: cs.onSurface.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          onDragStarted: (_) => HapticFeedback.lightImpact(),
                          onDragEnd: (_) => HapticFeedback.mediumImpact(),
                          onReorder: (reorderFn) {
                            // 重组 overflow id 列表后回写 navPins
                            // （保留可见槽顺序不动）
                            final overflowIds =
                                pins.overflowIds.toList(growable: false);
                            final reordered = reorderFn(overflowIds);
                            ref
                                .read(navPinsProvider.notifier)
                                .setPins([...pins.visibleIds, ...reordered]);
                            HapticFeedback.mediumImpact();
                          },
                          itemCount: overflow.length,
                          childBuilder: (itemBuilder) {
                            return GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 10,
                                    childAspectRatio: 1.0,
                                  ),
                              itemCount: overflow.length,
                              itemBuilder: (gridCtx, i) {
                                return itemBuilder(
                                  // ReorderableBuilder 强约束：每个子项必须
                                  // 有唯一 key（initChildren 的 assert），
                                  // 漏了 debug 下整个 sheet 直接 build 失败
                                  _MoreCell(
                                    key: ValueKey(overflow[i].id),
                                    entry: overflow[i],
                                    onTap: () {
                                      final id = overflow[i].id;
                                      Navigator.pop(ctx);
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        if (!mounted) return;
                                        _select(id);
                                      });
                                    },
                                  ),
                                  i,
                                );
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pins = ref.watch(navPinsProvider);
    // pin 变更时丢弃已移除页的缓存，避免泄漏
    _pageCache.removeWhere((id, _) => !pins.pinIds.contains(id) && id != _selectedId);

    final selected = _resolveSelected(pins);
    _selectedId = selected;

    final visibleEntries = pins.visibleIds
        .map(navEntryById)
        .whereType<NavEntry>()
        .toList();

    // 无溢出（pin 数 ≤ 可见槽）且设置未被钉选 → 末位槽直连设置，免 ⋯ 二跳。
    final lastSlotEntry =
        pins.lastSlotIsSettings ? navEntryById(kSettingsNavId) : null;

    final visibleIndex = visibleEntries.indexWhere((e) => e.id == selected);
    final moreSelected = visibleIndex < 0;

    // 可见槽始终留在 IndexedStack（带 Key），避免切到 ⋯ 时丢掉 State。
    // 溢出页作为额外末位子节点，仅在 moreSelected 时显示。
    final stackKids = <Widget>[
      for (final e in visibleEntries)
        KeyedSubtree(key: ValueKey(e.id), child: _pageFor(e.id)),
      if (moreSelected)
        KeyedSubtree(
          key: ValueKey('overflow-$selected'),
          child: _pageFor(selected),
        ),
    ];
    final body = stackKids.isEmpty
        ? const SizedBox.shrink()
        : IndexedStack(
            index: moreSelected
                ? stackKids.length - 1
                : visibleIndex.clamp(0, stackKids.length - 1),
            sizing: StackFit.expand,
            children: stackKids,
          );

    // 底栏 Stack 浮层。切勿把底栏高度写入 MediaQuery.padding——SafeArea 会
    // 吃掉后露出各页 Scaffold 白条。系统 safe inset 照常；底栏避让由页面
    // 滚动区用 QuickNavBottomBar.bodyBottomReserve 自行加。
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    // 子页面（如 Lab 上滑面板铺满）主动要隐藏底栏时合并隐藏条件。
    final hiddenByPage = ref.watch(bottomBarVisibilityProvider);
    final shouldHide = hiddenByPage || keyboard > 0;

    return Stack(
      children: [
        Scaffold(
          // 主题底色兜底：透明壳根页（钉选的 demo 等自身不铺背景的页面）
          // 靠这层拿到 surface 底色，否则一路透明透出 Flutter 黑窗。
          body: body,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: shouldHide,
            child: AnimatedOpacity(
              opacity: shouldHide ? 0 : 1,
              duration: const Duration(milliseconds: 120),
              child: QuickNavBottomBar(
                visibleEntries: visibleEntries,
                lastSlotEntry: lastSlotEntry,
                selectedId: selected,
                moreSelected: moreSelected,
                onSelect: _select,
                onMore: () => _openMore(pins),
              ),
            ),
          ),
        ),
        const ApkAutoUpdateMount(),
      ],
    );
  }
}

class _MoreCell extends StatefulWidget {
  const _MoreCell({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final NavEntry entry;
  final VoidCallback onTap;

  @override
  State<_MoreCell> createState() => _MoreCellState();
}

class _MoreCellState extends State<_MoreCell>
    with SingleTickerProviderStateMixin {
  /// 弹性曲线：iOS 按压回弹——快进快出，过冲 8% 营造 q 弹感。
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
      HapticFeedback.selectionClick();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      // Material 自带 InkWell splash 之外，再叠 iOS 风格缩放：
      // 按下放大 1.06，松手弹回原大小（曲线先过冲再收敛）
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                // 双色 mini app-icon：body 取 onSurface（深色），强调点走
                // LabDemoIcon 自适应——zen/cobalt 这些 mid-单色 primary 不再
                // 让 body 与 accent 同色，深色主题下 body 自动压暗出对比
                child: Center(
                  child: NavEntryIcon(
                    entry: widget.entry,
                    size: 18,
                    tint: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  widget.entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

