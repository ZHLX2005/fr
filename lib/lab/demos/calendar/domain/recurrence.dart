import 'event.dart';

/// 事件重复类型
enum Recurrence {
  none,            // 一次
  yearly,          // 每年公历月日
  yearlyLunarAuto, // 每年按农历推算到公历（由 NextBirthdayResolver 处理）
  manual,          // 每年手动选日（用 solarYearOffset 偏移）
}

class RecurrenceResolver {
  /// 返回 from 之后最近一次发生的 DateTime；none 返回 null
  static DateTime? nextOccurrence(Event e, DateTime from) {
    switch (e.recurrence) {
      case Recurrence.none:
        return null;
      case Recurrence.yearly:
        return _yearlyNext(e, from, offsetDays: 0);
      case Recurrence.yearlyLunarAuto:
        return null; // 由 NextBirthdayResolver 处理
      case Recurrence.manual:
        return _yearlyNext(e, from, offsetDays: e.solarYearOffset ?? 0);
    }
  }

  static DateTime _yearlyNext(
    Event e,
    DateTime from, {
    required int offsetDays,
  }) {
    var y = from.year;
    var dt = DateTime(y, e.month, e.day).add(Duration(days: offsetDays));
    if (dt.isBefore(from)) {
      y += 1;
      dt = DateTime(y, e.month, e.day).add(Duration(days: offsetDays));
    }
    return dt;
  }
}