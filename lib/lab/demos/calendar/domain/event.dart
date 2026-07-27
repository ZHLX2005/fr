import 'recurrence.dart';

/// 事件类型
enum EventType { birthday, anniversary, countdown, holiday, task, custom }

/// 历法系统
enum CalendarSystem { solar, lunar }

/// 颜色标签（8 色预设，含 hex 给 widget 同步用）
enum ColorTag {
  gray('#9E9E9E'),
  red('#C8553D'),
  orange('#D98E48'),
  amber('#E9B44C'),
  sage('#7A8B6F'),
  teal('#4F7C82'),
  indigo('#5A6B8C'),
  plum('#7A5C7E');
  final String hex;
  const ColorTag(this.hex);
}

/// 事件
class Event {
  final String id;
  final EventType type;
  final String title;
  final CalendarSystem system;
  final int year;     // 首次发生的年份（桌面 widget 用）
  final int month;    // 1-12
  final int day;      // 1-30 (lunar) / 1-31 (solar)
  final int? solarYearOffset; // 仅 manual
  final Recurrence recurrence;
  final String? personId;
  final ColorTag colorTag;
  final String? note;
  final DateTime createdAt;
  final int? systemCalendarEventId; // 系统日历同步 id（保留旧能力）
  /// 农历锚定年：仅 recurrence=yearlyLunarAuto 时使用，存"那次农历月日所在的那一年"
  /// 用于 next_birthday 反推后续年份的对应公历
  final int? lunarAnchorYear;

  const Event({
    required this.id,
    required this.type,
    required this.title,
    required this.system,
    required this.year,
    required this.month,
    required this.day,
    required this.recurrence,
    required this.colorTag,
    required this.createdAt,
    this.solarYearOffset,
    this.personId,
    this.note,
    this.systemCalendarEventId,
    this.lunarAnchorYear,
  });

  Event copyWith({
    EventType? type,
    String? title,
    CalendarSystem? system,
    int? year,
    int? month,
    int? day,
    int? solarYearOffset,
    Recurrence? recurrence,
    String? personId,
    ColorTag? colorTag,
    String? note,
    int? systemCalendarEventId,
    int? lunarAnchorYear,
  }) {
    return Event(
      id: id,
      type: type ?? this.type,
      title: title ?? this.title,
      system: system ?? this.system,
      year: year ?? this.year,
      month: month ?? this.month,
      day: day ?? this.day,
      solarYearOffset: solarYearOffset ?? this.solarYearOffset,
      recurrence: recurrence ?? this.recurrence,
      personId: personId ?? this.personId,
      colorTag: colorTag ?? this.colorTag,
      note: note ?? this.note,
      systemCalendarEventId: systemCalendarEventId ?? this.systemCalendarEventId,
      lunarAnchorYear: lunarAnchorYear ?? this.lunarAnchorYear,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'system': system.name,
        'year': year,
        'month': month,
        'day': day,
        if (solarYearOffset != null) 'solarYearOffset': solarYearOffset,
        'recurrence': recurrence.name,
        if (personId != null) 'personId': personId,
        'colorTag': colorTag.name,
        if (note != null) 'note': note,
        if (systemCalendarEventId != null) 'systemCalendarEventId': systemCalendarEventId,
        if (lunarAnchorYear != null) 'lunarAnchorYear': lunarAnchorYear,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Event.fromJson(Map<String, dynamic> j) => Event(
        id: j['id'] as String,
        type: EventType.values.byName(j['type'] as String),
        title: j['title'] as String,
        system: CalendarSystem.values.byName(j['system'] as String),
        year: (j['year'] as int?) ?? DateTime.now().year,
        month: j['month'] as int,
        day: j['day'] as int,
        solarYearOffset: j['solarYearOffset'] as int?,
        recurrence: Recurrence.values.byName(j['recurrence'] as String),
        personId: j['personId'] as String?,
        colorTag: ColorTag.values.byName(j['colorTag'] as String),
        note: j['note'] as String?,
        systemCalendarEventId: j['systemCalendarEventId'] as int?,
        lunarAnchorYear: j['lunarAnchorYear'] as int?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}