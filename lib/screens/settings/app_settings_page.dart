// 应用设置：主题入口 + 底栏容量 + 分 Tab 钉选（搜索 / 拖拽排序）。
// Tab：Cupertino 原生滑动分段 + 轻淡入；拖拽：本地排序 + 轻量抬起态。

import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/nav/nav_catalog.dart';
import '../../core/nav/nav_metrics_notifier.dart';
import '../../core/nav/nav_pins_notifier.dart';
import '../../core/theme/state/theme_provider.dart';
import '../profile/lab/game_center/const_game_center.dart';
import '../profile/theme/theme_page.dart';

enum _SettingsTab { general, pinned, core, ai, lab, games }

String _slotLabel(NavPinsState pins, String id) {
  final vis = pins.visibleIds;
  final i = vis.indexOf(id);
  if (i == 0) return '底栏 · 首页';
  if (i > 0) return '底栏 ${i + 1}';
  if (pins.overflowIds.contains(id)) return '⋯';
  return '未钉选';
}

class AppSettingsPage extends ConsumerStatefulWidget {
  const AppSettingsPage({super.key});

  @override
  ConsumerState<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends ConsumerState<AppSettingsPage> {
  _SettingsTab _tab = _SettingsTab.general;
  final _queries = <_SettingsTab, String>{};
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearch(_SettingsTab tab, String value) {
    setState(() => _queries[tab] = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (value.trim().isNotEmpty) {
        ref.read(navMetricsProvider.notifier).recordSearch(value);
      }
    });
  }

  bool _match(NavEntry e, String? q) {
    if (q == null || q.trim().isEmpty) return true;
    final s = q.trim().toLowerCase();
    return e.title.toLowerCase().contains(s) ||
        e.id.toLowerCase().contains(s) ||
        (e.subtitle?.toLowerCase().contains(s) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pins = ref.watch(navPinsProvider);
    final themeMode = ref.watch(themeNotifierProvider);
    final metrics = ref.watch(navMetricsProvider);

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: _CupertinoSettingsTabs(
                value: _tab,
                onChanged: (t) {
                  setState(() => _tab = t);
                  ref
                      .read(navMetricsProvider.notifier)
                      .recordClick('设置 · Tab ${t.name}');
                },
              ),
            ),
            Expanded(
              // 仅淡入淡出：无缩放/滑移叠层，避免「难看」的弹簧感
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: KeyedSubtree(
                  key: ValueKey(_tab),
                  child: switch (_tab) {
                    _SettingsTab.general => _GeneralPanel(
                        themeLabel: AppTheme.getThemeDisplayName(themeMode),
                        capacity: pins.capacity,
                        clicks: metrics.clicks,
                        searches: metrics.searches,
                        onCapacity: (c) => ref
                            .read(navPinsProvider.notifier)
                            .setCapacity(c),
                      ),
                    _SettingsTab.pinned => _PinPool(
                        searchHint: '搜索已钉选',
                        onSearch: (v) => _onSearch(_tab, v),
                        entries: pins.pinIds
                            .map(navEntryById)
                            .whereType<NavEntry>()
                            .where((e) => _match(e, _queries[_tab]))
                            .toList(),
                        pinnedIds: pins.pinIds,
                        reorderable: true,
                        showThumb: true,
                      ),
                    _SettingsTab.core => _PinPool(
                        searchHint: '搜索核心入口',
                        onSearch: (v) => _onSearch(_tab, v),
                        entries: navEntriesInGroup(NavGroup.core)
                            .where((e) => _match(e, _queries[_tab]))
                            .toList(),
                        pinnedIds: pins.pinIds,
                      ),
                    _SettingsTab.ai => _PinPool(
                        searchHint: '搜索 AI 入口',
                        onSearch: (v) => _onSearch(_tab, v),
                        entries: navEntriesInGroup(NavGroup.ai)
                            .where((e) => _match(e, _queries[_tab]))
                            .toList(),
                        pinnedIds: pins.pinIds,
                      ),
                    _SettingsTab.lab => _PinPool(
                        searchHint: '搜索实验室 demo',
                        onSearch: (v) => _onSearch(_tab, v),
                        entries: navEntriesInGroup(NavGroup.lab)
                            .where((e) => _match(e, _queries[_tab]))
                            .toList(),
                        pinnedIds: pins.pinIds,
                      ),
                    _SettingsTab.games => _PinPool(
                        searchHint: '搜索游戏 demo',
                        onSearch: (v) => _onSearch(_tab, v),
                        entries: navEntriesInGroup(NavGroup.game)
                            .where((e) => _match(e, _queries[_tab]))
                            .toList(),
                        pinnedIds: pins.pinIds,
                        showThumb: true,
                      ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneralPanel extends ConsumerWidget {
  const _GeneralPanel({
    required this.themeLabel,
    required this.capacity,
    required this.clicks,
    required this.searches,
    required this.onCapacity,
  });

  final String themeLabel;
  final int capacity;
  final int clicks;
  final int searches;
  final ValueChanged<int> onCapacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      children: [
        _SectionLabel('外观'),
        _Grouped(
          children: [
            ListTile(
              title: const Text('主题'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(themeLabel, style: TextStyle(color: cs.onSurfaceVariant)),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () {
                ref.read(navMetricsProvider.notifier).recordClick('设置 · 主题');
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ThemePage()),
                );
              },
            ),
          ],
        ),
        _SectionLabel('底栏'),
        _Grouped(
          children: [
            ListTile(
              title: const Text('容量（含 ⋯）'),
              trailing: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 4, label: Text('4')),
                ],
                selected: {capacity},
                onSelectionChanged: (s) {
                  onCapacity(s.first);
                  ref
                      .read(navMetricsProvider.notifier)
                      .recordClick('设置 · 容量 ${s.first}');
                },
              ),
            ),
          ],
        ),
        _SectionLabel('观测'),
        _Grouped(
          children: [
            ListTile(
              title: const Text('点击次数'),
              trailing: Text('$clicks', style: TextStyle(color: cs.primary)),
            ),
            ListTile(
              title: const Text('检索次数'),
              trailing: Text('$searches', style: TextStyle(color: cs.primary)),
            ),
          ],
        ),
      ],
    );
  }
}

