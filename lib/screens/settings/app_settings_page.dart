// 应用设置：主题入口 + 底栏容量 + 分 Tab 钉选（搜索 / 拖拽排序）。
// iOS inset grouped 手感：分段控件、弹簧开关、ReorderableListView。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/nav/nav_catalog.dart';
import '../../core/nav/nav_metrics_notifier.dart';
import '../../core/nav/nav_pins_notifier.dart';
import '../../core/theme/state/theme_provider.dart';
import '../profile/lab/game_center/const_game_center.dart';
import '../profile/theme/theme_page.dart';

enum _SettingsTab { general, pinned, core, ai, lab, games }

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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _IosSegmented(
                tabs: const [
                  ('通用', _SettingsTab.general),
                  ('已钉选', _SettingsTab.pinned),
                  ('核心', _SettingsTab.core),
                  ('AI', _SettingsTab.ai),
                  ('实验室', _SettingsTab.lab),
                  ('游戏', _SettingsTab.games),
                ],
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
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

class _PinPool extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: ValueKey(searchHint),
            onChanged: onSearch,
            decoration: InputDecoration(
              hintText: searchHint,
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
        if (reorderable)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '长按拖拽排序。顺序 = 底栏 → ⋯',
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
              : reorderable
                  ? ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: entries.length,
                      onReorder: (oldIndex, newIndex) {
                        // 在完整 pin 列表上按 id 重排
                        final full = [...pinnedIds];
                        final id = entries[oldIndex].id;
                        final from = full.indexOf(id);
                        if (from < 0) return;
                        var toId = newIndex >= entries.length
                            ? null
                            : entries[newIndex > oldIndex
                                    ? newIndex - 1
                                    : newIndex]
                                .id;
                        var to = toId == null
                            ? full.length
                            : full.indexOf(toId);
                        if (to < 0) return;
                        if (newIndex > oldIndex) to += 1;
                        ref
                            .read(navPinsProvider.notifier)
                            .reorderPins(from, to);
                        ref
                            .read(navMetricsProvider.notifier)
                            .recordClick('设置 · 拖拽排序');
                      },
                      itemBuilder: (context, index) {
                        final e = entries[index];
                        return _PinTile(
                          key: ValueKey(e.id),
                          entry: e,
                          pinned: true,
                          showThumb: showThumb,
                          dragIndex: index,
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final e = entries[index];
                        return _PinTile(
                          key: ValueKey(e.id),
                          entry: e,
                          pinned: pinnedIds.contains(e.id),
                          showThumb: showThumb,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _PinTile extends ConsumerWidget {
  const _PinTile({
    super.key,
    required this.entry,
    required this.pinned,
    this.showThumb = false,
    this.dragIndex,
  });

  final NavEntry entry;
  final bool pinned;
  final bool showThumb;
  final int? dragIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final pins = ref.watch(navPinsProvider);
    final vis = pins.visibleIds;
    final slot = vis.contains(entry.id)
        ? (vis.indexOf(entry.id) == 0
            ? '底栏 · 首页'
            : '底栏 ${vis.indexOf(entry.id) + 1}')
        : pins.overflowIds.contains(entry.id)
            ? '⋯'
            : '未钉选';

    final leading = dragIndex != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReorderableDragStartListener(
                index: dragIndex!,
                child: Icon(Icons.drag_handle, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              _LeadingIcon(entry: entry, showThumb: showThumb),
            ],
          )
        : _LeadingIcon(entry: entry, showThumb: showThumb);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: leading,
        title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${entry.groupLabel} · $slot',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Switch.adaptive(
          value: pinned,
          onChanged: (_) {
            ref.read(navPinsProvider.notifier).togglePin(entry.id);
            ref.read(navMetricsProvider.notifier).recordClick(
                  '设置 · ${pinned ? '关闭' : '打开'} ${entry.title}',
                );
          },
        ),
      ),
    );
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

class _IosSegmented extends StatelessWidget {
  const _IosSegmented({
    required this.tabs,
    required this.value,
    required this.onChanged,
  });

  final List<(String, _SettingsTab)> tabs;
  final _SettingsTab value;
  final ValueChanged<_SettingsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            for (final (label, tab) in tabs)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: value == tab ? cs.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: value == tab
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () => onChanged(tab),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: value == tab
                                ? cs.onSurface
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
