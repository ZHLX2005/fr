// 游戏中心 — 独立游戏列表页（主页直入）
//
// 结构（CustomScrollView，自上而下）：
//   ① 顶部功能行：返回键 + 描边搜索框（H3R-C「搜索框即头」，无标题无渐变）
//   ② 收藏轮播横滑（仅"全部"筛选下出现；收藏为空显示空态引导）
//   ③ 分类过滤 chip（border-emphasis，带数量）
//   ④ 自适应列数网格（MaxCrossAxisExtent，平板自动多列）
//
// 滚动越过阈值后顶部淡入一条毛玻璃细条（返回箭头 + 标题 + 搜索/历史 mini 图标），
// 替代原 AppBar 的同色渐变揭示。
//
// 搜索：输入实时过滤网格与分节标题；「搜索」钮 / 提交收键盘并记入搜索历史
//（SharedPreferences，最新在前封顶 8 条）；占位文字取历史首条。
// 历史入口在玻璃条 history 图标 → 底部弹层，可点词回填、可清空。
//
// 分类 / 配色 / 图标登记表在 game_center/const_game_center.dart；
// 卡片组件在 game_center/game_center_cards.dart；封面在 game_center_artwork.dart。
//
// 添加新游戏：demo `override type => DemoType.game` + 在 kGameCenterCatalog 与
// kGameMeta 里各登记一条，再跑 `dart run tool/publish_game_center_index.dart`
// 重发 KV——否则 ve 管理端「游戏封面」tab 看不到该游戏，无法分配封面。
// 本文件无需改动。

import 'dart:async' show unawaited;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/game_kit/game_center_catalog.dart';
import '../../../core/game_kit/skin/game_center_skin_spec.dart';
import '../../../lab/lab_container.dart';
import 'demo_detail_page.dart';
import 'game_center/const_game_center.dart';
import 'game_center/game_center_cards.dart';
import 'providers/lab_card_provider.dart';
import 'reveal_item.dart';

class GameCenterPage extends StatefulWidget {
  const GameCenterPage({super.key});

  @override
  State<GameCenterPage> createState() => _GameCenterPageState();
}

