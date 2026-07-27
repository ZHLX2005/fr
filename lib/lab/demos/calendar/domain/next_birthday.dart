import 'event.dart';
import 'lunar_calendar.dart';
import 'recurrence.dart';

/// 推算事件未来 N 年真实发生的公历 DateTime
class NextBirthdayResolver {
  final LunarCalendar _cal;
  NextBirthdayResolver(this._cal);

  /// from 之后最近一次发生
  DateTime upcoming(Event e, DateTime from) {
    switch (e.recurrence) {
      case Recurrence.yearlyLunarAuto:
        return _lunarUpcoming(e, from);
      case Recurrence.yearly:
      case Recurrence.manual:
        final n = RecurrenceResolver.nextOccurrence(e, from);
        return n ?? _safeFallback(e, from);
      case Recurrence.none:
        return DateTime(from.year, e.month, e.day);
    }
  }

  DateTime _lunarUpcoming(Event e, DateTime from) {
    // lunarAnchorYear 是那次农历月日所在的农历年；如果没存，取 from 的农历年
    int anchorLunarYear;
    if (e.lunarAnchorYear != null) {
      anchorLunarYear = e.lunarAnchorYear!;
    } else {
      final lNow = _cal.fromSolar(from);
      anchorLunarYear = lNow.year;
    }
    // 用 anchorLunarYear 反推那年的农历月日对应的公历
    final sAnchor = _cal.toSolar(anchorLunarYear, e.month, e.day);
    var candidate = DateTime(sAnchor.year, sAnchor.month, sAnchor.day);
    if (!candidate.isAfter(from)) {
      // 推到下一年（农历）的农历月日对应公历
      final sNext = _cal.toSolar(anchorLunarYear + 1, e.month, e.day);
      candidate = DateTime(sNext.year, sNext.month, sNext.day);
    }
    return candidate;
  }

  DateTime _safeFallback(Event e, DateTime from) {
    return DateTime(from.year, e.month, e.day);
  }

  /// 未来 N 年（基于 from 所在年的 1/1 起算）
  List<DateTime> nextN(Event e, int years, {required DateTime from}) {
    return List.generate(years, (i) {
      final base = DateTime(from.year + i, 1, 1);
      return upcoming(e, base);
    });
  }

  static int daysUntil(DateTime target, DateTime from) {
    final today = DateTime(from.year, from.month, from.day);
    final t = DateTime(target.year, target.month, target.day);
    return t.difference(today).inDays;
  }
}