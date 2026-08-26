import 'package:meta/meta.dart';

import 'anchor.dart';
import 'period.dart';
import 'person_patch.dart';

/// 事件类型
enum EventType { birthday, anniversary, countdown, holiday, task, custom }

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

/// 事件 —— v2 形态：anchor + Period + 内嵌 people。
///
/// 历史 v1 字段（`recurrence` / `everyNDays` / `solarYearOffset` /
/// `lunarAnchorYear`）已删除；老数据走 `EventV1Migration` 一次性迁移。
@immutable
class Event {
  final String id;
  final String title;
  final EventType type;
  final Anchor anchor;
  final Period period;
  final ColorTag colorTag;
  final List<PersonPatch> people;
  final String? note;
  final String groupId;
  final DateTime createdAt;
  final int? systemCalendarEventId;

  const Event({
    required this.id,
    required this.title,
    required this.type,
    required this.anchor,
    required this.period,
    required this.colorTag,
    this.people = const [],
    this.note,
    required this.groupId,
    required this.createdAt,
    this.systemCalendarEventId,
  });

  Event copyWith({
    String? title,
    EventType? type,
    Anchor? anchor,
    Period? period,
    ColorTag? colorTag,
    List<PersonPatch>? people,
    String? note,
    int? systemCalendarEventId,
  }) =>
      Event(
        id: id,
        title: title ?? this.title,
        type: type ?? this.type,
        anchor: anchor ?? this.anchor,
        period: period ?? this.period,
        colorTag: colorTag ?? this.colorTag,
        people: people ?? this.people,
        note: note ?? this.note,
        groupId: groupId,
        createdAt: createdAt,
        systemCalendarEventId: systemCalendarEventId ?? this.systemCalendarEventId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type.name,
        'anchor': _anchorToJson(anchor),
        'period': _periodToJson(period),
        'colorTag': colorTag.name,
        'people': people.map(_personPatchToJson).toList(),
        if (note != null) 'note': note,
        'groupId': groupId,
        'createdAt': createdAt.toIso8601String(),
        if (systemCalendarEventId != null)
          'systemCalendarEventId': systemCalendarEventId,
      };

  factory Event.fromJson(Map<String, dynamic> j) => Event(
        id: j['id'] as String,
        title: j['title'] as String,
        type: EventType.values.byName(j['type'] as String),
        anchor: _anchorFromJson(j['anchor'] as Map<String, dynamic>),
        period: _periodFromJson(j['period'] as Map<String, dynamic>),
        colorTag: ColorTag.values.byName(j['colorTag'] as String),
        people: ((j['people'] as List?) ?? const [])
            .map((p) => _personPatchFromJson(p as Map<String, dynamic>))
            .toList(),
        note: j['note'] as String?,
        groupId: (j['groupId'] as String?) ?? 'default',
        createdAt: DateTime.parse(j['createdAt'] as String),
        systemCalendarEventId: j['systemCalendarEventId'] as int?,
      );

