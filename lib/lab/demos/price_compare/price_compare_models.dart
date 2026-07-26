// 比价计算器 —— 数据模型与常量
// 手写 toMap/fromMap，避开 TypeAdapter part 文件的 CI 编译坑
// （详见 skill: Flutter-Hive-TypeAdapter-part文件CI构建失败问题）

const String kPriceCompareBoxName = 'price_compare_topics';
const String kPriceCompareLastTopicIdKey = 'last_topic_id';

/// 单行比价数据：资源数量 / 金额。
/// 前端保存为 String（跟 TextField 天然对齐），
/// 在需要计算时才 tryParse。
class PriceRow {
  PriceRow({this.resource = '', this.amount = ''});

  String resource;
  String amount;

  double? get numResource => double.tryParse(resource.trim());
  double? get numAmount => double.tryParse(amount.trim());

  /// 单价 = 金额 / 资源；任一非法或资源=0 返回 null
  double? get unitPrice {
    final r = numResource;
    final a = numAmount;
    if (r == null || a == null || r == 0) return null;
    return a / r;
  }

  Map<String, dynamic> toMap() => {'r': resource, 'a': amount};

  static PriceRow fromMap(Map m) => PriceRow(
        resource: (m['r'] ?? '') as String,
        amount: (m['a'] ?? '') as String,
      );
}

class PriceTopic {
  PriceTopic({required this.id, this.title = '', List<PriceRow>? rows})
      : rows = rows ?? [PriceRow(), PriceRow()];

  final String id;
  String title;
  List<PriceRow> rows;

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'rows': rows.map((e) => e.toMap()).toList(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  static PriceTopic fromMap(Map m) => PriceTopic(
        id: (m['id'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        rows: (m['rows'] as List? ?? [])
            .map((e) => PriceRow.fromMap(e as Map))
            .toList(),
      );
}

/// 数字格式化：4 位有效小数，去尾零
String formatUnitPrice(double v) {
  if (v.isNaN || v.isInfinite) return '—';
  var s = v.toStringAsFixed(4);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}
