import 'package:xiaodouzi_fr/lab/demos/calendar/data/calendar_config.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/event_draft.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/anchor.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/event.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/period.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/person.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/person_patch.dart';

/// v1 → v2 一次性迁移。
///
/// 读取老 Hive `events` box 里的每条记录：
/// - Map 形态（新装设备的 v2 写盘）：正常 v1→v2 字段映射。
/// - Event 实例（v1 typed 写盘 → v2 用 Box<dynamic> 读取）：用反射（dynamic
///   字段访问）抽取 v1 字段。删除/重命名的字段读不到 → 用默认值。
/// - 其它类型：dropped。
///
/// 无法识别的记录收集到 droppedIds。
///
/// v1 → v2 字段映射：
///   recurrence=yearly + system=solar  → Period.yearly + SolarAnchor
///   recurrence=yearlyLunarAuto        → Period.yearly + LunarAnchor(anchor = lunarAnchorYear ?? year)
///   recurrence=manual                 → Period.yearly + SolarAnchor (offset dropped)
///   recurrence=none                   → Period.oneShot + SolarAnchor
///   everyNDays=N                      → Period.everyNDays(n=N) + SolarAnchor(year, month, day)
class EventV1Migration {
  static ({List<EventDraft> drafts, List<String> droppedIds}) run(
    Iterable<dynamic> rawRecords, {
    CalendarConfig? config,
  }) {
    final drafts = <EventDraft>[];
    final dropped = <String>[];
    var i = 0;
    for (final raw in rawRecords) {
      try {
        final draft = _tryDecode(raw, config: config);
        if (draft != null) {
          drafts.add(draft);
        } else {
          dropped.add(_idOf(raw, fallbackIndex: i));
        }
      } catch (_) {
        dropped.add(_idOf(raw, fallbackIndex: i));
      }
      i++;
    }
    return (drafts: drafts, droppedIds: dropped);
  }

  static String _idOf(dynamic raw, {required int fallbackIndex}) {
    try {
      final id = (raw as dynamic).id;
      if (id is String) return id;
    } catch (_) {}
    if (raw is Map && raw['id'] is String) return raw['id'] as String;
    return 'unknown_$fallbackIndex';
  }

  static EventDraft? _tryDecode(dynamic raw, {CalendarConfig? config}) {
    // 1) Map 形态
    if (raw is Map) {
      return _fromMap(Map<String, dynamic>.from(raw), config: config);
    }
    // 2) 旧 v1 Event 实例（typed box → dynamic 读取）
    if (raw != null && raw is! String && raw is! num && raw is! bool) {
      try {
        final m = _readTypedFields(raw);
        if (m == null) return null;
        return _fromMap(m, config: config);
      } catch (e) {
        // ignore: avoid_print
        print('[EventV1Migration] typed decode failed: $e');
        return null;
      }
    }
    return null;
  }

