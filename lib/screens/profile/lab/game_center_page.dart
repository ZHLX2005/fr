// 游戏中心 - 主页直入的独立游戏列表页面
//
// 通过 part of 复用 LabPage 的 _DemoDetailPage 与 LabCardProvider,保持
// 与 LabPage 同一套打开/收藏体验,零组件代码重复。
//
// 布局：每个游戏独占一行（ListView），上层 16:9 封面（按分类占位 icon），
// 下层标题 + 描述 + 右上角收藏星标。
//
// 分类设计：DemoPage 不加新字段；归类由本页 _categoryOf 用 is-类型判断完成。
// 添加新游戏：① 让新 demo override `type => DemoType.game` ② 在 _categoryOf 加
// 一条 `is` 分支（同时加入 _categoryLabels / _categoryIcon）。
// 空分类 tab 仍显示"暂无此类游戏"占位，便于后续补足。

part of 'lab_page.dart';

class GameCenterPage extends StatefulWidget {
  const GameCenterPage({super.key});

  @override
  State<GameCenterPage> createState() => _GameCenterViewState();
}

class _GameCenterViewState extends State<GameCenterPage>
    with TickerProviderStateMixin {
  // Tab 显示顺序与 label；首位为 GameCategory.favorites（按收藏过滤），
  // 第二位 GameCategory.all 兜底"全部"。改顺序 / 改名称 = 改这个列表
  // （与 _categoryOf / _categoryIcon 分支对应维护）。
  static const List<({String category, String label})> _categoryLabels = [
    (category: GameCategory.favorites, label: '收藏'),
    (category: GameCategory.all, label: '全部'),
    (category: GameCategory.arcade, label: '街机'),
    (category: GameCategory.multiplayer, label: '联机'),
    (category: GameCategory.board, label: '棋游'),
    (category: GameCategory.puzzle, label: '益智'),
    (category: GameCategory.music, label: '音游'),
  ];

  // 分类 → 封面占位 icon。无封面图时用分类语义提示用户大致玩法。
  // favorites 单独映射为星标 icon，与卡片右上角星标呼应。
  static const Map<String, IconData> _categoryIcon = {
    GameCategory.favorites: Icons.star,
    GameCategory.arcade: Icons.sports_esports,
    GameCategory.multiplayer: Icons.people_outline,
    GameCategory.board: Icons.grid_4x4,
    GameCategory.puzzle: Icons.extension,
    GameCategory.music: Icons.music_note,
  };

  late final TabController _tabController;
  late final AnimationController _revealController;
  late final LabCardProvider _provider;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categoryLabels.length, vsync: this);
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // 切 Tab 时重放进场动画，让用户感知列表刷新
    _tabController.addListener(_onTabChanged);
    _revealController.forward();
    // 收藏 tab 需要在用户点星标时实时刷新；
    // 复用 LabCardProvider 单例，避免 _GameRowCard 与本页 state 双订阅竞争。
    _provider = LabCardProvider();
    _provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _revealController.dispose();
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      _revealController.forward(from: 0.0);
    }
  }

  /// 把 demo 映射到 GameCategory 字符串。覆盖 6 个现有 game demo + 兜底。
  String _categoryOf(DemoPage d) {
    if (d is SnakeGameDemo) return GameCategory.arcade;
    if (d is SurroundGameDemo) return GameCategory.multiplayer;
    if (d is ReversiDemo) return GameCategory.board;
    if (d is JungleChessDemo) return GameCategory.board;
    if (d is Game2048Demo) return GameCategory.puzzle;
    if (d is LineDemo) return GameCategory.music;
    return GameCategory.arcade; // 兜底：新加入未分类的 game demo 暂归街机
  }

  /// 按 category 取 demo 子集。
  /// - `all` 返回全集（按注册顺序）
  /// - `favorites` 返回 LabCardProvider 中标记为收藏的 game demo
  /// - 其余按 _categoryOf 归类
  List<MapEntry<String, DemoPage>> _bucket(String category) {
    final all = demoRegistry.getAll().filterByType(DemoType.game);
    if (category == GameCategory.all) return all;
    if (category == GameCategory.favorites) {
      return all.where((e) => _provider.isFavorite(e.value.title)).toList();
    }
    return all.where((e) => _categoryOf(e.value) == category).toList();
  }

  void _openDemo(BuildContext context, DemoPage demo) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _DemoDetailPage(demo: demo)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('游戏中心'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final c in _categoryLabels) Tab(text: c.label)],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          for (final c in _categoryLabels)
            _buildBucketTab(theme: theme, category: c.category),
        ],
      ),
    );
  }

  Widget _buildBucketTab({required ThemeData theme, required String category}) {
    final demos = _bucket(category);
    if (demos.isEmpty) {
      return _EmptyBucket(theme: theme);
    }
    return ListView.builder(
      controller: ScrollController(),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: demos.length,
      itemBuilder: (context, index) {
        final demo = demos[index].value;
        return Padding(
          padding: EdgeInsets.only(bottom: index == demos.length - 1 ? 0 : 12),
          child: _RevealItem(
            index: index,
            controller: _revealController,
            child: _GameRowCard(
              demo: demo,
              icon: _iconFor(category),
              onTap: () => _openDemo(context, demo),
            ),
          ),
        );
      },
    );
  }

  IconData _iconFor(String category) {
    // 全部 tab 用 arcade icon 兜底；具体分类查表。
    if (category == GameCategory.all) {
      return _categoryIcon[GameCategory.arcade]!;
    }
    return _categoryIcon[category] ?? _categoryIcon[GameCategory.arcade]!;
  }
}

/// 游戏行卡片：上层 16:9 分类占位封面，下层标题/描述/收藏星标。
class _GameRowCard extends StatefulWidget {
  const _GameRowCard({
    required this.demo,
    required this.icon,
    required this.onTap,
  });

  final DemoPage demo;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_GameRowCard> createState() => _GameRowCardState();
}

class _GameRowCardState extends State<_GameRowCard> {
  late final LabCardProvider _provider = LabCardProvider();

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  bool get _isFavorite => _provider.isFavorite(widget.demo.title);

  Future<void> _toggleFavorite() async {
    await _provider.setFavorite(widget.demo.title, !_isFavorite);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFav = _isFavorite;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 上层：分类占位封面
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _CoverPlaceholder(icon: widget.icon),
                ),
                // 下层：标题 + 描述
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.demo.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.demo.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // 收藏星标：浮在封面右上角；用 Material 透传点击
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black.withValues(alpha: 0.35),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: isFav ? '取消收藏' : '收藏',
                  icon: Icon(
                    isFav ? Icons.star : Icons.star_border,
                    color: isFav ? Colors.amber : Colors.white,
                  ),
                  onPressed: _toggleFavorite,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分类占位封面：渐变背景 + 居中 icon。无真实图片时用此占位。
class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: 56,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

/// 空分类占位 widget。
class _EmptyBucket extends StatelessWidget {
  const _EmptyBucket({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.videogame_asset_off,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无此类游戏',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
