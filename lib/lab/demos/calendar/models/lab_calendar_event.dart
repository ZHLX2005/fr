/// 日历待办事项数据模型
class LabCalendarEvent {
  final String id;
  final int year;
  final int month; // 1-12
  final int day;   // 1-31
  final String title;
  final String color; // #RRGGBB
  final String? description;
  final DateTime createdAt;

  /// 系统日历事件 ID，null 表示未同步到系统日历
  final int? systemCalendarEventId;

  const LabCalendarEvent({
    required this.id,
    required this.year,
    required this.month,
    required this.day,
    required this.title,
    required this.color,
    this.description,
    required this.createdAt,
    this.systemCalendarEventId,
  });

  /// 该事件归属的日期键，用于按天分组
  String get dateKey =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  /// 是否已同步到系统日历
  bool get isSyncedToSystemCalendar => systemCalendarEventId != null;

  LabCalendarEvent copyWith({
    String? id,
    int? year,
    int? month,
    int? day,
    String? title,
    String? color,
    String? description,
    DateTime? createdAt,
    int? systemCalendarEventId,
  }) {
    return LabCalendarEvent(
      id: id ?? this.id,
      year: year ?? this.year,
      month: month ?? this.month,
      day: day ?? this.day,
      title: title ?? this.title,
      color: color ?? this.color,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      systemCalendarEventId: systemCalendarEventId ?? this.systemCalendarEventId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'year': year,
    'month': month,
    'day': day,
    'title': title,
    'color': color,
    'description': description,
    'createdAt': createdAt.toIso8601String(),
    if (systemCalendarEventId != null)
      'systemCalendarEventId': systemCalendarEventId,
  };

  factory LabCalendarEvent.fromJson(Map<String, dynamic> j) => LabCalendarEvent(
    id: j['id'] as String,
    year: j['year'] as int,
    month: j['month'] as int,
    day: j['day'] as int,
    title: j['title'] as String,
    color: j['color'] as String,
    description: j['description'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String),
    systemCalendarEventId: j['systemCalendarEventId'] as int?,
  );
}

/// 预设颜色板
const List<String> kLabCalendarPalette = [
  '#F44336', // 红
  '#FF9800', // 橙
  '#FFC107', // 黄
  '#4CAF50', // 绿
  '#00BCD4', // 青
  '#2196F3', // 蓝
  '#9C27B0', // 紫
  '#795548', // 棕
];