  /// 用反射从 typed v1 Event 对象读字段；任何字段缺失都返回 null（不是异常）。
  static Map<String, dynamic>? _readTypedFields(dynamic raw) {
    String? id;
    String? title;
    try { id = (raw as dynamic).id as String?; } catch (_) {}
    try { title = ((raw as dynamic).title as String?)?.trim(); } catch (_) {}
    if (id == null || title == null || title.isEmpty) return null;
    String typeStr = 'custom';
    try { typeStr = ((raw as dynamic).type?.toString()) ?? 'custom'; } catch (_) {}
    String sysStr = 'solar';
    try { sysStr = ((raw as dynamic).system?.toString()) ?? 'solar'; } catch (_) {}
    int? year, month, day;
    int? everyNDays;
    int? lunarAnchorYear;
    bool? isLeap;
    String? note, personId, groupId;
    String recStr = 'none';
    String colorStr = 'gray';
    try { year = _safeInt((raw as dynamic).year); } catch (_) {}
    try { month = _safeInt((raw as dynamic).month); } catch (_) {}
    try { day = _safeInt((raw as dynamic).day); } catch (_) {}
    try { recStr = ((raw as dynamic).recurrence?.toString()) ?? 'none'; } catch (_) {}
    try { colorStr = ((raw as dynamic).colorTag?.toString()) ?? 'gray'; } catch (_) {}
    try { everyNDays = _safeInt((raw as dynamic).everyNDays); } catch (_) {}
    try { isLeap = (raw as dynamic).isLeap as bool?; } catch (_) {}
    try { lunarAnchorYear = _safeInt((raw as dynamic).lunarAnchorYear); } catch (_) {}
    try { note = (raw as dynamic).note as String?; } catch (_) {}
    try { personId = (raw as dynamic).personId as String?; } catch (_) {}
    try { groupId = ((raw as dynamic).groupId as String?) ?? 'default'; } catch (_) {}
    return {
      'id': id,
      'title': title,
      'type': typeStr,
      'system': sysStr,
      'year': year,
      'month': month,
      'day': day,
      'recurrence': recStr,
      'colorTag': colorStr,
      'everyNDays': everyNDays,
      'isLeap': isLeap,
      'lunarAnchorYear': lunarAnchorYear,
      'personId': personId,
      'groupId': groupId,
      'note': note,
    };
  }

  static int? _safeInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return null;
  }

  static EventDraft? _fromMap(Map<String, dynamic> m, {CalendarConfig? config}) {
    final title = (m['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;

    final type = _parseType(m['type'] as String?);

    final sys = (m['system'] as String?) ?? 'solar';
    final isLunar = sys == 'lunar';

    final month = m['month'] as int?;
    final day = m['day'] as int?;
    if (month == null || day == null) return null;

    final everyNDays = m['everyNDays'] as int?;
    final recurrence = m['recurrence'] as String? ?? 'none';
    final lunarAnchorYear = m['lunarAnchorYear'] as int?;
    final yearRaw = m['year'] as int?;
    final anchorYear = yearRaw ?? (config?.startDateIso != null
        ? int.parse(config!.startDateIso!.substring(0, 4))
        : DateTime.now().year);

    final color = _parseColor(m['colorTag'] as String?);

    Anchor anchor;
    Period period;
    if (everyNDays != null) {
      anchor = AnchorFactory.solar(month: month, day: day, year: anchorYear);
      period = PeriodFactory.everyNDays(n: everyNDays);
    } else {
      switch (recurrence) {
        case 'yearly':
          anchor = isLunar
              ? AnchorFactory.lunar(month: month, day: day, isLeap: false, year: anchorYear)
              : AnchorFactory.solar(month: month, day: day, year: anchorYear);
          period = PeriodFactory.yearly();
          break;
        case 'yearlyLunarAuto':
          anchor = AnchorFactory.lunar(
            month: month,
            day: day,
            isLeap: (m['isLeap'] as bool?) ?? false,
            year: lunarAnchorYear ?? anchorYear,
          );
          period = PeriodFactory.yearly();
          break;
        case 'manual':
          anchor = AnchorFactory.solar(month: month, day: day, year: anchorYear);
          period = PeriodFactory.yearly();
          break;
        case 'none':
        default:
          anchor = AnchorFactory.solar(month: month, day: day, year: anchorYear);
          period = PeriodFactory.oneShot();
      }
    }

    return EventDraft(
      title: title,
      type: type,
      anchor: anchor,
      period: period,
      colorTag: color,
      note: m['note'] as String?,
    );
  }

  static EventType _parseType(String? s) {
    if (s == null) return EventType.custom;
    for (final t in EventType.values) {
      if (t.name == s) return t;
    }
    return EventType.custom;
  }

  static ColorTag _parseColor(String? s) {
    if (s == null) return ColorTag.gray;
    for (final c in ColorTag.values) {
      if (c.name == s) return c;
    }
    return ColorTag.gray;
  }

  // Suppress unused-import warning on Person (used in real provider code, not here)
  static void _keepImports() {
    PersonRelation.self;
  }
}