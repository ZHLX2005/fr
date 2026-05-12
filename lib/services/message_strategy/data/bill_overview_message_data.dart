import '../interfaces/message_data.dart';

/// 分类支出项
class CategoryExpense {
  final String categoryId;
  final String categoryName;
  final String icon;
  final double amount;
  final double percentage;

  const CategoryExpense({
    required this.categoryId,
    required this.categoryName,
    required this.icon,
    required this.amount,
    required this.percentage,
  });
}

/// 账单全景消息数据
class BillOverviewMessageData implements IMessageData {
  /// AI汇总标签
  final String aiTag;

  /// 账单月份
  final String month;

  /// 总支出
  final double totalExpense;

  /// 总收入
  final double totalIncome;

  /// 结余
  final double balance;

  /// 分类支出列表
  final List<CategoryExpense> categoryExpenses;

  /// 最高单笔消费
  final CategoryExpense? topExpense;

  BillOverviewMessageData({
    this.aiTag = 'AI汇总',
    required this.month,
    required this.totalExpense,
    required this.totalIncome,
    required this.balance,
    required this.categoryExpenses,
    this.topExpense,
  });

  @override
  String get type => 'bill_overview';
}
