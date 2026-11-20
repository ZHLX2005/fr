/// 公历 → 农历换算（1900-2100）。
///
/// 算法与数据表从 docs/prototypes/calendar-capsule-nav.html 内联的
/// solarlunar（jjonline）逐位移植；测试基准值直接取自 JS 版运行结果，
/// 见 test/core/calendar/calendar_lunar_test.dart。
library;

import 'calendar_lunar_tables.dart';

/// 农历换算结果。UI 只消费 [monthCn] / [dayCn] / [isTerm] / [term]。
class LunarDate {
  const LunarDate({
    required this.solarYear,
    required this.solarMonth,
    required this.solarDay,
    required this.lunarYear,
    required this.lunarMonth,
    required this.lunarDay,
    required this.isLeapMonth,
    required this.isTerm,
    required this.term,
    required this.monthCn,
    required this.dayCn,
    required this.animal,
  });

  final int solarYear;
  final int solarMonth;
  final int solarDay;
  final int lunarYear;
  final int lunarMonth;
  final int lunarDay;
  final bool isLeapMonth;

  /// 当天是否恰为节气交节；[term] 为节气名（如「立冬」）。
  final bool isTerm;
  final String term;

  /// 农历月俗称（含闰前缀，如「闰四月」「腊月」）。
  final String monthCn;

  /// 农历日俗称（如「初六」「廿一」）。
  final String dayCn;
  final String animal;

  /// 月视图格子的次级文案：节气 > 农历节日 > 初一显月名 > 农历日。
  String get dayLabel {
    if (isTerm) return term;
    final festival = lunarFestival(lunarMonth, lunarDay, isLeapMonth);
    if (festival != null) return festival;
    if (lunarDay == 1 && !isLeapMonth) return monthCn;
    return dayCn;
  }
}

/// 农历传统节日（闰月不重复庆祝）。
const Map<String, String> _kLunarFestivals = {
  '1-1': '春节',
  '1-15': '元宵节',
  '5-5': '端午节',
  '7-7': '七夕节',
  '8-15': '中秋节',
  '9-9': '重阳节',
  '12-8': '腊八节',
  '12-23': '小年',
};

/// 公历节日（农历节日走 [_kLunarFestivals]）。
const Map<String, String> _kSolarFestivals = {
  '1-1': '元旦',
  '5-1': '劳动节',
  '6-1': '儿童节',
  '9-10': '教师节',
  '10-1': '国庆节',
};

String? lunarFestival(int lunarMonth, int lunarDay, bool isLeap) {
  if (isLeap) return null;
  return _kLunarFestivals['$lunarMonth-$lunarDay'];
}

String? solarFestival(int month, int day) => _kSolarFestivals['$month-$day'];