class _GameCenterPageState extends State<GameCenterPage>
    with TickerProviderStateMixin {
  final _provider = LabCardProvider();
  final _scrollController = ScrollController();
  final _chipScrollController = ScrollController();
  final _featuredController = PageController(viewportFraction: 0.88);
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  late final AnimationController _revealController;

  /// 全部 game 类 demo（按注册顺序，别名 slug 已按实例去重）
  late final List<DemoPage> _games;

  String _selected = GameCategory.all;
  double _glassReveal = 0.0;
  int _featuredIndex = 0;

  /// 搜索历史（最新在前；SharedPreferences 持久化）
  List<String> _searchHistory = const [];

  @override
  void initState() {
    super.initState();
    final seen = <DemoPage>{};
    _games = demoRegistry
        .getAll()
        .filterByType(DemoType.game)
        .map((e) => e.value)
        .where(seen.add)
        .toList();

    // debug 校验（双向防漂移）：
    //   正向：catalog（KV 事实源，ve 管理端消费）每条都已注册且在 kGameMeta 里；
    //   反向：每个注册的 game 都进了 catalog（漏登记 → 管理端无法分配封面）。
    // 任一不一致在 debug 构建直接崩（发布前必现）。
    assert(() {
      final slugs = _games.map((d) => d.slug).toSet();
      for (final e in kGameCenterCatalog) {
        assert(
          slugs.contains(e.slug),
          'game-center catalog slug "${e.slug}" is not registered as DemoType.game; '
          'add it to kGameCenterCatalog / demo, or drop it from the catalog',
        );
        assert(
          kGameMeta.containsKey(e.slug),
          'game-center catalog slug "${e.slug}" missing in kGameMeta; '
          'add a GameMeta entry in const_game_center.dart',
        );
      }
      final catalogSlugs = kGameCenterCatalog.map((e) => e.slug).toSet();
      for (final d in _games) {
        assert(
          catalogSlugs.contains(d.slug),
          'game "${d.slug}" is registered as DemoType.game but missing in '
          'kGameCenterCatalog; add a GameCenterCatalogEntry in '
          'game_center_catalog.dart, then republish via '
          'tool/publish_game_center_index.dart (ve admin cannot see it otherwise)',
        );
      }
      return true;
    }());

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _scrollController.addListener(_onScroll);
    _provider.addListener(_onProviderChanged);
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadSearchHistory());

    // 封面加载（id58 修复：KV 拉取结果落盘，离线/下次进入也能显示线上封面）：
    //   1. 先恢复上次持久化的封面索引（零网络，首屏即可显示线上封面）；
    //   2. 再 best-effort 拉取线上最新（fetchAndMerge 成功后自动落盘）。
    // 封面管线：ve game-skin-admin 上传 → KV public game-center_skin:index → 这里合入。
    // 拉取/恢复成功后必须 setState：卡片在 build 时读 gameCenterCoverOf，
    // 否则首屏一直停在程序化兜底。
    unawaited(_loadCovers());
  }

  Future<void> _loadCovers() async {
    final restored = await gameCenterSkinBundle
        .restorePersistedIndex()
        .catchError((Object _) => false);
    if (restored && mounted) setState(() {});
    final ok = await fetchAndMergeGameCenterSkins().catchError(
      (Object _) => false,
    );
    if (ok && mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _chipScrollController.dispose();
    _featuredController.dispose();
    _revealController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    // 收藏变更会影响"收藏" chip 数量与收藏筛选结果
    if (mounted) setState(() {});
  }

  void _onScroll() {
    // 滚动越过阈值 → 毛玻璃细条整体淡入（opacity + 轻微下移入场）
    final next = (_scrollController.offset / kGcGlassBarThreshold).clamp(
      0.0,
      1.0,
    );
    if ((next - _glassReveal).abs() > 0.01) {
      setState(() => _glassReveal = next);
    }
  }

  // ── 搜索 ────────────────────────────────────────────────────

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      // getStringList 返回不可修改列表，必须拷贝 —— 否则 _commitSearch 的
      // remove/insert 直接抛 UnsupportedError
      _searchHistory = List<String>.of(
        prefs.getStringList(kGcSearchHistoryKey) ?? const [],
      );
    });
  }

  Future<void> _saveSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kGcSearchHistoryKey, _searchHistory);
  }

  /// 「搜索」钮 / 键盘提交：记录历史（去重置顶）并收键盘。
  Future<void> _commitSearch() async {
    final q = _searchController.text.trim();
    if (q.isNotEmpty) {
      setState(() {
        _searchHistory
          ..remove(q)
          ..insert(0, q);
        if (_searchHistory.length > kGcSearchHistoryMax) {
          _searchHistory.removeRange(kGcSearchHistoryMax, _searchHistory.length);
        }
      });
      unawaited(_saveSearchHistory());
    }
    _searchFocusNode.unfocus();
  }

  /// 输入即重算列表；有词时跳回"全部"分类，
  /// 避免在非全部分类下搜索看起来像没结果。
  void _onSearchChanged() {
    setState(() {});
    if (_searchController.text.trim().isEmpty) return;
    if (_selected != GameCategory.all) _select(GameCategory.all);
  }

  /// 占位文字：最近搜索的首条；无历史时用通用提示。
  String get _searchHint =>
      _searchHistory.isEmpty ? '搜索游戏 · 玩法 · 分类' : _searchHistory.first;

  /// 搜索命中：标题 / 描述大小写不敏感包含匹配
  bool _matchSearch(DemoPage demo, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return demo.title.toLowerCase().contains(q) ||
        demo.description.toLowerCase().contains(q);
  }

  // ── 数据 ────────────────────────────────────────────────────

  /// 轮播数据源：收藏的游戏（按 Lab 面板的收藏顺序），不再按"联机"硬编码。
  List<DemoPage> get _featured {
    final order = _provider.getFavoritesOrder();
    final list = _games
        .where((d) => _provider.isFavorite(d.title))
        .toList();
    list.sort(
      (a, b) => order.indexOf(a.title).compareTo(order.indexOf(b.title)),
    );
    return list;
  }

  List<DemoPage> _bucket(String category) {
    final query = _searchController.text.trim();
    Iterable<DemoPage> pool = _games;
    // 有搜索词时按词过滤（分类过滤在搜索结果上继续生效）
    if (query.isNotEmpty) {
      pool = pool.where((d) => _matchSearch(d, query));
    }
    if (category == GameCategory.all) return pool.toList();
    if (category == GameCategory.favorites) {
      return pool.where((d) => _provider.isFavorite(d.title)).toList();
    }
    return pool
        .where((d) => gameMetaOf(d.slug).categories.contains(category))
        .toList();
  }

  void _open(DemoPage demo) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DemoDetailPage(demo: demo)),
    );
  }

  void _select(String category) {
    if (_selected == category) return;
    setState(() => _selected = category);
    _revealController.forward(from: 0.0);
    _scrollChipIntoView(category);
  }

  /// 左右滑切换分类：左滑下一档，右滑上一档（与 chip 顺序一致）。
  void _onHorizontalDragEnd(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v.abs() < 280) return;
    final tabs = kGameCategoryTabs;
    final i = tabs.indexWhere((t) => t.category == _selected);
    if (i < 0) return;
    final next = i + (v < 0 ? 1 : -1);
    if (next < 0 || next >= tabs.length) return;
    HapticFeedback.selectionClick();
    _select(tabs[next].category);
  }

  void _scrollChipIntoView(String category) {
    final i = kGameCategoryTabs.indexWhere((t) => t.category == category);
    if (i < 0 || !_chipScrollController.hasClients) return;
    // chip 宽约不一，用近似步进保证选中项大致入屏
    final target = (i * 100.0).clamp(
      0.0,
      _chipScrollController.position.maxScrollExtent,
    );
    unawaited(
      _chipScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      ),
    );
  }

  // ── 构建 ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _bucket(_selected);
    final query = _searchController.text.trim();
    final showFeatured = _selected == GameCategory.all && query.isEmpty;

    // H3R-C「搜索框即头」：无渐变头部，纸面恒浅底 —— 状态栏图标恒深色
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: [
            GestureDetector(
              // 垂直列表仍走 CustomScrollView；水平甩动切换分类 tab。
              // 收藏轮播 PageView / chip 横滑条在手势竞技场中优先，不抢它们的横向滑动。
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader(theme)),
                  if (showFeatured) ...[
                    SliverToBoxAdapter(
                      child: _SectionTitle(
                        title: '我的收藏',
                        subtitle: _featured.isEmpty
                            ? '收藏的游戏会自动展示在这里'
                            : '${_featured.length} 款 · 点星标管理',
                        icon: Icons.star_rounded,
                      ),
                    ),
                    if (_featured.isEmpty)
                      const SliverToBoxAdapter(child: _EmptyFeatured())
                    else
                      SliverToBoxAdapter(child: _buildFeatured()),
                  ],
                  SliverToBoxAdapter(child: _buildCategoryBar()),
                  if (list.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyBucket(
                        category: _selected,
                        isSearch: query.isNotEmpty,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        kGcPagePadding,
                        4,
                        kGcPagePadding,
                        28,
                      ),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: kGcGridMaxExtent,
                              childAspectRatio: kGcGridAspectRatio,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                            ),
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final demo = list[index];
                          return RevealItem(
                            index: index,
                            controller: _revealController,
                            delayStep: kGcRevealDelayStep,
                            maxDelay: kGcRevealMaxDelay,
                            itemDuration: kGcRevealItemDuration,
                            translateY: kGcRevealTranslateY,
                            child: GameGridCard(
                              demo: demo,
                              onTap: () => _open(demo),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            // 滚动后淡入的毛玻璃细条（返回箭头 + 标题 + 搜索/历史 mini 图标）
            _buildGlassBar(theme),
          ],
        ),
      ),
    );
  }

  /// 顶部功能行：返回键 + 描边搜索框（H3R-C 定稿：状态栏下第一行就是功能件）
  Widget _buildHeader(ThemeData theme) {
    final topInset = MediaQuery.paddingOf(context).top;
    // 有状态栏 inset（刘海屏）用 inset+6；无 inset（桌面/横屏）给固定呼吸空间
    final topGap = topInset > 0
        ? topInset + kGcTopRowGapTop
        : kGcTopRowGapTopFallback;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        kGcPagePadding,
        topGap,
        kGcPagePadding,
        kGcTopRowGapBottom,
      ),
      child: SizedBox(
        height: kGcTopRowHeight,
        child: Row(
          children: [
            _BackButton(onTap: () => Navigator.maybePop(context)),
            const SizedBox(width: 10),
            Expanded(child: _buildSearchField(theme)),
          ],
        ),
      ),
    );
  }

  /// 描边式搜索框：透明底 + 主题色 2px 描边 + 内嵌「搜索」提交钮。
  /// 占位文字 = 最近搜索的首条（隐性展示历史行为）。
  Widget _buildSearchField(ThemeData theme) {
    final scheme = theme.colorScheme;
    final borderColor = scheme.primary.withValues(alpha: 0.55);
    return GestureDetector(
      // 框内任意空白（图标 / 文字上下空隙）点按都聚焦输入
      onTap: () => _searchFocusNode.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: kGcTopRowHeight,
        padding: const EdgeInsets.only(right: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kGcSearchRadius),
          border: Border.all(
            color: borderColor,
            width: kGcSearchBorderWidth,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(Icons.search_rounded, size: 19, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              // Center + isCollapsed：TextField 固有高度即一行字，
              // 垂直居中不依赖 textAlignVertical（后者在紧高度下不可靠）
              child: Center(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  cursorColor: scheme.primary,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => unawaited(_commitSearch()),
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: _searchHint,
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
            _SearchGoButton(onTap: () => unawaited(_commitSearch())),
          ],
        ),
      ),
    );
  }

  /// 毛玻璃标题条：surface 82% + blur，左端返回箭头 + 「游戏中心」，
  /// 右侧 search（回顶聚焦搜索框）/ history（搜索历史弹层）两枚 mini 图标。
  Widget _buildGlassBar(ThemeData theme) {
    final scheme = theme.colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: IgnorePointer(
        // 未完全显现时不拦截手势，保证滚动自然
        ignoring: _glassReveal < 0.99,
        child: Opacity(
          opacity: _glassReveal,
          child: Transform.translate(
            offset: Offset(0, -8 * (1 - _glassReveal)),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.82),
                    border: Border(
                      bottom: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(14, topInset, 18, 10),
                    child: SizedBox(
                      height: 28,
                      child: Row(
                        children: [
                          _GlassIcon(
                            icon: Icons.arrow_back_ios_new_rounded,
                            onTap: () => Navigator.maybePop(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '游戏中心',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          _GlassIcon(
                            icon: Icons.search_rounded,
                            onTap: _scrollToSearch,
                          ),
                          const SizedBox(width: 14),
                          _GlassIcon(
                            icon: Icons.history_rounded,
                            onTap: _showSearchHistorySheet,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 玻璃条 search 图标：回顶并聚焦搜索框
  void _scrollToSearch() {
    _searchFocusNode.requestFocus();
    if (_scrollController.hasClients && _scrollController.offset != 0) {
      unawaited(
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  /// 搜索历史底部弹层：点词条回填搜索框，可一键清空
  Future<void> _showSearchHistorySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _SearchHistorySheet(
        history: List.unmodifiable(_searchHistory),
        onUse: (term) {
          Navigator.pop(sheetContext);
          _searchController.text = term;
          _searchController.selection = TextSelection.collapsed(
            offset: term.length,
          );
          _searchFocusNode.requestFocus();
        },
        onClear: () {
          Navigator.pop(sheetContext);
          setState(() => _searchHistory = const []);
          unawaited(_saveSearchHistory());
        },
      ),
    );
  }

  Widget _buildFeatured() {
    final featured = _featured;
    final safeIndex =
        featured.isEmpty ? 0 : _featuredIndex.clamp(0, featured.length - 1);
    return Column(
      children: [
        SizedBox(
          height: kGcFeaturedHeight,
          child: PageView.builder(
            controller: _featuredController,
            padEnds: false,
            onPageChanged: (i) => setState(() => _featuredIndex = i),
            itemCount: featured.length,
            itemBuilder: (context, index) {
              final demo = featured[index];
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  index == 0 ? kGcPagePadding : 6,
                  4,
                  index == featured.length - 1 ? kGcPagePadding : 6,
                  10,
                ),
                child: GameFeaturedCard(demo: demo, onTap: () => _open(demo)),
              );
            },
          ),
        ),
        if (featured.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < featured.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == safeIndex ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(
                      alpha: i == safeIndex ? 0.9 : 0.25,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCategoryBar() {
    final label = kGameCategoryTabs
        .firstWhere((t) => t.category == _selected)
        .label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: _selected == GameCategory.all ? '全部游戏' : label,
          subtitle: '${_bucket(_selected).length} 款',
          icon: kGameCategoryIcons[_selected] ?? Icons.apps_rounded,
        ),
        SizedBox(
          height: 46,
          child: ListView.separated(
            controller: _chipScrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: kGcPagePadding),
            itemCount: kGameCategoryTabs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final tab = kGameCategoryTabs[index];
              return Center(
                child: GameCategoryChip(
                  label: tab.label,
                  icon: kGameCategoryIcons[tab.category]!,
                  count: _bucket(tab.category).length,
                  selected: _selected == tab.category,
                  onTap: () => _select(tab.category),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 页面内小组件
// ══════════════════════════════════════════════════════════════

/// 分节标题：左侧主题色竖条 + 标题 + 次要说明
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kGcPagePadding,
        18,
        kGcPagePadding,
        10,
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 17, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 收藏轮播空态引导（无收藏时展示在"我的收藏"区块）
class _EmptyFeatured extends StatelessWidget {
  const _EmptyFeatured();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kGcPagePadding),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(kGcCardRadius),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.star_border_rounded,
              size: 38,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 10),
            Text(
              '收藏的游戏会出现在这里',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '点卡片右上角的星标即可收藏',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空分类占位（含搜索无结果）
class _EmptyBucket extends StatelessWidget {
  const _EmptyBucket({required this.category, this.isSearch = false});

  final String category;

  /// true = 因搜索无命中而非分类本身为空，文案随之切换
  final bool isSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFav = category == GameCategory.favorites;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearch
                ? Icons.search_off_rounded
                : isFav
                    ? Icons.star_border_rounded
                    : Icons.videogame_asset_off,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 14),
          Text(
            isSearch ? '没有找到相关游戏' : isFav ? '还没有收藏的游戏' : '暂无此类游戏',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isSearch ? '换个关键词试试，比如「棋」「联机」' : isFav ? '点卡片右上角的星标即可收藏' : '换个分类看看',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// 入场动画使用共享 RevealItem（reveal_item.dart），节奏常量见
// const_game_center.dart 的 kGcReveal*。

// ══════════════════════════════════════════════════════════════
// 头部功能行小组件
// ══════════════════════════════════════════════════════════════

/// 返回钮：40px 方形热区、透明底、radius 12，按下时主题色 18% 底。
/// 对应原型 .backbtn（含玻璃条左端的返回箭头同款规格）。
class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kGcSearchRadius),
        child: SizedBox(
          width: kGcTopRowHeight,
          height: kGcTopRowHeight,
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 21,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// 搜索框内嵌「搜索」提交钮：主色实底、白字、radius 9（原型 .go）。
class _SearchGoButton extends StatelessWidget {
  const _SearchGoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: kGcSearchButtonHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            '搜索',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ),
    );
  }
}

/// 毛玻璃条右侧 mini 图标钮（search / history / 返回箭头共用）
class _GlassIcon extends StatelessWidget {
  const _GlassIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 19, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// 搜索历史底部弹层：词条可点回填，右上角一键清空。
class _SearchHistorySheet extends StatelessWidget {
  const _SearchHistorySheet({
    required this.history,
    required this.onUse,
    required this.onClear,
  });

  final List<String> history;
  final ValueChanged<String> onUse;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  '搜索历史',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onClear,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    '暂无搜索历史',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final term in history)
                    ActionChip(
                      label: Text(term),
                      labelStyle: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                      side: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                      backgroundColor: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                      onPressed: () => onUse(term),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
