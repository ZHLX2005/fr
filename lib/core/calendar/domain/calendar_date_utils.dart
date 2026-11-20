/// 日历模块的日期工具：全部按本地时间、按“天”归一化。
library;

DateTime calendarDateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime calendarDayStart(DateTime value) => calendarDateOnly(value);

DateTime calendarDayEnd(DateTime value) =>
    calendarDateOnly(value).add(const Duration(days: 1));

/// `yyyy-mm-dd`，用于月视图任务点、Set 去重。
String calendarDateKey(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// 一周的起点。默认周一。
DateTime calendarWeekStart(DateTime date, {bool mondayFirst = true}) {
  final day = calendarDateOnly(date);
  final offset = mondayFirst ? day.weekday - DateTime.monday : day.weekday % 7;
  return day.subtract(Duration(days: offset));
}

/// 月视图固定 42 格（6 周）的起点。
DateTime calendarMonthGridStart(DateTime month, {bool mondayFirst = true}) {
  final first = DateTime(month.year, month.month, 1);
  final offset = mondayFirst
      ? first.weekday - DateTime.monday
      : first.weekday % 7;
  return first.subtract(Duration(days: offset));
}

/// 某天是否在 [start]（含）到 [end]（不含）之间。
bool calendarDateInRange(DateTime date, DateTime start, DateTime end) {
  final day = calendarDateOnly(date);
  return !day.isBefore(calendarDateOnly(start)) &&
      day.isBefore(calendarDateOnly(end));
}

/// 取两个日期中较早/较晚的一个。
DateTime calendarMinDate(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
DateTime calendarMaxDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

/// 某月天数。
int calendarDaysInMonth(int year, int month) =>
    DateTime(year, month + 1, 0).day;

