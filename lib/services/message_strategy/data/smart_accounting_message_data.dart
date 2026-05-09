import '../interfaces/message_data.dart';

/// 消费分类
class AccountingCategory {
  final String id;
  final String name;
  final String icon;

  const AccountingCategory({
    required this.id,
    required this.name,
    required this.icon,
  });

  static const List<AccountingCategory> defaults = [
    AccountingCategory(id: 'food', name: '餐饮', icon: '🍜'),
    AccountingCategory(id: 'transport', name: '交通', icon: '🚗'),
    AccountingCategory(id: 'shopping', name: '购物', icon: '🛍️'),
    AccountingCategory(id: 'entertainment', name: '娱乐', icon: '🎮'),
    AccountingCategory(id: 'medical', name: '医疗', icon: '🏥'),
    AccountingCategory(id: 'other', name: '其他', icon: '📦'),
  ];
}

/// 智能记账消息数据
class SmartAccountingMessageData implements IMessageData {
  /// AI识别标签
  final String aiTag;

  /// 识别时间
  final String recognizedTime;

  /// 分类
  final AccountingCategory category;

  /// 备注描述
  final String description;

  /// 金额
  final double amount;

  SmartAccountingMessageData({
    this.aiTag = 'AI识别',
    required this.recognizedTime,
    required this.category,
    required this.description,
    required this.amount,
  });

  @override
  String get type => 'smart_accounting';
}
