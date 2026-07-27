import 'event.dart';
import 'lunar_calendar.dart';

/// 8 位数字 (YYYYMMDD) ↔ 公历/农历 DateTime
class LunarDateCodec {
  final LunarCalendar _cal;
  LunarDateCodec(this._cal);

  /// 8 位数字 → 公历 DateTime
  DateTime parseSolarFromYmd8(int yyyymmdd) {
    final y = yyyymmdd ~/ 10000;
    final m = (yyyymmdd ~/ 100) % 100;
    final d = yyyymmdd % 100;
    return DateTime(y, m, d);
  }

  /// 8 位数字 → 农历对应公历 DateTime（需指定所在农历年）
  ///
  /// 农历无 30 日时抛 ArgumentError
  DateTime parseLunarFromYmd8(int yyyymmdd, {required int year}) {
    final m = (yyyymmdd ~/ 100) % 100;
    final d = yyyymmdd % 100;
    final daysInMonth = _cal.daysInLunarMonth(year, m);
    if (d > daysInMonth) {
      throw ArgumentError(
        '农历 $year 年 $m 月只有 $daysInMonth 天，$d 超出范围',
      );
    }
    final s = _cal.toSolar(year, m, d);
    return DateTime(s.year, s.month, s.day);
  }

  /// 把公历 DateTime 编码成 8 位数字（按指定历法）
  ///
  /// 用于 UI 输入回显。lunar 时取农历月日拼接，年用 lunar 年。
  int toYmd8(DateTime solar, CalendarSystem system) {
    if (system == CalendarSystem.solar) {
      return solar.year * 10000 + solar.month * 100 + solar.day;
    }
    final l = _cal.fromSolar(solar);
    return l.year * 10000 + l.month * 100 + l.day;
  }

  /// 公历 DateTime → LunarDate（直接代理 LunarCalendar）
  LunarDate lunarFromSolar(DateTime solar) => _cal.fromSolar(solar);
}