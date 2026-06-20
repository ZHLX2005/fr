// 游戏中心 - 主页直入的独立游戏列表页面
//
// 通过 part of 复用 LabPage 的 _ScrollRevealGrid / _openDemoPage / _DemoDetailPage
// 等私有 widget，保持与 LabPage 同一套渲染/打开/收藏/背景图体验，零组件代码重复。
//
// 分类设计：DemoPage 不加新字段；归类由本页 _categoryOf 用 is-类型判断完成。
// 添加新游戏：① 让新 demo override `type => DemoType.game` ② 在 _categoryOf 加
// 一条 `is` 分支（同时加入 _categoryLabels / _orderedCategories）。
// 空分类 tab 仍显示"暂无此类游戏"占位，便于后续补足。

part of 'lab_page.dart';

class GameCenterPage extends StatefulWidget {
  const GameCenterPage({super.key});

  @override
  State<GameCenterPage> createState() => _GameCenterViewState();
}

class _GameCenterViewState extends State<GameCenterPage>
    with SingleTickerProviderStateMixin {
  // Tab 显示顺序与 label；首位固定为 GameCategory.all 兜底"全部"。
  // 改顺序 / 改名称 = 改这个列表（与 _categoryOf 分支对应维护）。
  static const List<({String category, String label})> _categoryLabels = [
    (category: GameCategory.all, label: '全部'),
    (category: GameCategory.arcade, label: '街机'),
    (category: GameCategory.multiplayer, label: '联机'),
    (category: GameCategory.board, label: '棋游'),
    (category: GameCategory.puzzle, label: '益智'),
    (category: GameCategory.music, label: '音游'),
  ];

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categoryLabels.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 把 demo 映射到 GameCategory 字符串。覆盖 5 个现有 game demo + 兜底。
  String _categoryOf(DemoPage d) {
    if (d is SnakeGameDemo) return GameCategory.arcade;
    if (d is SurroundGameDemo) return GameCategory.multiplayer;
    if (d is ReversiDemo) return GameCategory.board;
    if (d is Game2048Demo) return GameCategory.puzzle;
    if (d is LineDemo) return GameCategory.music;
    return GameCategory.arcade; // 兜底：新加入未分类的 game demo 暂归街机
  }

  /// 按 category 取 demo 子集。`all` 返回全集（按注册顺序）。
  List<MapEntry<String, DemoPage>> _bucket(String category) {
    final all = demoRegistry.getAll().filterByType(DemoType.game);
    if (category == GameCategory.all) return all;
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
    return _ScrollRevealGrid(
      demos: demos,
      controller: ScrollController(),
      onDemoTap: (demo) => _openDemo(context, demo),
      physics: const BouncingScrollPhysics(),
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
