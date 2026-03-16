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
  final int span; // 跨列数 1 或 2

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
  // 模拟数据看板
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
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
          const SizedBox(height: 24),

          // 网格视图 1: 标准 2 列网格
          Text(
            '标准 2 列网格',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          _buildStandardGrid(),

          const SizedBox(height: 32),

          // 网格视图 2: 交错网格（类似瀑布流）
          Text(
            '交错网格 (Staggered)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          _buildStaggeredGrid(),

          const SizedBox(height: 32),

          // 网格视图 3: 课表视图
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
    );
  }

  /// 标准 2 列网格
  Widget _buildStandardGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        final item = _dashboardItems[index];
        return _DashboardCard(data: item);
      },
    );
  }

  /// 交错网格 - 类似 Pinterest/瀑布流
  Widget _buildStaggeredGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: _dashboardItems.length,
      itemBuilder: (context, index) {
        final item = _dashboardItems[index];
        // 让特定卡片跨行
        final isLarge = item.span > 1;
        return SizedBox(
          height: isLarge ? 180 : 120,
          child: _DashboardCard(data: item),
        );
      },
    );
  }

  /// 课表视图
  Widget _buildScheduleGrid() {
    // 课表数据: [时间, 周一, 周二, 周三, 周四, 周五]
    final scheduleData = [
      ['08:00', '数学', '英语', '物理', '化学', '数学'],
      ['09:00', '英语', '数学', '数学', '物理', '英语'],
      ['10:00', '物理', '化学', '英语', '数学', '物理'],
      ['11:00', '化学', '物理', '化学', '英语', '化学'],
      ['14:00', '体育', '美术', '音乐', '体育', '班会'],
      ['15:00', '自习', '自习', '自习', '自习', '自习'],
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 表头
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 60, child: Center(child: Text('时间'))),
                Expanded(child: Center(child: Text('周一'))),
                Expanded(child: Center(child: Text('周二'))),
                Expanded(child: Center(child: Text('周三'))),
                Expanded(child: Center(child: Text('周四'))),
                Expanded(child: Center(child: Text('周五'))),
              ],
            ),
          ),
          // 课表内容
          ...scheduleData.asMap().entries.map((entry) {
            final rowIndex = entry.key;
            final row = entry.value;
            final isEven = rowIndex.isEven;

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isEven ? Colors.white : Colors.grey.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Center(
                      child: Text(
                        row[0],
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  ...row.sublist(1).map((course) => Expanded(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getCourseColor(course).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              course,
                              style: TextStyle(
                                fontSize: 11,
                                color: _getCourseColor(course),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      )),
                ],
              ),
            );
          }),
        ],
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

/// 数据卡片组件
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
              data.color.withOpacity(0.1),
              data.color.withOpacity(0.05),
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(data.icon, color: data.color, size: 24),
                if (data.span > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: data.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      data.title,
                      style: TextStyle(
                        fontSize: 10,
                        color: data.color,
                        fontWeight: FontWeight.bold,
                      ),
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
                    fontSize: data.span > 1 ? 28 : 20,
                    fontWeight: FontWeight.bold,
                    color: data.color,
                  ),
                ),
                if (data.span == 1)
                  Text(
                    data.title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 注册 Demo
void registerGridDashboardDemo() {
  demoRegistry.register(GridDashboardDemo());
}
