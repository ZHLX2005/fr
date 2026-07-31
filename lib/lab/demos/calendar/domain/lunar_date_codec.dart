import 'event.dart';
import 'lunar_calendar.dart';

/// 8 位数字 (YYYYMMDD) ↔ 公历/农历
///
/// 存储约定：8 位数字里的 YYYY/MM/DD 永远是**输入历法**下的值——
/// 用户输入"农历 1990 五月廿"就传 19900520 + system=lunar，年份来自数字本身。
class LunarDateCodec {
  final LunarCalendar _cal;
  LunarDateCodec(this._cal);

  /// 8 位数字 → 公历 DateTime（直接拆位，公历无歧义）
  DateTime parseSolarFromYmd8(int yyyymmdd) {
    final y = yyyymmdd ~/ 10000;
    final m = (yyyymmdd ~/ 100) % 100;
    final d = yyyymmdd % 100;
    return DateTime(y, m, d);
  }

  /// 8 位数字 → 农历对应公历 DateTime
  ///
  /// **年份取自 8 位数本身**（YYYYMMDD 的高四位），不再用外部 year——
  /// 外部 year 曾用 DateTime.now().year，导致用户输入的出生年被无视、
  /// 生日年年漂移。isLeap 表示该农历月是否闰月。
  ///
  /// 农历该月无 30 日时抛 ArgumentError。
  DateTime parseLunarFromYmd8(int yyyymmdd, {bool isLeap = false}) {
    final y = yyyymmdd ~/ 10000;
    final m = (yyyymmdd ~/ 100) % 100;
    final d = yyyymmdd % 100;
    final daysInMonth = _cal.daysInLunarMonth(y, m, isLeap: isLeap);
    if (d > daysInMonth) {
      throw ArgumentError(
        '农历 $y 年${isLeap ? "闰" : ""}$m 月只有 $daysInMonth 天，$d 超出范围',
      );
    }
    final s = _cal.toSolar(y, m, d, isLeap: isLeap);
    return DateTime(s.year, s.month, s.day);
  }

  /// 把公历 DateTime 编码成 8 位数字（按指定历法）
  ///
  /// solar: 公历年月日；lunar: 农历年月日（isLeap 信息丢失，仅 UI 回显用）。
  int toYmd8(DateTime solar, CalendarSystem system) {
    if (system == CalendarSystem.solar) {
      return solar.year * 10000 + solar.month * 100 + solar.day;
    }
    final l = _cal.fromSolar(solar);
    return l.year * 10000 + l.month * 100 + l.day;
  }

  /// 公历 DateTime → LunarDate（直接代理 LunarCalendar）
  LunarDate lunarFromSolar(DateTime solar) => _cal.fromSolar(solar);

  /// 历法切换换算：把 [from] 历法下的 8 位日期转成 [to] 历法下的等值 8 位日期。
  ///
  /// 用于表单里用户点"公历↔农历"切换时，**把字段值替换成对方历法的等值**，
  /// 而不是"用同一串数字重新解释"。lunar→solar 需要 [sourceIsLeap] 才能正确反推。
  ///
  /// 返回 (目标历法下的 8 位日期, 目标历法是否闰月)。
  ({int ymd8, bool isLeap}) convertSystem(
    int ymd8, {
    required CalendarSystem from,
    required CalendarSystem to,
    bool sourceIsLeap = false,
  }) {
    if (from == to) return (ymd8: ymd8, isLeap: sourceIsLeap);
    final y = ymd8 ~/ 10000;
    final m = (ymd8 ~/ 100) % 100;
    final d = ymd8 % 100;
    if (from == CalendarSystem.solar) {
      // 公历 → 农历
      final l = _cal.fromSolar(DateTime(y, m, d));
      return (
        ymd8: l.year * 10000 + l.month * 100 + l.day,
        isLeap: l.isLeap,
      );
    } else {
      // 农历 → 公历
      final s = _cal.toSolar(y, m, d, isLeap: sourceIsLeap);
      return (ymd8: s.year * 10000 + s.month * 100 + s.day, isLeap: false);
    }
  }
}
