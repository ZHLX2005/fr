// 游戏中心 — 独立游戏列表页（主页直入）
//
// 结构（CustomScrollView，自上而下）：
//   ① 透明 AppBar（滚动后标题+底色淡入，返回键始终可点）
//   ② 渐变 Hero 头部：标题 + "N 款游戏 / M 款联机 / K 收藏"统计
//   ③ 精选联机横滑（仅"全部"筛选下出现）
//   ④ 分类过滤 chip（border-emphasis，带数量）
//   ⑤ 自适应列数网格（MaxCrossAxisExtent，平板自动多列）
//
// 分类 / 配色 / 图标登记表在 game_center/const_game_center.dart；
// 卡片组件在 game_center/game_center_cards.dart；封面在 game_center_artwork.dart。
//
// 添加新游戏：demo `override type => DemoType.game` + 在 kGameMeta 里登记一条即可，
// 本文件无需改动。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../lab/lab_container.dart';
import 'demo_detail_page.dart';
import 'game_center/const_game_center.dart';
import 'game_center/game_center_cards.dart';
import 'providers/lab_card_provider.dart';

class GameCenterPage extends StatefulWidget {
  const GameCenterPage({super.key});

  @override
  State<GameCenterPage> createState() => _GameCenterPageState();
}

class _GameCenterPageState extends State<GameCenterPage>
    with TickerProviderStateMixin {
  final _provider = LabCardProvider();
  final _scrollController = ScrollController();
  final _featuredController = PageController(viewportFraction: 0.88);
  late final AnimationController _revealController;

  /// 全部 game 类 demo（按注册顺序，别名 slug 已按实例去重）
  late final List<DemoPage> _games;

  String _selected = GameCategory.all;
  double _titleReveal = 0.0;
  int _featuredIndex = 0;

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

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _scrollController.addListener(_onScroll);
    _provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _featuredController.dispose();
    _revealController.dispose();
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    // 收藏变更会影响"收藏" chip 数量与收藏筛选结果
    if (mounted) setState(() {});
  }

  void _onScroll() {
    final next = (_scrollController.offset / kGcTitleFadeDistance).clamp(
      0.0,
      1.0,
    );
    if ((next - _titleReveal).abs() > 0.01) {
      setState(() => _titleReveal = next);
    }
  }

  // ── 数据 ────────────────────────────────────────────────────

  List<DemoPage> get _featured =>
      _games.where((d) => gameMetaOf(d.slug).isOnline).toList();

  List<DemoPage> _bucket(String category) {
    if (category == GameCategory.all) return _games;
    if (category == GameCategory.favorites) {
      return _games.where((d) => _provider.isFavorite(d.title)).toList();
    }
    return _games
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
  }

  // ── 构建 ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final list = _bucket(_selected);
    final showFeatured =
        _selected == GameCategory.all && _featured.isNotEmpty;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // 「banner 收拢成头部」：AppBar 自身用与 Hero 头部**同一套渐变**按滚动
        // 进度淡入 —— 头部滑走多少，AppBar 就补上多少同色底，交界处不换色系。
        // 前景恒定白色：AppBar 始终压在蓝色上（先是身后的 Hero，后是自己的渐变），
        // 不再出现"白底浅色"与蓝头部对撞的突兀感。
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        flexibleSpace: IgnorePointer(
          child: Opacity(
            opacity: _titleReveal,
            // 必须 SizedBox.expand：AppBar 用 StackFit.passthrough 传下来的是
            // **松约束**，无 child 的 DecoratedBox 会取 constraints.smallest
            // 塌成 0 高，表现就是"滚动后头部整块透明"。
            child: SizedBox.expand(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: _headerGradient(scheme),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(
                        alpha: 0.22 * _titleReveal,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        title: Opacity(opacity: _titleReveal, child: const Text('游戏中心')),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(theme)),
          if (showFeatured) ...[
            SliverToBoxAdapter(
              child: _SectionTitle(
                title: '精选联机',
                subtitle: '与好友同房对战',
                icon: Icons.wifi_tethering_rounded,
              ),
            ),
            SliverToBoxAdapter(child: _buildFeatured()),
          ],
          SliverToBoxAdapter(child: _buildCategoryBar()),
          if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyBucket(category: _selected),
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
                  return _RevealItem(
                    index: index,
                    controller: _revealController,
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
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final scheme = theme.colorScheme;
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final onlineCount = _featured.length;
    final favCount = _games.where((d) => _provider.isFavorite(d.title)).length;

    return Container(
      height: topInset + kGcHeaderHeight,
      decoration: BoxDecoration(
        // 只用 gradient，不叠 color（叠加会出双重色调）；
        // 与 AppBar 共用 _headerGradient，保证滚动衔接不断色。
        gradient: _headerGradient(scheme),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(kGcHeaderBottomRadius),
          bottomRight: Radius.circular(kGcHeaderBottomRadius),
        ),
      ),
      child: Stack(
        children: [
          // 一处极淡的光斑即可，多了会把矮头部塞满
          Positioned(
            right: -34,
            top: topInset - 44,
            child: const _Blob(size: 108, alpha: 0.10),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              kGcPagePadding + 4,
              topInset,
              kGcPagePadding + 4,
              18,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '游戏中心',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                // 概览压成一行小字：数量是参考信息，不该占据视觉主位
                Text(
                  '${_games.length} 款 · 联机 $onlineCount · 收藏 $favCount',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatured() {
    final featured = _featured;
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
                  width: i == _featuredIndex ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(
                      alpha: i == _featuredIndex ? 0.9 : 0.25,
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

/// Hero 头部与 AppBar 共用的渐变。
/// 两处必须同源：AppBar 是"头部滑走后补上的那一截"，用不同色系会在
/// 滚动中途出现明显的色带断层（浅色 surface 撞蓝色 banner）。
LinearGradient _headerGradient(ColorScheme scheme) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [scheme.primary, scheme.tertiary],
);

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
      padding: const EdgeInsets.fromLTRB(kGcPagePadding, 18, kGcPagePadding, 10),
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

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }
}

/// 空分类占位
class _EmptyBucket extends StatelessWidget {
  const _EmptyBucket({required this.category});

  final String category;

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
            isFav ? Icons.star_border_rounded : Icons.videogame_asset_off,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 14),
          Text(
            isFav ? '还没有收藏的游戏' : '暂无此类游戏',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isFav ? '点卡片右上角的星标即可收藏' : '换个分类看看',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// 逐项错峰淡入上移，切分类时重放
class _RevealItem extends StatelessWidget {
  const _RevealItem({
    required this.index,
    required this.controller,
    required this.child,
  });

  final int index;
  final AnimationController controller;
  final Widget child;

  double _progress(double t) {
    final start = (index * 0.05).clamp(0.0, 0.6);
    const dur = 0.3;
    if (t < start) return 0.0;
    if (t >= start + dur) return 1.0;
    return Curves.easeOutCubic.transform((t - start) / dur);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final p = _progress(controller.value);
        if (p >= 1.0) return child;
        return Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - p)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
