import 'dart:convert';

import '../../lab/demos/calendar/domain/event_occurrence.dart';

/// 桌面日历小组件传递的数据（v2：接受 EventOccurrence）。
///
/// Kotlin 端无需理解 Event 的完整结构，仅按日期分桶收颜色数组：
///   { "1": ["#FF0000"], "5": ["#FF9800", "#2196F3"], ... }
class CalendarWidgetData {
  final int year;
  final int month;
  final int todayYear;
  final int todayMonth;
  final int todayDay;

  /// key=日(1..31 string), value=该日所有事件颜色（按 createdAt 升序）
  final Map<String, List<String>> colorsByDay;

  const CalendarWidgetData({
    required this.year,
    required this.month,
    required this.todayYear,
    required this.todayMonth,
    required this.todayDay,
    required this.colorsByDay,
  });

  /// 从 EventOccurrence 列表构建当月 widget 数据。
  /// 仅保留 `[year, month]` 内的发生日。
  factory CalendarWidgetData.fromOccurrences({
    required int year,
    required int month,
    required List<EventOccurrence> occurrences,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final grouped = <String, List<String>>{};
    final projected = <EventOccurrence>[];
    for (final o in occurrences) {
      if (o.date.year == year && o.date.month == month) {
        projected.add(o);
      }
    }
    projected.sort((a, b) => a.event.createdAt.compareTo(b.event.createdAt));
    for (final o in projected) {
      grouped.putIfAbsent(o.date.day.toString(), () => []).add(o.event.colorTag.hex);
    }
    return CalendarWidgetData(
      year: year,
      month: month,
      todayYear: today.year,
      todayMonth: today.month,
      todayDay: today.day,
      colorsByDay: grouped,
    );
  }

  static const empty = CalendarWidgetData(
    year: 1970,
    month: 1,
    todayYear: 1970,
    todayMonth: 1,
    todayDay: 1,
    colorsByDay: {},
  );

  String get colorsJson => json.encode(colorsByDay);
}