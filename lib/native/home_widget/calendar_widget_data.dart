import 'dart:convert';

import '../../lab/demos/calendar/domain/event.dart';
import '../../lab/demos/calendar/domain/lunar_calendar.dart';

/// 桌面日历小组件传递的数据
///
/// Kotlin 端无需理解 Event 的完整结构，仅按日期分桶收颜色数组：
///   { "1": ["#FF0000"], "5": ["#FF9800", "#2196F3"], ... }
class CalendarWidgetData {
  /// 视图年（如 2026）
  final int year;

  /// 视图月（1-12）
  final int month;

  /// 今日年（用于高亮判定，可能与视图月不一致）
  final int todayYear;
  final int todayMonth;
  final int todayDay;

  /// 按日分组的颜色 map：key=日(1..31 string)，value=该日所有事件颜色（按 createdAt 升序）
  final Map<String, List<String>> colorsByDay;

  const CalendarWidgetData({
    required this.year,
    required this.month,
    required this.todayYear,
    required this.todayMonth,
    required this.todayDay,
    required this.colorsByDay,
  });

  /// 从事件列表构建当月 widget 数据（新签名：接受 List<Event>）
  ///
  /// 传 [lunar] 后，农历事件会先 resolve 到 [year] 公历年的发生日再分桶，
  /// 否则按公历月日直接匹配（仅 solar 事件正确）。
  factory CalendarWidgetData.fromEvents({
    required int year,
    required int month,
    required List<Event> events,
    LunarCalendar? lunar,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final Map<String, List<String>> grouped = {};
    // 把每个事件 resolve 到 [year] 的公历发生日，保留落在 [month] 的。
    final projected = <(DateTime, Event)>[];
    for (final e in events) {
      DateTime d;
      if (e.system == CalendarSystem.solar) {
        d = DateTime(year, e.month, e.day);
      } else if (lunar != null) {
        DateTime? found;
        for (final ly in [year - 1, year]) {
          try {
            final s = lunar.toSolar(ly, e.month, e.day, isLeap: e.isLeap);
            if (s.year == year) {
              found = DateTime(s.year, s.month, s.day);
              break;
            }
          } catch (_) {
            // 该农历年无此月日，跳过
          }
        }
        if (found == null) continue;
        d = found;
      } else {
        d = DateTime(year, e.month, e.day);
      }
      if (d.month == month) projected.add((d, e));
    }
    projected.sort((a, b) => a.$2.createdAt.compareTo(b.$2.createdAt));
    for (final (d, e) in projected) {
      grouped.putIfAbsent(d.day.toString(), () => []).add(e.colorTag.hex);
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