import 'package:meta/meta.dart';

/// 周期 —— 事件重复规则。
///
/// 每种周期（除 `oneShot`）都可选携带 `until` 或 `count` 终止条件：
/// - `until`：最后一次发生的日期（包含）。
/// - `count`：从首次发生起累计允许发生的次数。
/// 两者都填时由实现方决定哪个优先（暂以 `until` 优先，符合直觉）。
@immutable
sealed class Period {
  const Period();
}

@immutable
class OneShotPeriod extends Period {
  const OneShotPeriod();

  @override
  bool operator ==(Object o) => o is OneShotPeriod;

  @override
  int get hashCode => (OneShotPeriod).hashCode;
}

@immutable
class YearlyPeriod extends Period {
  final DateTime? until;
  final int? count;
  const YearlyPeriod({this.until, this.count});

  @override
  bool operator ==(Object o) =>
      o is YearlyPeriod && o.until == until && o.count == count;

  @override
  int get hashCode => Object.hash(until, count);
}

@immutable
class MonthlyDayPeriod extends Period {
  final int day; // 1-31，超过该月长度的月份跳过
  final DateTime? until;
  final int? count;
  const MonthlyDayPeriod({required this.day, this.until, this.count});

  @override
  bool operator ==(Object o) =>
      o is MonthlyDayPeriod && o.day == day && o.until == until && o.count == count;

  @override
  int get hashCode => Object.hash(day, until, count);
}

@immutable
class MonthlyNthWeekdayPeriod extends Period {
  /// 第 N 个 weekday(1..5)；N 超过当月该 weekday 个数时该月跳过。
  final int n;
  /// weekday: Mon=1..Sun=7
  final int weekday;
  final DateTime? until;
  final int? count;
  const MonthlyNthWeekdayPeriod({
    required this.n,
    required this.weekday,
    this.until,
    this.count,
  });

  @override
  bool operator ==(Object o) =>
      o is MonthlyNthWeekdayPeriod &&
      o.n == n &&
      o.weekday == weekday &&
      o.until == until &&
      o.count == count;

  @override
  int get hashCode => Object.hash(n, weekday, until, count);
}

@immutable
class EveryNDaysPeriod extends Period {
  /// 每 n 天一次。**weekday 不参与过滤** —— 严格按锚点 + n*k 天推进。
  final int n;
  final DateTime? until;
  final int? count;
  const EveryNDaysPeriod({required this.n, this.until, this.count});

  @override
  bool operator ==(Object o) =>
      o is EveryNDaysPeriod && o.n == n && o.until == until && o.count == count;

  @override
  int get hashCode => Object.hash(n, until, count);
}

@immutable
class EveryNWeeksPeriod extends Period {
  final int n; // 每 n 周
  final Set<int> weekdays; // Mon=1..Sun=7
  final DateTime? until;
  final int? count;
  const EveryNWeeksPeriod({
    required this.n,
    required this.weekdays,
    this.until,
    this.count,
  });

  @override
  bool operator ==(Object o) =>
      o is EveryNWeeksPeriod &&
      o.n == n &&
      _setEq(o.weekdays, weekdays) &&
      o.until == until &&
      o.count == count;

  @override
  int get hashCode => Object.hash(n, Object.hashAllUnordered(weekdays), until, count);

  static bool _setEq(Set<int> a, Set<int> b) {
    if (a.length != b.length) return false;
    for (final x in a) {
      if (!b.contains(x)) return false;
    }
    return true;
  }
}

/// 命名构造器入口。形式为 `PeriodFactory.oneShot()` 等。
extension PeriodFactory on Period {
  static Period oneShot() => const OneShotPeriod();
  static Period yearly({DateTime? until, int? count}) =>
      YearlyPeriod(until: until, count: count);
  static Period monthlyDay({required int day, DateTime? until, int? count}) =>
      MonthlyDayPeriod(day: day, until: until, count: count);
  static Period monthlyNthWeekday({
    required int n,
    required int weekday,
    DateTime? until,
    int? count,
  }) =>
      MonthlyNthWeekdayPeriod(n: n, weekday: weekday, until: until, count: count);
  static Period everyNDays({required int n, DateTime? until, int? count}) =>
      EveryNDaysPeriod(n: n, until: until, count: count);
  static Period everyNWeeks({
    required int n,
    required Set<int> weekdays,
    DateTime? until,
    int? count,
  }) =>
      EveryNWeeksPeriod(n: n, weekdays: weekdays, until: until, count: count);
}