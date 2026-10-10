// 主壳：可配置快捷底栏。
//
// - 首页 = 钉选列表第 1 项
// - 可见槽 IndexedStack + RepaintBoundary（性能）
// - ⋯ 溢出：Modal sheet，按需 push / 切换
// - iOS 手感：弹簧胶囊 + 轻量页切换

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/nav/nav_catalog.dart';
import '../core/nav/nav_metrics_notifier.dart';
import '../core/nav/nav_pins_notifier.dart';
import '../widgets/quick_nav_bottom_bar.dart';
import 'apk_auto_update_host.dart';

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

  void _select(String id, {required String source}) {
    final entry = navEntryById(id);
    if (entry == null) return;
    ref.read(navMetricsProvider.notifier).recordClick('$source · ${entry.title}');
    setState(() => _selectedId = id);
  }

  Future<void> _openMore(NavPinsState pins) async {
    ref.read(navMetricsProvider.notifier).recordClick('底栏 · 更多');
    final overflow = pins.overflowIds
        .map(navEntryById)
        .whereType<NavEntry>()
        .toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
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
                              _select('core-settings', source: '更多');
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
                      child: GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        children: [
                          for (final e in overflow)
                            _MoreCell(
                              entry: e,
                              onTap: () {
                                final id = e.id;
                                Navigator.pop(ctx);
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  _select(id, source: '更多');
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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

    final mq = MediaQuery.of(context);
    // extendBody：页面画到底栏背后，BackdropFilter 才能采到内容（液态玻璃前提）。
    final bodyPadding = mq.padding.copyWith(
      bottom: QuickNavBottomBar.reserveHeight(context),
    );

    return Stack(
      children: [
        Scaffold(
          extendBody: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: MediaQuery(
            data: mq.copyWith(padding: bodyPadding),
            child: body,
          ),
          bottomNavigationBar: Material(
            type: MaterialType.transparency,
            child: QuickNavBottomBar(
              visibleEntries: visibleEntries,
              selectedId: selected,
              moreSelected: moreSelected,
              onSelect: (id) => _select(id, source: '底栏'),
              onMore: () => _openMore(pins),
            ),
          ),
        ),
        const ApkAutoUpdateMount(),
      ],
    );
  }
}

class _MoreCell extends StatelessWidget {
  const _MoreCell({required this.entry, required this.onTap});

  final NavEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
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
              child: Icon(entry.icon, color: cs.primary, size: 18),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                entry.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
