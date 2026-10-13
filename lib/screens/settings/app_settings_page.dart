// 应用设置：主题入口 + 底栏容量 + 分 Tab 钉选（搜索 / 拖拽排序）。
// Tab：分段点击 + 左右滑动；钉选散卡排序，其它分组一张大组卡（无阴影）。
// 原型：docs/prototypes/settings-list-group-card.html

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/game_kit/skin/game_center_skin_spec.dart';
import '../../core/nav/game_cover_warmup.dart';
import '../../core/nav/nav_catalog.dart';
import '../../core/nav/nav_pins_notifier.dart';
import '../../core/theme/state/theme_provider.dart';
import '../../lab/lab_container.dart';
import '../../widgets/nav_entry_icon.dart';
import '../../widgets/quick_nav_bottom_bar.dart';
import '../profile/lab/demo_detail_page.dart';
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
  static const _tabs = _SettingsTab.values;

  _SettingsTab _tab = _SettingsTab.general;
  late final PageController _pageController;
  final _queries = <_SettingsTab, String>{};
  /// 封面预热完成后刷新游戏缩略图。
  var _coversReady = false;
  /// 钉选拖拽中禁止横向翻页。
  var _pagingLocked = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _tab.index);
    // 进设置时再确保拉一次（启动预热可能尚未完成）
    warmUpGameCenterCovers().then((_) {
      if (mounted) setState(() => _coversReady = true);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectTab(_SettingsTab tab, {required bool animate}) {
    _tab = tab;
    if (!animate || !_pageController.hasClients) return;
    final current = _pageController.page ?? tab.index.toDouble();
    if ((current - tab.index).abs() < 0.001) return;
    _pageController.animateToPage(
      tab.index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _onSearch(_SettingsTab tab, String value) {
    setState(() => _queries[tab] = value);
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

    return Scaffold(
      // 页底 highest，卡面 surface —— 靠明度分层，不用投影。
      backgroundColor: cs.surfaceContainerHighest,
      // 底栏浮层：勿 SafeArea(bottom)，否则留白露出 Scaffold 色条。
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: AnimatedBuilder(
                animation: _pageController,
                builder: (context, _) {
                  final page = _pageController.hasClients
                      ? (_pageController.page ?? _tab.index.toDouble())
                      : _tab.index.toDouble();
                  return _CupertinoSettingsTabs(
                    page: page,
                    onChanged: (t) => _selectTab(t, animate: true),
                  );
                },
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: _pagingLocked
                    ? const NeverScrollableScrollPhysics()
                    : null,
                onPageChanged: (i) =>
                    _selectTab(_tabs[i.clamp(0, _tabs.length - 1)], animate: false),
                children: [
                  _KeepAlivePage(
                    child: _GeneralPanel(
                      themeLabel: AppTheme.getThemeDisplayName(themeMode),
                      capacity: pins.capacity,
                      onCapacity: (c) =>
                          ref.read(navPinsProvider.notifier).setCapacity(c),
                    ),
                  ),
                  _KeepAlivePage(
                    child: _PinPool(
                      searchHint: '搜索已钉选',
                      onSearch: (v) => _onSearch(_SettingsTab.pinned, v),
                      entries: pins.pinIds
                          .map(navEntryById)
                          .whereType<NavEntry>()
                          .where((e) => _match(e, _queries[_SettingsTab.pinned]))
                          .toList(),
                      pinnedIds: pins.pinIds,
                      reorderable: true,
                      showThumb: true,
                      onReorderActive: (active) =>
                          setState(() => _pagingLocked = active),
                    ),
                  ),
                  _KeepAlivePage(
                    child: _PinPool(
                      searchHint: '搜索核心入口',
                      onSearch: (v) => _onSearch(_SettingsTab.core, v),
                      entries: navEntriesInGroup(NavGroup.core)
                          .where((e) => _match(e, _queries[_SettingsTab.core]))
                          .toList(),
                      pinnedIds: pins.pinIds,
                    ),
                  ),
                  _KeepAlivePage(
                    child: _PinPool(
                      searchHint: '搜索 AI 入口',
                      onSearch: (v) => _onSearch(_SettingsTab.ai, v),
                      entries: navEntriesInGroup(NavGroup.ai)
                          .where((e) => _match(e, _queries[_SettingsTab.ai]))
                          .toList(),
                      pinnedIds: pins.pinIds,
                    ),
                  ),
                  _KeepAlivePage(
                    child: _PinPool(
                      searchHint: '搜索实验室 demo',
                      onSearch: (v) => _onSearch(_SettingsTab.lab, v),
                      entries: navEntriesInGroup(NavGroup.lab)
                          .where((e) => _match(e, _queries[_SettingsTab.lab]))
                          .toList(),
                      pinnedIds: pins.pinIds,
                    ),
                  ),
                  _KeepAlivePage(
                    child: _PinPool(
                      searchHint: '搜索游戏 demo',
                      onSearch: (v) => _onSearch(_SettingsTab.games, v),
                      entries: navEntriesInGroup(NavGroup.game)
                          .where((e) => _match(e, _queries[_SettingsTab.games]))
                          .toList(),
                      pinnedIds: pins.pinIds,
                      showThumb: true,
                      coverEpoch: _coversReady ? 1 : 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GeneralPanel extends StatelessWidget {
  const _GeneralPanel({
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
    final bottomPad = QuickNavBottomBar.bodyBottomReserve(context);
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottomPad),
      children: [
        _SectionLabel('账号'),
        _Grouped(
          children: [
            ListTile(
              title: const Text('统一登录扫码'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final demo = demoRegistry.getBySlug('auth-login');
                if (demo == null) return;
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DemoDetailPage(demo: demo)),
                );
              },
            ),
          ],
        ),
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
    this.coverEpoch = 0,
    this.onReorderActive,
  });

  final String searchHint;
  final ValueChanged<String> onSearch;
  final List<NavEntry> entries;
  final List<String> pinnedIds;
  final bool reorderable;
  final bool showThumb;
  final int coverEpoch;
  final ValueChanged<bool>? onReorderActive;

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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Material(
            color: cs.surface,
            elevation: 0,
            borderRadius: BorderRadius.circular(980),
            child: TextField(
              key: ValueKey(widget.searchHint),
              onChanged: widget.onSearch,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(980),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            widget.reorderable
                ? '长按拖动排序。顺序 = 底栏 → ⋯'
                : '开关在这里改钉选；排序请去「钉选」。',
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
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16 + QuickNavBottomBar.bodyBottomReserve(context),
                      ),
                      itemCount: entries.length,
                      buildDefaultDragHandles: false,
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
                              scale: lerpDouble(1.0, 1.02, t)!,
                              child: Material(
                                elevation: 0,
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
                        widget.onReorderActive?.call(true);
                        setState(() => _dragOrder = [...widget.entries]);
                      },
                      onReorderEnd: (_) {
                        HapticFeedback.selectionClick();
                        widget.onReorderActive?.call(false);
                      },
                      onReorder: (oldIndex, newIndex) {
                        final local = [...(_dragOrder ?? widget.entries)];
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = local.removeAt(oldIndex);
                        local.insert(newIndex, item);
                        setState(() => _dragOrder = local);

                        final full = local.map((e) => e.id).toList();
                        final shown = full.toSet();
                        for (final id in widget.pinnedIds) {
                          if (!shown.contains(id)) full.add(id);
                        }
                        ref.read(navPinsProvider.notifier).setPins(full);
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
                          loose: true,
                        );
                      },
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16 + QuickNavBottomBar.bodyBottomReserve(context),
                      ),
                      children: [
                        // 一张大组卡：行与行零间距、无分隔线。
                        Material(
                          color: cs.surface,
                          elevation: 0,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final e in entries)
                                _PinTile(
                                  key: ValueKey(
                                    '${e.id}-${widget.coverEpoch}',
                                  ),
                                  entry: e,
                                  pinned: pins.pinIds.contains(e.id),
                                  slotLabel: _slotLabel(pins, e.id),
                                  showThumb: widget.showThumb,
                                  loose: false,
                                  onToggle: () {
                                    ref
                                        .read(navPinsProvider.notifier)
                                        .togglePin(e.id);
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
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
    required this.loose,
    this.onToggle,
    this.showThumb = false,
    this.dragIndex,
  });

  final NavEntry entry;
  final bool pinned;
  final String slotLabel;
  /// true = 钉选散卡（独立圆角卡）；false = 大组卡内一行。
  final bool loose;
  final VoidCallback? onToggle;
  final bool showThumb;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final row = ListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      minVerticalPadding: 0,
      leading: _LeadingIcon(
        entry: entry,
        showThumb: showThumb,
      ),
      title: Text(
        entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      subtitle: Text(
        '${entry.groupLabel} · $slotLabel',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: cs.onSurfaceVariant,
        ),
      ),
      trailing: onToggle != null
          ? Switch.adaptive(
              value: pinned,
              onChanged: (_) => onToggle!(),
            )
          : dragIndex != null
              ? Icon(
                  Icons.drag_handle_rounded,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                )
              : null,
    );

    final Widget tile;
    if (loose) {
      // 散卡：surface · r16 · 间距 10 · 无阴影
      tile = Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: cs.surface,
          elevation: 0,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: row,
        ),
      );
    } else {
      tile = row;
    }

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
  const _LeadingIcon({
    required this.entry,
    required this.showThumb,
  });

  final NavEntry entry;
  final bool showThumb;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (showThumb && entry.id.startsWith('demo:')) {
      final slug = entry.id.substring(5);
      final meta = kGameMeta[slug];
      // KV 远程封面（small）→ 程序化渐变兜底
      final cover = gameCenterCoverOf(slug, kGameCenterSkinSmall);
      if (cover != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Image(
              image: cover,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _gameFallback(meta, entry.icon),
            ),
          ),
        );
      }
      if (meta != null) return _gameFallback(meta, entry.icon);
    }
    // 原型 .ico：40 方圆角瓦，不用圆形。
    // demo 专属 SVG：onPrimaryContainer 轮廓 + 主题自适应强调点
    // （cobalt/zen 深 primary 会自动提亮，见 LabDemoIcon 自适应规则）；
    // 未登记的核心入口 / demo 走 Material icon。
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: NavEntryIcon(
          entry: entry,
          size: 18,
          tint: cs.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _gameFallback(GameMeta? meta, IconData icon) {
    if (meta == null) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18),
      );
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
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

class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});
  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// 等宽收进一屏的分段控件（不横向滚动）。
class _CupertinoSettingsTabs extends StatelessWidget {
  const _CupertinoSettingsTabs({
    required this.page,
    required this.onChanged,
  });

  final double page;
  final ValueChanged<_SettingsTab> onChanged;

  /// 短标签，保证 6 格塞进手机宽度。
  static const _tabs = <(String, _SettingsTab)>[
    ('通用', _SettingsTab.general),
    ('钉选', _SettingsTab.pinned),
    ('核心', _SettingsTab.core),
    ('AI', _SettingsTab.ai),
    ('实验', _SettingsTab.lab),
    ('游戏', _SettingsTab.games),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = page.round().clamp(0, _tabs.length - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final innerW = constraints.maxWidth - 4;
        final cellW = innerW / _tabs.length;
        return Container(
          height: 36,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(2),
          child: Stack(
            children: [
              Positioned(
                left: page.clamp(0, _tabs.length - 1) * cellW,
                top: 0,
                bottom: 0,
                width: cellW,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onChanged(_tabs[i].$2);
                        },
                        child: Center(
                          child: Text(
                            _tabs[i].$1,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selected == i
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: selected == i
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
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
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
