// 比价计算器 —— 数据模型与常量
// 手写 toMap/fromMap，避开 TypeAdapter part 文件的 CI 编译坑
// （详见 skill: Flutter-Hive-TypeAdapter-part文件CI构建失败问题）

const String kPriceCompareBoxName = 'price_compare_topics';
const String kPriceCompareLastTopicIdKey = 'last_topic_id';

/// 单行比价数据：资源数量 / 金额 / 备注（品牌等）。
/// 前端数字保存为 String（跟 TextField 天然对齐），
/// 在需要计算时才 tryParse。
class PriceRow {
  PriceRow({
    this.resource = '',
    this.amount = '',
    this.note = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String resource; // 资源数量（前）
  String amount; // 金额（后）
  String note; // 备注：品牌/规格/购买渠道
  DateTime createdAt; // 本行创建时间

  double? get numResource => double.tryParse(resource.trim());
  double? get numAmount => double.tryParse(amount.trim());

  /// 单价 = 金额 / 资源；任一非法或资源=0 返回 null
  double? get unitPrice {
    final r = numResource;
    final a = numAmount;
    if (r == null || a == null || r == 0) return null;
    return a / r;
  }

  Map<String, dynamic> toMap() => {
        'r': resource,
        'a': amount,
        'n': note,
        'c': createdAt.millisecondsSinceEpoch,
      };

  static PriceRow fromMap(Map m) => PriceRow(
        resource: (m['r'] ?? '') as String,
        amount: (m['a'] ?? '') as String,
        note: (m['n'] ?? '') as String,
        // 兼容老数据（无 'c' 字段）：给一个近似时间，不影响使用
        createdAt: m['c'] is int
            ? DateTime.fromMillisecondsSinceEpoch(m['c'] as int)
            : DateTime.now(),
      );
}

class PriceTopic {
  PriceTopic({
    required this.id,
    this.title = '',
    List<PriceRow>? rows,
    DateTime? createdAt,
  })  : rows = rows ?? [PriceRow(), PriceRow()],
        createdAt = createdAt ?? DateTime.now();

  final String id;
  String title;
  List<PriceRow> rows;
  final DateTime createdAt; // 主题创建时间（不变）

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'rows': rows.map((e) => e.toMap()).toList(),
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  static PriceTopic fromMap(Map m) => PriceTopic(
        id: (m['id'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        rows: (m['rows'] as List? ?? [])
            .map((e) => PriceRow.fromMap(e as Map))
            .toList(),
        // 兼容老数据（早期版本无 createdAt）：用 updatedAt 兜底，再兜底当前时间
        createdAt: m['createdAt'] is int
            ? DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int)
            : (m['updatedAt'] is int
                ? DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int)
                : DateTime.now()),
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

/// 时间格式化：智能显示——今天只显示时分，其它显示 M/d，跨年显示 y/M/d
String formatCreatedAt(DateTime t) {
  final now = DateTime.now();
  final isSameDay =
      t.year == now.year && t.month == now.month && t.day == now.day;
  if (isSameDay) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
  if (t.year == now.year) {
    return '${t.month}/${t.day}';
  }
  return '${t.year}/${t.month}/${t.day}';
}

/// 完整时间：yyyy/MM/dd HH:mm，主题创建时间副标题用
String formatFullDate(DateTime t) {
  String p(int n) => n.toString().padLeft(2, '0');
  return '${t.year}/${p(t.month)}/${p(t.day)} ${p(t.hour)}:${p(t.minute)}';
}