  @override
  bool operator ==(Object o) =>
      o is Event &&
      o.id == id &&
      o.title == title &&
      o.type == type &&
      o.anchor == anchor &&
      o.period == period &&
      o.colorTag == colorTag &&
      _listEq(o.people, people) &&
      o.note == note &&
      o.groupId == groupId &&
      o.createdAt == createdAt &&
      o.systemCalendarEventId == systemCalendarEventId;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        type,
        anchor,
        period,
        colorTag,
        Object.hashAll(people),
        note,
        groupId,
        createdAt,
        systemCalendarEventId,
      );

  static bool _listEq(List a, List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

Map<String, dynamic> _anchorToJson(Anchor a) {
  if (a is SolarAnchor) {
    return {'system': 'solar', 'month': a.month, 'day': a.day, 'year': a.year};
  }
  if (a is LunarAnchor) {
    return {
      'system': 'lunar',
      'month': a.month,
      'day': a.day,
      'isLeap': a.isLeap,
      'year': a.year,
    };
  }
  throw StateError('unknown anchor: ${a.runtimeType}');
}

Anchor _anchorFromJson(Map<String, dynamic> j) {
  final sys = j['system'] as String;
  if (sys == 'lunar') {
    return LunarAnchor(
      month: j['month'] as int,
      day: j['day'] as int,
      isLeap: (j['isLeap'] as bool?) ?? false,
      year: j['year'] as int,
    );
  }
  return SolarAnchor(
    month: j['month'] as int,
    day: j['day'] as int,
    year: j['year'] as int,
  );
}

Map<String, dynamic> _periodToJson(Period p) {
  DateTime? iso(DateTime? d) => d?.toIso8601String();
  if (p is OneShotPeriod) return {'kind': 'oneShot'};
  if (p is YearlyPeriod) {
    return {
      'kind': 'yearly',
      if (p.until != null) 'until': iso(p.until),
      if (p.count != null) 'count': p.count,
    };
  }
  if (p is MonthlyDayPeriod) {
    return {
      'kind': 'monthlyDay',
      'day': p.day,
      if (p.until != null) 'until': iso(p.until),
      if (p.count != null) 'count': p.count,
    };
  }
  if (p is MonthlyNthWeekdayPeriod) {
    return {
      'kind': 'monthlyNthWeekday',
      'nth': p.n,
      'weekday': p.weekday,
      if (p.until != null) 'until': iso(p.until),
      if (p.count != null) 'count': p.count,
    };
  }
  if (p is EveryNDaysPeriod) {
    return {
      'kind': 'everyNDays',
      'n': p.n,
      if (p.until != null) 'until': iso(p.until),
      if (p.count != null) 'count': p.count,
    };
  }
  if (p is EveryNWeeksPeriod) {
    return {
      'kind': 'everyNWeeks',
      'n': p.n,
      'weekdays': (p.weekdays.toList()..sort()),
      if (p.until != null) 'until': iso(p.until),
      if (p.count != null) 'count': p.count,
    };
  }
  throw StateError('unknown period: ${p.runtimeType}');
}

Period _periodFromJson(Map<String, dynamic> j) {
  DateTime? parseUntil() => j['until'] == null ? null : DateTime.parse(j['until'] as String);
  int? parseCount() => j['count'] as int?;
  switch (j['kind'] as String) {
    case 'oneShot':
      return const OneShotPeriod();
    case 'yearly':
      return YearlyPeriod(until: parseUntil(), count: parseCount());
    case 'monthlyDay':
      return MonthlyDayPeriod(
        day: j['day'] as int,
        until: parseUntil(),
        count: parseCount(),
      );
    case 'monthlyNthWeekday':
      return MonthlyNthWeekdayPeriod(
        n: j['nth'] as int,
        weekday: j['weekday'] as int,
        until: parseUntil(),
        count: parseCount(),
      );
    case 'everyNDays':
      return EveryNDaysPeriod(
        n: j['n'] as int,
        until: parseUntil(),
        count: parseCount(),
      );
    case 'everyNWeeks':
      return EveryNWeeksPeriod(
        n: j['n'] as int,
        weekdays: (j['weekdays'] as List).cast<int>().toSet(),
        until: parseUntil(),
        count: parseCount(),
      );
  }
  throw StateError('unknown period kind: ${j['kind']}');
}

Map<String, dynamic> _personPatchToJson(PersonPatch p) => {
      if (p.name != null) 'name': p.name,
      if (p.relation != null) 'relation': p.relation!.name,
      if (p.avatarEmoji != null) 'avatar': p.avatarEmoji,
      if (p.note != null) 'note': p.note,
    };

PersonPatch _personPatchFromJson(Map<String, dynamic> j) => PersonPatch(
      name: j['name'] as String?,
      relation: j['relation'] == null
          ? null
          : PersonRelation.values.byName(j['relation'] as String),
      avatarEmoji: j['avatar'] as String?,
      note: j['note'] as String?,
    );