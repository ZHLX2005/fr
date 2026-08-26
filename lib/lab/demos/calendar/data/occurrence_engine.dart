import '../domain/anchor.dart';
import '../domain/event.dart';
import '../domain/event_occurrence.dart';
import '../domain/period.dart';
import '../lunar_adapter.dart';

/// 把 `Event` + `Period` 展开为 `EventOccurrence` 列表。
///
/// 所有方法都是纯函数（除构造时持有的 `LunarAdapter`），便于单元测试。
class OccurrenceEngine {
  final LunarAdapter lunar;
  const OccurrenceEngine(this.lunar);

  /// [from, to] 区间（含端点）的所有发生日。
  List<EventOccurrence> occurrencesBetween(
    List<Event> events,
    DateTime from,
    DateTime to,
  ) {
    final out = <EventOccurrence>[];
    for (final e in events) {
      out.addAll(_expand(e, from, to));
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  /// 给定日期上的所有发生日。
  List<EventOccurrence> eventsOn(List<Event> events, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return occurrencesBetween(events, dayStart, dayEnd.subtract(const Duration(seconds: 1)));
  }

  /// [from] 之后（含）最近一次发生。
  DateTime? nextOccurrence(Event e, DateTime from) {
    final occ = _expand(e, from, DateTime(from.year + 5, 12, 31));
    return occ.isEmpty ? null : occ.first.date;
  }

  // ───────── expand by period ─────────

  List<EventOccurrence> _expand(Event e, DateTime from, DateTime to) {
    final p = e.period;
    if (p is OneShotPeriod) {
      final d = _solarDateForAnchor(e.anchor);
      if (d == null) return const [];
      if (d.isBefore(_normStart(from)) || d.isAfter(_normEnd(to))) return const [];
      return [EventOccurrence(event: e, date: d)];
    }
    if (p is YearlyPeriod) return _expandYearly(e, from, to);
    if (p is MonthlyDayPeriod) return _expandMonthlyDay(e, from, to);
    if (p is MonthlyNthWeekdayPeriod) return _expandMonthlyNth(e, from, to);
    if (p is EveryNDaysPeriod) return _expandEveryNDays(e, from, to);
    if (p is EveryNWeeksPeriod) return _expandEveryNWeeks(e, from, to);
    return const [];
  }

  DateTime? _solarDateForAnchor(Anchor a) {
    if (a is SolarAnchor) return DateTime(a.year, a.month, a.day);
    if (a is LunarAnchor) {
      try {
        final s = lunar.toSolar(a.year, a.month, a.day, isLeap: a.isLeap);
        return DateTime(s.year, s.month, s.day);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  DateTime _normStart(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _normEnd(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);

  bool _inRange(DateTime d, DateTime from, DateTime to) =>
      !d.isBefore(_normStart(from)) && !d.isAfter(_normEnd(to));

  List<EventOccurrence> _expandYearly(Event e, DateTime from, DateTime to) {
    final out = <EventOccurrence>[];
    if (e.anchor is SolarAnchor) {
      final a = e.anchor as SolarAnchor;
      for (var y = from.year - 1; y <= to.year + 1; y++) {
        final d = DateTime(y, a.month, a.day);
        if (!_inRange(d, from, to)) continue;
        out.add(EventOccurrence(event: e, date: d));
      }
    } else if (e.anchor is LunarAnchor) {
      final a = e.anchor as LunarAnchor;
      // 尝试 [solarYear-1, solarYear+1]，落在范围内即取
      for (final solarYear in [from.year - 1, from.year, from.year + 1, to.year + 1]) {
        try {
          final s = lunar.toSolar(solarYear, a.month, a.day, isLeap: a.isLeap);
          final d = DateTime(s.year, s.month, s.day);
          if (d.year == solarYear && _inRange(d, from, to)) {
            out.add(EventOccurrence(event: e, date: d));
          }
        } catch (_) {
          // 该年无对应农历月日（如闰月缺失），跳过
        }
      }
    }
    return _applyUntilCount(out, e.period);
  }

  List<EventOccurrence> _expandMonthlyDay(Event e, DateTime from, DateTime to) {
    final p = e.period as MonthlyDayPeriod;
    final out = <EventOccurrence>[];
    final a = e.anchor as SolarAnchor;
    var y = from.year;
    var month = from.month;
    while (DateTime(y, month, 1).isBefore(DateTime(to.year, to.month + 1, 1))) {
      final daysInMonth = _monthLength(y, month);
      if (p.day <= daysInMonth) {
        final d = DateTime(y, month, p.day);
        if (_inRange(d, from, to)) out.add(EventOccurrence(event: e, date: d));
      }
      month++;
      if (month > 12) {
        month = 1;
        y++;
      }
      // 防御无限循环：anchor.year 限制下界
      if (y > to.year + 2) break;
      // 无 anchor.year 时跳过下限检查
      if (a.year > 0 && y < a.year) {
        y = a.year;
        month = 1;
      }
    }
    return _applyUntilCount(out, e.period);
  }

  List<EventOccurrence> _expandMonthlyNth(Event e, DateTime from, DateTime to) {
    final p = e.period as MonthlyNthWeekdayPeriod;
    final out = <EventOccurrence>[];
    var y = from.year;
    var month = from.month;
    while (DateTime(y, month, 1).isBefore(DateTime(to.year, to.month + 1, 1))) {
      final firstWeekday = _firstWeekdayOfMonth(y, month, p.weekday);
      if (firstWeekday != null) {
        final occ = firstWeekday.add(Duration(days: 7 * (p.n - 1)));
        if (occ.month == month && _inRange(occ, from, to)) {
          out.add(EventOccurrence(event: e, date: occ));
        }
      }
      month++;
      if (month > 12) { month = 1; y++; }
      if (y > to.year + 2) break;
    }
    return _applyUntilCount(out, e.period);
  }

  List<EventOccurrence> _expandEveryNDays(Event e, DateTime from, DateTime to) {
    final p = e.period as EveryNDaysPeriod;
    final a = e.anchor as SolarAnchor;
    final start = DateTime(a.year, a.month, a.day);
    final out = <EventOccurrence>[];
    // 计算第一个 ≥ from 的发生
    final diff = _normStart(from).difference(start).inDays;
    final firstK = diff <= 0 ? 0 : ((diff + p.n - 1) ~/ p.n);
    var k = firstK;
    var emitted = 0;
    while (true) {
      final d = start.add(Duration(days: k * p.n));
      if (d.isAfter(_normEnd(to))) break;
      if (_inRange(d, from, to)) out.add(EventOccurrence(event: e, date: d));
      emitted++;
      if (p.count != null && emitted >= p.count!) break;
      k++;
      if (emitted > 100000) break; // safety
    }
    if (p.until != null) {
      // 过滤掉 > until 的
      return out.where((o) => !o.date.isAfter(_normEnd(p.until!))).toList();
    }
    return out;
  }

  List<EventOccurrence> _expandEveryNWeeks(Event e, DateTime from, DateTime to) {
    final p = e.period as EveryNWeeksPeriod;
    final a = e.anchor as SolarAnchor;
    final start = DateTime(a.year, a.month, a.day);
    final out = <EventOccurrence>[];
    // 从 start 起每 n 周一块。在每块内 emit weekday ∈ p.weekdays 的日子。
    final normFrom = _normStart(from);
    final firstChunkDiff = normFrom.difference(start).inDays;
    final firstChunk = firstChunkDiff <= 0
        ? 0
        : (firstChunkDiff / (p.n * 7)).floor();
    var k = firstChunk;
    var emitted = 0;
    while (true) {
      final chunkStart = start.add(Duration(days: k * p.n * 7));
      // 块内 7 天，每个 weekday 试一次
      for (var d = 0; d < p.n * 7; d++) {
        final day = chunkStart.add(Duration(days: d));
        if (p.weekdays.contains(day.weekday)) {
          if (_inRange(day, from, to)) {
            out.add(EventOccurrence(event: e, date: day));
          }
        }
      }
      if (chunkStart.isAfter(_normEnd(to))) break;
      emitted++;
      if (p.count != null && emitted >= p.count!) break;
      k++;
      if (emitted > 10000) break;
    }
    if (p.until != null) {
      return out.where((o) => !o.date.isAfter(_normEnd(p.until!))).toList();
    }
    return out;
  }

  // ───────── helpers ─────────

  List<EventOccurrence> _applyUntilCount(List<EventOccurrence> occ, Period p) {
    var result = occ;
    final until = _untilOf(p);
    if (until != null) {
      result = result.where((o) => !o.date.isAfter(_normEnd(until))).toList();
    }
    final count = _countOf(p);
    if (count != null && result.length > count) {
      result = result.sublist(0, count);
    }
    return result;
  }

  DateTime? _untilOf(Period p) {
    if (p is YearlyPeriod) return p.until;
    if (p is MonthlyDayPeriod) return p.until;
    if (p is MonthlyNthWeekdayPeriod) return p.until;
    if (p is EveryNDaysPeriod) return p.until;
    if (p is EveryNWeeksPeriod) return p.until;
    return null;
  }

  int? _countOf(Period p) {
    if (p is YearlyPeriod) return p.count;
    if (p is MonthlyDayPeriod) return p.count;
    if (p is MonthlyNthWeekdayPeriod) return p.count;
    if (p is EveryNDaysPeriod) return p.count;
    if (p is EveryNWeeksPeriod) return p.count;
    return null;
  }

  int _monthLength(int year, int month) {
    // 下个月 1 号 - 本月 1 号
    final next = month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    final thisStart = DateTime(year, month, 1);
    return next.difference(thisStart).inDays;
  }

  DateTime? _firstWeekdayOfMonth(int year, int month, int weekday) {
    final first = DateTime(year, month, 1);
    final delta = (weekday - first.weekday) % 7;
    return first.add(Duration(days: delta));
  }
}