class _PinPool extends ConsumerStatefulWidget {
  const _PinPool({
    required this.searchHint,
    required this.onSearch,
    required this.entries,
    required this.pinnedIds,
    this.reorderable = false,
    this.showThumb = false,
  });

  final String searchHint;
  final ValueChanged<String> onSearch;
  final List<NavEntry> entries;
  final List<String> pinnedIds;
  final bool reorderable;
  final bool showThumb;

  @override
  ConsumerState<_PinPool> createState() => _PinPoolState();
}

class _PinPoolState extends ConsumerState<_PinPool> {
  /// 拖拽中的本地顺序，避免 provider 回写打断 Reorderable 动画。
  List<NavEntry>? _dragOrder;

  @override
  void didUpdateWidget(covariant _PinPool old) {
    super.didUpdateWidget(old);
    if (!widget.reorderable) {
      _dragOrder = null;
      return;
    }
    // 外部列表变化且不在拖拽时，丢弃本地缓存
    if (_dragOrder == null) return;
    final localIds = _dragOrder!.map((e) => e.id).join(',');
    final nextIds = widget.entries.map((e) => e.id).join(',');
    if (localIds == nextIds) _dragOrder = null;
  }

  List<NavEntry> get _entries => _dragOrder ?? widget.entries;

  String _slotFor(String id) {
    final pins = ref.read(navPinsProvider);
    // 拖拽时用本地顺序估算槽位，避免整表 watch
    if (_dragOrder != null) {
      final ids = _dragOrder!.map((e) => e.id).toList();
      final cap = pins.capacity;
      final visCount = cap - 1;
      final i = ids.indexOf(id);
      if (i < 0) return '未钉选';
      if (i == 0) return '底栏 · 首页';
      if (i < visCount) return '底栏 ${i + 1}';
      return '⋯';
    }
    return _slotLabel(pins, id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = _entries;
    final pins = ref.watch(navPinsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: ValueKey(widget.searchHint),
            onChanged: widget.onSearch,
            decoration: InputDecoration(
              hintText: widget.searchHint,
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        if (widget.reorderable)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '长按拖动排序。顺序 = 底栏 → ⋯',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    '无匹配项',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              : widget.reorderable
                  ? ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: entries.length,
                      buildDefaultDragHandles: false,
                      // 提高跟手滚动速度
                      autoScrollerVelocityScalar: 40,
                      proxyDecorator: (child, index, animation) {
                        final curved = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                          reverseCurve: Curves.easeInCubic,
                        );
                        return AnimatedBuilder(
                          animation: curved,
                          builder: (context, child) {
                            final t = curved.value;
                            return Transform.scale(
                              scale: lerpDouble(1.0, 1.03, t)!,
                              child: Material(
                                elevation: lerpDouble(0, 10, t)!,
                                shadowColor:
                                    Colors.black.withValues(alpha: 0.18),
                                color: cs.surface,
                                borderRadius: BorderRadius.circular(16),
                                child: child,
                              ),
                            );
                          },
                          child: child,
                        );
                      },
                      onReorderStart: (_) {
                        HapticFeedback.mediumImpact();
                        setState(() => _dragOrder = [...widget.entries]);
                      },
                      onReorderEnd: (_) {
                        HapticFeedback.selectionClick();
                      },
                      onReorder: (oldIndex, newIndex) {
                        final local = [...(_dragOrder ?? widget.entries)];
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = local.removeAt(oldIndex);
                        local.insert(newIndex, item);
                        setState(() => _dragOrder = local);

                        final full = local.map((e) => e.id).toList();
                        // 若当前是过滤视图，把未显示的 pin 接在后面
                        final shown = full.toSet();
                        for (final id in widget.pinnedIds) {
                          if (!shown.contains(id)) full.add(id);
                        }
                        ref.read(navPinsProvider.notifier).setPins(full);
                        ref
                            .read(navMetricsProvider.notifier)
                            .recordClick('设置 · 拖拽排序');
                        // 下一帧清本地，避免与 provider 打架
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _dragOrder = null);
                        });
                      },
                      itemBuilder: (context, index) {
                        final e = entries[index];
                        return _PinTile(
                          key: ValueKey(e.id),
                          entry: e,
                          pinned: true,
                          slotLabel: _slotFor(e.id),
                          showThumb: widget.showThumb,
                          dragIndex: index,
                          onToggle: () {
                            ref
                                .read(navPinsProvider.notifier)
                                .togglePin(e.id);
                            ref.read(navMetricsProvider.notifier).recordClick(
                                  '设置 · 关闭 ${e.title}',
                                );
                          },
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final e = entries[index];
                        final pinned = pins.pinIds.contains(e.id);
                        return _PinTile(
                          key: ValueKey(e.id),
                          entry: e,
                          pinned: pinned,
                          slotLabel: _slotLabel(pins, e.id),
                          showThumb: widget.showThumb,
                          onToggle: () {
                            ref
                                .read(navPinsProvider.notifier)
                                .togglePin(e.id);
                            ref.read(navMetricsProvider.notifier).recordClick(
                                  '设置 · ${pinned ? '关闭' : '打开'} ${e.title}',
                                );
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _PinTile extends StatelessWidget {
  const _PinTile({
    super.key,
    required this.entry,
    required this.pinned,
    required this.slotLabel,
    required this.onToggle,
    this.showThumb = false,
    this.dragIndex,
  });

  final NavEntry entry;
  final bool pinned;
  final String slotLabel;
  final VoidCallback onToggle;
  final bool showThumb;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final tile = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dragIndex != null) ...[
              Icon(Icons.drag_handle_rounded, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            _LeadingIcon(entry: entry, showThumb: showThumb),
          ],
        ),
        title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${entry.groupLabel} · $slotLabel',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Switch.adaptive(
          value: pinned,
          onChanged: (_) => onToggle(),
        ),
      ),
      ),
    );

