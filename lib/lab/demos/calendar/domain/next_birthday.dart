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
    // 当前所在的农历年——以它为基底计算"今年或明年"的公历生日。
    // 之前用 anchorLunarYear（出生年），导致 toSolar 永远算的是 199× 年，
    // 从不跳到当前年：生日"下次"永远是 30 年前。
    final currentLunarYear = _cal.fromSolar(from).year;
    // 尝试今年（农历年）的对应公历
    final sThis = _cal.toSolar(
      currentLunarYear,
      e.month,
      e.day,
      isLeap: e.isLeap,
    );
    var candidate = DateTime(sThis.year, sThis.month, sThis.day);
    if (!candidate.isAfter(from)) {
      // 已经过了 → 推下一农历年
      final sNext = _cal.toSolar(
        currentLunarYear + 1,
        e.month,
        e.day,
        isLeap: e.isLeap,
      );
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