const List<String> _kGan = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
const List<String> _kZhi = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
const List<String> _kAnimals = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];
const List<String> _kTerms = [
  '小寒', '大寒', '立春', '雨水', '惊蛰', '春分', '清明', '谷雨',
  '立夏', '小满', '芒种', '夏至', '小暑', '大暑', '立秋', '处暑',
  '白露', '秋分', '寒露', '霜降', '立冬', '小雪', '大雪', '冬至',
];
const List<String> _kMonthNames = ['正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊'];
const List<String> _kDayPrefix = ['初', '十', '廿', '卅'];
const List<String> _kDigits = ['日', '一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];

/// 农历 y 年一整年总天数。
int _lunarYearDays(int y) {
  var sum = 348;
  final info = kLunarInfo[y - 1900];
  for (var bit = 0x8000; bit > 0x8; bit >>= 1) {
    sum += (info & bit) != 0 ? 1 : 0;
  }
  return sum + _leapDays(y);
}

/// 农历 y 年闰哪个月；无闰月返回 0。
int _leapMonth(int y) => kLunarInfo[y - 1900] & 0xf;

/// 农历 y 年闰月天数；无闰月返回 0。
int _leapDays(int y) {
  if (_leapMonth(y) == 0) return 0;
  return (kLunarInfo[y - 1900] & 0x10000) != 0 ? 30 : 29;
}

/// 农历 y 年 m 月（非闰月）天数。
int _monthDays(int y, int m) =>
    (kLunarInfo[y - 1900] & (0x10000 >> m)) != 0 ? 30 : 29;

/// 公历 y 年 m 月天数。
int _solarDays(int y, int m) {
  if (m == 2) {
    final leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    return leap ? 29 : 28;
  }
  return const [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1];
}

String _toGanZhi(int offset) => _kGan[offset % 10] + _kZhi[offset % 12];

String _toChinaMonth(int m) => '${_kMonthNames[m - 1]}月';

String _toChinaDay(int d) {
  switch (d) {
    case 10:
      return '初十';
    case 20:
      return '二十';
    case 30:
      return '三十';
  }
  return '${_kDayPrefix[d ~/ 10]}${_kDigits[d % 10]}';
}

/// 公历 y 年第 n 个节气（n=1 小寒 … n=24 冬至）的「日」。
int lunarTermDay(int y, int n) {
  assert(y >= 1900 && y <= 2100 && n >= 1 && n <= 24);
  final table = kLunarTermInfo[y - 1900];
  String chunk(int index) =>
      int.parse(table.substring(index * 5, index * 5 + 5), radix: 16)
          .toString();
  final groups = List.generate(6, chunk);
  final days = <String>[
    for (final g in groups) ...[
      _jsSubstr(g, 0, 1),
      _jsSubstr(g, 1, 2),
      _jsSubstr(g, 3, 1),
      _jsSubstr(g, 4, 2),
    ],
  ];
  return int.parse(days[n - 1]);
}

/// 复刻 JS `substr(start, length)` 语义（越界返回空串）。
String _jsSubstr(String s, int start, int length) {
  if (start >= s.length) return '';
  final end = start + length > s.length ? s.length : start + length;
  return s.substring(start, end);
}

/// 公历 → 农历。支持 1900-01-31 至 2100-12-31；越界返回 null。
LunarDate? solar2lunar(int y, int m, int d) {
  if (y < 1900 || y > 2100) return null;
  if (y == 1900 && m == 1 && d < 31) return null;
  if (m < 1 || m > 12) return null;
  final maxDay = _solarDays(y, m);
  if (d < 1 || d > maxDay) return null;

  // 与 JS 版一致：以 UTC 天数差为偏移（本地日期不涉时区换算）。
  var offset = DateTime.utc(y, m, d)
      .difference(DateTime.utc(1900, 1, 31))
      .inDays;

  var temp = 0;
  var i = 1900;
  for (; i < 2101 && offset > 0; i++) {
    temp = _lunarYearDays(i);
    offset -= temp;
  }
  if (offset < 0) {
    offset += temp;
    i--;
  }
  final lunarYear = i;

  final leap = _leapMonth(lunarYear);
  var isLeap = false;
  for (i = 1; i < 13 && offset > 0; i++) {
    if (leap > 0 && i == leap + 1 && !isLeap) {
      --i;
      isLeap = true;
      temp = _leapDays(lunarYear);
    } else {
      temp = _monthDays(lunarYear, i);
    }
    if (isLeap && i == leap + 1) {
      isLeap = false;
    }
    offset -= temp;
  }

  if (offset == 0 && leap > 0 && i == leap + 1) {
    if (isLeap) {
      isLeap = false;
    } else {
      isLeap = true;
      --i;
    }
  }
  if (offset < 0) {
    offset += temp;
    --i;
  }
  final lunarMonth = i;
  final lunarDay = offset + 1;

  final monthCn =
      (isLeap && leap == lunarMonth ? '闰' : '') + _toChinaMonth(lunarMonth);
  var animal = _kAnimals[(lunarYear - 4) % 12];

  // 当月「节」与「中气」的公历日。
  final firstNode = lunarTermDay(y, m * 2 - 1);
  final secondNode = lunarTermDay(y, m * 2);
  var isTerm = false;
  var term = '';
  if (firstNode == d) {
    isTerm = true;
    term = _kTerms[m * 2 - 2];
  }
  if (secondNode == d) {
    isTerm = true;
    term = _kTerms[m * 2 - 1];
  }

  return LunarDate(
    solarYear: y,
    solarMonth: m,
    solarDay: d,
    lunarYear: lunarYear,
    lunarMonth: lunarMonth,
    lunarDay: lunarDay,
    isLeapMonth: isLeap,
    isTerm: isTerm,
    term: term,
    monthCn: monthCn,
    dayCn: _toChinaDay(lunarDay),
    animal: animal,
  );
}

/// 农历 → 公历（1900-2100）。失败返回 null。
DateTime? lunar2solar(int y, int m, int d, {bool isLeapMonth = false}) {
  final leap = _leapMonth(y);
  if (isLeapMonth && leap != m) return null;
  if (y == 2100 && m == 12 && d > 1) return null;
  if (y == 1900 && m == 1 && d < 31) return null;
  if (y < 1900 || y > 2100 || d > _monthDays(y, m)) return null;

  var offset = 0;
  for (var i = 1900; i < y; i++) {
    offset += _lunarYearDays(i);
  }
  var isAdd = false;
  for (var i = 1; i < m; i++) {
    final leapOfMonth = _leapMonth(y);
    if (!isAdd && leapOfMonth <= i && leapOfMonth > 0) {
      offset += _leapDays(y);
      isAdd = true;
    }
    offset += _monthDays(y, i);
  }
  if (isLeapMonth) {
    // 与 JS 版一致：闰月目标补该月整月天数（d 在下方统一相加）。
    offset += _monthDays(y, m);
  }
  // JS 版 Date.UTC(1900, 1, 30) 月份为 0 起始（1 = 二月），2 月 30 日
  // 溢出归一为公历 1900-03-02，即 1900 年农历正月初一的真实锚点。
  return DateTime.utc(1900, 3, 2)
      .add(Duration(days: offset + d - 31));
}

String ganZhiYear(int y) => _toGanZhi(y - 4);

/// 月视图格子的次级文案（节气/节日为金高亮，初一显月名，其余农历日）。
/// 返回 `(文案, 是否高亮)`；换算失败返回 null。
(String, bool)? calendarLunarSubLabel(DateTime day) {
  final lunar = solar2lunar(day.year, day.month, day.day);
  if (lunar == null) return null;
  if (lunar.isTerm) return (lunar.term, true);
  final solar = solarFestival(day.month, day.day);
  if (solar != null) return (solar, true);
  final lunarFest =
      lunarFestival(lunar.lunarMonth, lunar.lunarDay, lunar.isLeapMonth);
  if (lunarFest != null) return (lunarFest, true);
  if (lunar.lunarDay == 1 && !lunar.isLeapMonth) {
    return (lunar.monthCn, false);
  }
  return (lunar.dayCn, false);
}
