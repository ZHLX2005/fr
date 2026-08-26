import 'package:xiaodouzi_fr/lab/demos/calendar/data/calendar_config.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/event_draft.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/anchor.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/event.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/period.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/person.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/person_patch.dart';

/// v1 → v2 一次性迁移。
///
/// 读取老 Hive `events` box 里的每条记录（v1 是 typed `Event` 对象；
/// v2 改为 untyped Map 后，这里接受 `Map`/`Event`/其它任何值），
/// 尽力识别 v1 形态转 v2 EventDraft。无法识别的记录收集到 droppedIds。
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
    if (raw is Map && raw['id'] is String) return raw['id'] as String;
    return 'unknown_$fallbackIndex';
  }

  static EventDraft? _tryDecode(dynamic raw, {CalendarConfig? config}) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);

    final title = (m['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;

    final type = _parseType(m['type'] as String?);

    // system
    final sys = (m['system'] as String?) ?? 'solar';
    final isLunar = sys == 'lunar';

    // date parts (v1 stores solar-style month/day in calendar of `system`)
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

    // color
    final color = _parseColor(m['colorTag'] as String?);

    // recurrence + period
    Anchor anchor;
    Period period;
    if (everyNDays != null) {
      // every-N-days solar
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
          // drop solarYearOffset (lossy)
          anchor = AnchorFactory.solar(month: month, day: day, year: anchorYear);
          period = PeriodFactory.yearly();
          break;
        case 'none':
        default:
          anchor = AnchorFactory.solar(month: month, day: day, year: anchorYear);
          period = PeriodFactory.oneShot();
      }
    }

    final people = <PersonPatch>[];
    final personId = m['personId'] as String?;
    // 老数据里只有 personId 指针，patch 字段暂时缺失；解析器后置 resolve。

    return EventDraft(
      title: title,
      type: type,
      anchor: anchor,
      period: period,
      colorTag: color,
      people: people,
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