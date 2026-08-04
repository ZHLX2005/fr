/// 单条小票条目（资源/数量/单价/备注）。
/// 单价由后端 LLM 直接给，前端不做除法，避免歧义。
class LineItem {
  final String resource;
  final double quantity;
  final double unitPrice;
  final String note;

  const LineItem({
    required this.resource,
    required this.quantity,
    required this.unitPrice,
    required this.note,
  });
}

/// 整张小票识别结果。
class ReceiptResult {
  final String storeName;
  final DateTime purchasedAt;
  final List<LineItem> items;
  /// LLM 给的主题推荐，前端可被用户覆盖。
  final String recommendedTopic;

  const ReceiptResult({
    required this.storeName,
    required this.purchasedAt,
    required this.items,
    required this.recommendedTopic,
  });
}

/// 单行在交互卡里的状态。
enum ReceiptLineStatus { pending, recorded, rejected }