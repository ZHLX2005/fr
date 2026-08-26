import 'event.dart';
import 'anchor.dart';
import 'lunar_calendar.dart';
import '../lunar_adapter.dart';
import '../data/occurrence_engine.dart';

/// 推算事件未来 N 年真实发生的公历 DateTime（v2：用 OccurrenceEngine）。
class NextBirthdayResolver {
  final LunarCalendar _cal;
  final OccurrenceEngine _engine;
  NextBirthdayResolver(this._cal) : _engine = OccurrenceEngine(LunarAdapter());

  /// from 之后最近一次发生
  DateTime upcoming(Event e, DateTime from) {
    return _engine.nextOccurrence(e, from) ?? _safeFallback(e, from);
  }

  DateTime _safeFallback(Event e, DateTime from) {
    if (e.anchor is SolarAnchor) {
      final a = e.anchor as SolarAnchor;
      return DateTime(from.year, a.month, a.day);
    }
    return from;
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