import 'dart:convert';

/// 单条小票条目（资源/数量/单价/备注）。
/// 单价由后端 LLM 直接给，前端不做除法，避免歧义。
class LineItem {
  final String resource;
  final double quantity;
  final double unitPrice;
  final String note;
  /// 该商品所属分类，由 LLM 推断（满足"每行默认主题 AI 生成"需求）。
  final String defaultTopic;
  /// 该行在交互卡里的记录状态（持久化，重进页面恢复，不随页面重建丢失）。
  final ReceiptLineStatus status;
  /// 已记入的主题 ID（Hive box key）；''=未记入。
  final String recordedTopicId;
  /// 已记入/改主题后显示的主题标题；''=未记入。
  final String recordedTopicTitle;

  const LineItem({
    required this.resource,
    required this.quantity,
    required this.unitPrice,
    required this.note,
    this.defaultTopic = '',
    this.status = ReceiptLineStatus.pending,
    this.recordedTopicId = '',
    this.recordedTopicTitle = '',
  });

  Map<String, dynamic> toJson() => {
        'resource': resource,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'note': note,
        'defaultTopic': defaultTopic,
        'status': status.name,
        'recordedTopicId': recordedTopicId,
        'recordedTopicTitle': recordedTopicTitle,
      };

  static LineItem fromJson(Map<String, dynamic> m) => LineItem(
        resource: (m['resource'] as String?) ?? '',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (m['unitPrice'] as num?)?.toDouble() ?? 0,
        note: (m['note'] as String?) ?? '',
        defaultTopic: (m['defaultTopic'] as String?) ?? '',
        status: _statusFrom(m['status']),
        recordedTopicId: (m['recordedTopicId'] as String?) ?? '',
        recordedTopicTitle: (m['recordedTopicTitle'] as String?) ?? '',
      );

  static ReceiptLineStatus _statusFrom(Object? s) {
    for (final v in ReceiptLineStatus.values) {
      if (v.name == s) return v;
    }
    return ReceiptLineStatus.pending; // 旧数据无 status → 按 pending
  }
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

  /// 从 flex 接口返回的 content（可能裹在 ```json 代码块里）解析。
  /// 解析失败抛 [FormatException]，调用方需 catch。
  factory ReceiptResult.fromFlexContent(String content) {
    final jsonStr = _stripCodeFence(content);
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('flex content 非合法 JSON: $e\n---\n$jsonStr');
    }

    final itemsRaw = json['items'] as List? ?? [];
    final items = itemsRaw.map((e) {
      final m = e as Map<String, dynamic>;
      return LineItem(
        resource: (m['name'] as String?) ?? '',
        quantity: (m['quantity'] as num?)?.toDouble() ?? 0,
        unitPrice: (m['unit_price'] as num?)?.toDouble() ?? 0,
        note: (m['note'] as String?) ?? '',
        defaultTopic: (m['default_topic'] as String?) ?? '',
      );
    }).toList();

    return ReceiptResult(
      storeName: (json['store_name'] as String?) ?? '',
      purchasedAt: _parseTime(json['purchased_at'] as String?) ?? DateTime.now(),
      recommendedTopic: (json['recommended_topic'] as String?) ?? '',
      items: items,
    );
  }

  /// 剥掉 ```json ... ``` 代码块包裹；没有代码块则原样返回。
  static String _stripCodeFence(String content) {
    final fenced = RegExp(r'```(?:json)?\s*(\{.*\})\s*```', dotAll: true)
        .firstMatch(content);
    if (fenced != null) return fenced.group(1)!.trim();
    final plain = RegExp(r'\{.*\}', dotAll: true).firstMatch(content);
    return plain != null ? plain.group(0)!.trim() : content.trim();
  }

  static DateTime? _parseTime(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s) ??
        DateTime.tryParse(s.replaceAll(' ', 'T'));
  }
}

/// 单行在交互卡里的状态。
enum ReceiptLineStatus { pending, recorded, rejected }