import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/bill_overview_message_data.dart';

/// Strategy for rendering Bill Overview messages (monthly summary with expandable details)
class BillOverviewMessageWidgetStrategy
    extends MessageWidgetStrategy<BillOverviewMessageData> {
  @override
  Widget build(BuildContext context, BillOverviewMessageData data) {
    return _BillOverviewContent(data: data);
  }

  @override
  BillOverviewMessageData createMockData() => BillOverviewMessageData(
        month: '2024年1月',
        totalExpense: 5432.5,
        totalIncome: 12000.0,
        balance: 6567.5,
        categoryExpenses: const [
          CategoryExpense(
            categoryId: 'food',
            categoryName: '餐饮',
            icon: '🍜',
            amount: 1523.5,
            percentage: 28.0,
          ),
          CategoryExpense(
            categoryId: 'transport',
            categoryName: '交通',
            icon: '🚗',
            amount: 856.0,
            percentage: 15.8,
          ),
          CategoryExpense(
            categoryId: 'shopping',
            categoryName: '购物',
            icon: '🛍️',
            amount: 1856.0,
            percentage: 34.2,
          ),
          CategoryExpense(
            categoryId: 'entertainment',
            categoryName: '娱乐',
            icon: '🎮',
            amount: 697.0,
            percentage: 12.8,
          ),
          CategoryExpense(
            categoryId: 'other',
            categoryName: '其他',
            icon: '📦',
            amount: 500.0,
            percentage: 9.2,
          ),
        ],
        topExpense: CategoryExpense(
          categoryId: 'shopping',
          categoryName: '购物',
          icon: '🛍️',
          amount: 1856.0,
          percentage: 34.2,
        ),
      );
}

class _BillOverviewContent extends StatefulWidget {
  final BillOverviewMessageData data;

  const _BillOverviewContent({required this.data});

  @override
  State<_BillOverviewContent> createState() => _BillOverviewContentState();
}

class _BillOverviewContentState extends State<_BillOverviewContent>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 元信息行
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.data.aiTag,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                    Text(
                      widget.data.month,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 三指标网格
                Row(
                  children: [
                    _buildMetricItem(
                      theme,
                      '总支出',
                      '¥ ${widget.data.totalExpense.toStringAsFixed(2)}',
                      theme.colorScheme.error,
                    ),
                    _buildMetricItem(
                      theme,
                      '总收入',
                      '¥ ${widget.data.totalIncome.toStringAsFixed(2)}',
                      Colors.green,
                    ),
                    _buildMetricItem(
                      theme,
                      '结余',
                      '¥ ${widget.data.balance.toStringAsFixed(2)}',
                      theme.colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 图表区
                // 环形图 + 分类占比
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 环形图
                    SizedBox(
                      width: 80,
                      height: 80,
                      child: CustomPaint(
                        painter: _PieChartPainter(
                          expenses: widget.data.categoryExpenses,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '¥',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              Text(
                                widget.data.totalExpense.toStringAsFixed(0),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 分类占比列表
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.data.categoryExpenses
                            .take(4)
                            .map((expense) =>
                                _buildCategoryRow(theme, expense))
                            .toList(),
                      ),
                    ),
                  ],
                ),

                // 高亮提示卡
                if (widget.data.topExpense != null) ...[
                  const SizedBox(height: 12),
                  _buildHighlightCard(theme, widget.data.topExpense!),
                ],
              ],
            ),
          ),

          // 分割线
          Divider(
            height: 1,
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),

          // 操作行
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      // TODO: 导出账单
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('导出账单功能开发中')),
                      );
                    },
                    child: const Text('导出账单'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _toggleExpand,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('查看明细'),
                      AnimatedRotation(
                        turns: _isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 展开区
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: _buildExpandArea(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(
    ThemeData theme,
    String label,
    String value,
    Color color,
  ) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(ThemeData theme, CategoryExpense expense) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(expense.icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              expense.categoryName,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            width: 50,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: expense.percentage / 100,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 40,
            child: Text(
              '${expense.percentage.toStringAsFixed(0)}%',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightCard(ThemeData theme, CategoryExpense expense) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Text(expense.icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '最高单笔消费：${expense.categoryName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          Text(
            '¥ ${expense.amount.toStringAsFixed(2)}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandArea(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 流水列表标题
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            '近期消费',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),

        // 流水列表
        ...widget.data.categoryExpenses.take(3).map((expense) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Text(expense.icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    expense.categoryName,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '-¥ ${expense.amount.toStringAsFixed(2)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
          );
        }),

        // 查看全部
        Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: TextButton(
              onPressed: () {
                // TODO: 跳转原生完整账单页
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('跳转账单页功能开发中')),
                );
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('查看全部记录'),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 环形图Painter
class _PieChartPainter extends CustomPainter {
  final List<CategoryExpense> expenses;

  _PieChartPainter({required this.expenses});

  static const List<Color> _colors = [
    Color(0xFF6366F1), // 蓝
    Color(0xFFF59E0B), // 黄
    Color(0xFF10B981), // 绿
    Color(0xFFEC4899), // 粉
    Color(0xFF8B5CF6), // 紫
    Color(0xFF6B7280), // 灰
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = radius * 0.35;

    double startAngle = -3.14159 / 2; // 从顶部开始

    for (int i = 0; i < expenses.length; i++) {
      final sweepAngle = (expenses[i].percentage / 100) * 2 * 3.14159;
      final paint = Paint()
        ..color = _colors[i % _colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle,
        false,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
