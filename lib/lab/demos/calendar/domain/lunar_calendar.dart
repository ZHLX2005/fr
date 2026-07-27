/// 公历日期值对象
class SolarDate {
  final int year;
  final int month;
  final int day;
  const SolarDate(this.year, this.month, this.day);

  @override
  String toString() =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is SolarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

/// 农历日期值对象
class LunarDate {
  final int year;
  final int month;
  final int day;
  final bool isLeap;
  const LunarDate(this.year, this.month, this.day, {this.isLeap = false});

  @override
  String toString() =>
      '农历$year年${isLeap ? "闰" : ""}$month月$day';

  @override
  bool operator ==(Object other) =>
      other is LunarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.isLeap == isLeap;

  @override
  int get hashCode => Object.hash(year, month, day, isLeap);
}

/// 农历引擎抽象（便于替换库或加宜忌）
abstract class LunarCalendar {
  SolarDate toSolar(
    int lunarYear,
    int lunarMonth,
    int lunarDay, {
    bool isLeap = false,
  });
  LunarDate fromSolar(DateTime solar);
  String zodiacOf(DateTime solar); // 生肖（鼠牛虎兔…）
  String? solarTermOf(DateTime solar); // 节气（返回 null 表示非节气日）
  int daysInLunarMonth(int year, int month, {bool isLeap = false});
}