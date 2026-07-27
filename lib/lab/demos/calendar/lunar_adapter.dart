import 'package:lunar/lunar.dart' as l;

import 'domain/lunar_calendar.dart';

/// lunar 包（by 6tail.cn）的适配器，实现 LunarCalendar 抽象
class LunarAdapter implements LunarCalendar {
  @override
  SolarDate toSolar(
    int lunarYear,
    int lunarMonth,
    int lunarDay, {
    bool isLeap = false,
  }) {
    // lunar 包：负数 month 代表闰月
    final ld = l.Lunar.fromYmd(lunarYear, isLeap ? -lunarMonth : lunarMonth, lunarDay);
    final s = ld.getSolar();
    return SolarDate(s.getYear(), s.getMonth(), s.getDay());
  }

  @override
  LunarDate fromSolar(DateTime solar) {
    final ld = l.Lunar.fromDate(solar);
    final month = ld.getMonth();
    return LunarDate(
      ld.getYear(),
      month.abs(),
      ld.getDay(),
      isLeap: month < 0,
    );
  }

  @override
  String zodiacOf(DateTime solar) => l.Lunar.fromDate(solar).getYearShengXiao();

  @override
  String? solarTermOf(DateTime solar) {
    // lunar 包节气通过 getJieQi() 提供；保持接口简洁，暂不展开
    return null;
  }

  @override
  int daysInLunarMonth(int year, int month, {bool isLeap = false}) {
    // 用下个月第一天 Solar 减本月第一天 Solar
    final thisFirst = l.Lunar.fromYmd(year, isLeap ? -month : month, 1).getSolar();
    final nextFirst = l.Lunar.fromYmd(year, isLeap ? -month : month + 1, 1).getSolar();
    final a = DateTime(thisFirst.getYear(), thisFirst.getMonth(), thisFirst.getDay());
    final b = DateTime(nextFirst.getYear(), nextFirst.getMonth(), nextFirst.getDay());
    return b.difference(a).inDays;
  }
}