    if (dragIndex != null) {
      return ReorderableDelayedDragStartListener(
        index: dragIndex!,
        child: tile,
      );
    }
    return tile;
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.entry, required this.showThumb});

  final NavEntry entry;
  final bool showThumb;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 游戏：用 meta 渐变块暗示封面体系（完整封面仍在游戏中心）
    if (showThumb && entry.id.startsWith('demo:')) {
      final slug = entry.id.substring(5);
      final meta = kGameMeta[slug];
      if (meta != null) {
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: meta.gradient,
            ),
          ),
          child: Icon(meta.icon, color: Colors.white, size: 18),
        );
      }
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(entry.icon, color: cs.primary, size: 18),
    );
  }
}

/// 系统 Cupertino 滑动分段（原生胶囊跟手，无自定义弹簧过冲）。
class _CupertinoSettingsTabs extends StatelessWidget {
  const _CupertinoSettingsTabs({
    required this.value,
    required this.onChanged,
  });

  final _SettingsTab value;
  final ValueChanged<_SettingsTab> onChanged;

  static const _tabs = <(String, _SettingsTab)>[
    ('通用', _SettingsTab.general),
    ('已钉选', _SettingsTab.pinned),
    ('核心', _SettingsTab.core),
    ('AI', _SettingsTab.ai),
    ('实验室', _SettingsTab.lab),
    ('游戏', _SettingsTab.games),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: CupertinoSlidingSegmentedControl<_SettingsTab>(
          groupValue: value,
          backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.7),
          thumbColor: cs.surface,
          padding: const EdgeInsets.all(3),
          children: {
            for (final (label, tab) in _tabs)
              tab: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        value == tab ? FontWeight.w700 : FontWeight.w600,
                    color: value == tab ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ),
          },
          onValueChanged: (v) {
            if (v == null) return;
            HapticFeedback.selectionClick();
            onChanged(v);
          },
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 0.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _Grouped extends StatelessWidget {
  const _Grouped({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
