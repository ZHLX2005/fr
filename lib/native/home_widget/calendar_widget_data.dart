import 'dart:convert';
import '../../lab/models/lab_calendar_event.dart';

/// 桌面日历小组件传递的数据
///
/// Kotlin 端无需理解 LabCalendarEvent 的完整结构，仅按日期分桶收颜色数组：
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

  /// 从事件列表构建当月 widget 数据
  factory CalendarWidgetData.fromEvents({
    required int year,
    required int month,
    required List<LabCalendarEvent> events,
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();

    // 仅保留当月事件，按 day 分桶
    final Map<String, List<String>> grouped = {};
    final monthEvents = events.where(
      (e) => e.year == year && e.month == month,
    );
    final sorted = monthEvents.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final e in sorted) {
      grouped.putIfAbsent(e.day.toString(), () => []).add(e.color);
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

  /// 序列化 colorsByDay 给 Kotlin 解析
  String get colorsJson => json.encode(colorsByDay);
}
