import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 网格视图 Demo - 数据看板/课表编排
class GridDashboardDemo extends DemoPage {
  @override
  String get title => '网格视图';

  @override
  String get description => '类似数据看板、课表编排的网格布局';

  @override
  Widget buildPage(BuildContext context) {
    return const _GridDashboardPage();
  }
}

/// 模拟数据
class DashboardData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final int span;

  const DashboardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.span = 1,
  });
}

class _GridDashboardPage extends StatefulWidget {
  const _GridDashboardPage();

  @override
  State<_GridDashboardPage> createState() => _GridDashboardPageState();
}

class _GridDashboardPageState extends State<_GridDashboardPage> {
  final List<DashboardData> _dashboardItems = const [
    DashboardData(
      title: '今日收益',
      value: '¥12,580',
      icon: Icons.account_balance_wallet,
      color: Colors.green,
    ),
    DashboardData(
      title: '订单数量',
      value: '328',
      icon: Icons.shopping_cart,
      color: Colors.blue,
    ),
    DashboardData(
      title: '新增用户',
      value: '+86',
      icon: Icons.person_add,
      color: Colors.orange,
    ),
    DashboardData(
      title: '活跃度',
      value: '92%',
      icon: Icons.trending_up,
      color: Colors.purple,
    ),
    DashboardData(
      title: '课表',
      value: '5节/天',
      icon: Icons.calendar_today,
      color: Colors.teal,
      span: 2,
    ),
    DashboardData(
      title: '消息',
      value: '12',
      icon: Icons.message,
      color: Colors.red,
    ),
    DashboardData(
      title: '待办事项',
      value: '8',
      icon: Icons.checklist,
      color: Colors.indigo,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // 折叠式圆角渐变头部
          SliverPersistentHeader(
            pinned: false,
            delegate: _CollapsingHeaderDelegate(
              expandedHeight: 200,
              minHeight: 80,
              maxRadius: 40,
            ),
          ),
          // 内容区顶部圆角覆盖
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '数据看板',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '网格视图布局示例',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 标准 2 列网格
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '标准 2 列网格',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStandardGrid(),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          // 交错网格
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '交错网格 (Staggered)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStaggeredGrid(),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          // 课表视图
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '课表视图',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildScheduleGrid(),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildStandardGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _dashboardItems
              .take(4)
              .map(
                (item) => SizedBox(
                  width: width,
                  child: _DashboardCard(data: item),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildStaggeredGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final halfWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _dashboardItems.map((item) {
            final width =
                item.span > 1 ? constraints.maxWidth : halfWidth;
            return SizedBox(
              width: width,
              height: item.span > 1 ? 160 : 100,
              child: _DashboardCard(data: item),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildScheduleGrid() {
    final scheduleData = [
      ['08:00', '数学', '英语', '物理', '化学', '数学'],
      ['09:00', '英语', '数学', '数学', '物理', '英语'],
      ['10:00', '物理', '化学', '英语', '数学', '物理'],
      ['11:00', '化学', '物理', '化学', '英语', '化学'],
      ['14:00', '体育', '美术', '音乐', '体育', '班会'],
      ['15:00', '自习', '自习', '自习', '自习', '自习'],
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Table(
          border: TableBorder.all(color: Colors.grey.shade300),
          defaultColumnWidth: const FixedColumnWidth(60),
          children: [
            TableRow(
              decoration: BoxDecoration(color: Colors.blue.shade50),
              children: [
                _tableCell('时间', isHeader: true),
                _tableCell('周一', isHeader: true),
                _tableCell('周二', isHeader: true),
                _tableCell('周三', isHeader: true),
                _tableCell('周四', isHeader: true),
                _tableCell('周五', isHeader: true),
              ],
            ),
            ...scheduleData.map(
              (row) => TableRow(
                children: [
                  _tableCell(row[0]),
                  _tableCell(row[1], course: row[1]),
                  _tableCell(row[2], course: row[2]),
                  _tableCell(row[3], course: row[3]),
                  _tableCell(row[4], course: row[4]),
                  _tableCell(row[5], course: row[5]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tableCell(String text, {bool isHeader = false, String? course}) {
    final color = course != null ? _getCourseColor(course) : null;
    return Container(
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color?.withValues(alpha: 0.1)),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: color,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _getCourseColor(String course) {
    switch (course) {
      case '数学':
        return Colors.blue;
      case '英语':
        return Colors.green;
      case '物理':
        return Colors.orange;
      case '化学':
        return Colors.purple;
      case '体育':
        return Colors.red;
      case '美术':
        return Colors.pink;
      case '音乐':
        return Colors.teal;
      case '班会':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }
}

/// 折叠式圆角渐变头部 Delegate
/// 参考日记头部 demo 的压缩圆角效果，迁移到 SliverPersistentHeader
class _CollapsingHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double expandedHeight;
  final double minHeight;
  final double maxRadius;

  _CollapsingHeaderDelegate({
    required this.expandedHeight,
    required this.minHeight,
    required this.maxRadius,
  });

  @override
  double get maxExtent => expandedHeight;

  @override
  double get minExtent => minHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // 折叠进度: 0.0(展开) -> 1.0(完全折叠)
    final t = (shrinkOffset / (expandedHeight - minHeight)).clamp(0.0, 1.0);

    // 圆角从 maxRadius 渐变到 0
    final radius = maxRadius * (1 - t);

    // 标题字号从 28 渐变到 18
    final titleSize = 28 - (28 - 18) * t;

    // 副标题透明度
    final subtitleOpacity = 1.0 - t;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 渐变背景块（底部圆角）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF6C63FF),
                  const Color(0xFF4ECDC4),
                ],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(radius),
                bottomRight: Radius.circular(radius),
              ),
            ),
          ),
        ),
        // 安全区域内容
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12 * (1 - t)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 标题行
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '数据看板',
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // 日期选择器
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: Colors.white,
                            size: 14,
                          ),
                          SizedBox(width: 6),
                          Text(
                            '今天',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 副标题（随折叠淡出）
                Opacity(
                  opacity: subtitleOpacity,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '网格布局 · 课表编排 · 数据可视化',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
                // 统计摘要（随折叠淡出）
                Opacity(
                  opacity: subtitleOpacity,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        _buildSummaryChip('7项指标', Icons.dashboard),
                        const SizedBox(width: 8),
                        _buildSummaryChip('6行课表', Icons.table_chart),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CollapsingHeaderDelegate oldDelegate) {
    return oldDelegate.expandedHeight != expandedHeight ||
        oldDelegate.minHeight != minHeight ||
        oldDelegate.maxRadius != maxRadius;
  }
}

class _DashboardCard extends StatelessWidget {
  final DashboardData data;
  const _DashboardCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              data.color.withValues(alpha: 0.1),
              data.color.withValues(alpha: 0.05),
            ],
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(data.icon, color: data.color, size: 20),
                if (data.span > 1)
                  Flexible(
                    child: Text(
                      data.title,
                      style: TextStyle(
                        fontSize: 10,
                        color: data.color,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.value,
                  style: TextStyle(
                    fontSize: data.span > 1 ? 24 : 18,
                    fontWeight: FontWeight.bold,
                    color: data.color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (data.span == 1)
                  Text(
                    data.title,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void registerGridDashboardDemo() {
  demoRegistry.register(GridDashboardDemo());
}
