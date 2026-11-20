import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/calendar/domain/calendar_lunar.dart';

/// 农历换算基准值取自原型内联 solarlunar（JS 版）的真实运行输出，
/// 见 docs/prototypes/calendar-capsule-nav.html。
void main() {
  group('solar2lunar：春节锚点', () {
    test('2026-02-17 = 丙午年正月初一（马年）', () {
      final lunar = solar2lunar(2026, 2, 17)!;
      expect(lunar.lunarYear, 2026);
      expect(lunar.lunarMonth, 1);
      expect(lunar.lunarDay, 1);
      expect(lunar.isLeapMonth, false);
      expect(lunar.monthCn, '正月');
      expect(lunar.dayCn, '初一');
      expect(lunar.animal, '马');
    });

    test('2025-01-29 = 正月初一（蛇年）', () {
      final lunar = solar2lunar(2025, 1, 29)!;
      expect(lunar.lunarMonth, 1);
      expect(lunar.lunarDay, 1);
      expect(lunar.animal, '蛇');
    });

    test('2024-02-10 = 正月初一（龙年）', () {
      final lunar = solar2lunar(2024, 2, 10)!;
      expect(lunar.lunarMonth, 1);
      expect(lunar.lunarDay, 1);
      expect(lunar.animal, '龙');
    });
  });

  group('solar2lunar：节气', () {
    test('2025-11-07 立冬（农历九月十八）', () {
      final lunar = solar2lunar(2025, 11, 7)!;
      expect(lunar.isTerm, true);
      expect(lunar.term, '立冬');
      expect(lunar.lunarMonth, 9);
      expect(lunar.lunarDay, 18);
      expect(lunar.dayLabel, '立冬'); // 节气优先于农历日
    });

    test('2025-08-23 处暑（七月初一：节气优先于月名）', () {
      final lunar = solar2lunar(2025, 8, 23)!;
      expect(lunar.isTerm, true);
      expect(lunar.term, '处暑');
      expect(lunar.lunarDay, 1);
      expect(lunar.dayLabel, '处暑');
    });

    test('lunarTermDay(1987, 3) = 4（1987-02-04 立春）', () {
      expect(lunarTermDay(1987, 3), 4);
    });

    test('lunarTermDay(2025, 21) = 7（2025-11-07 立冬）', () {
      expect(lunarTermDay(2025, 21), 7);
    });

    test('lunarTermDay(2025, 19) = 8（2025-10-08 寒露）', () {
      expect(lunarTermDay(2025, 19), 8);
    });
  });

  group('solar2lunar：常规换算', () {
    test('2026-11-20 = 农历十月十二', () {
      final lunar = solar2lunar(2026, 11, 20)!;
      expect(lunar.lunarMonth, 10);
      expect(lunar.lunarDay, 12);
      expect(lunar.monthCn, '十月');
      expect(lunar.dayCn, '十二');
      expect(lunar.dayLabel, '十二');
    });

    test('2026-11-16 = 十月初八', () {
      final lunar = solar2lunar(2026, 11, 16)!;
      expect(lunar.lunarDay, 8);
      expect(lunar.dayCn, '初八');
    });

    test('1987-11-01 = 九月初十（solarlunar 文档用例）', () {
      final lunar = solar2lunar(1987, 11, 1)!;
      expect(lunar.lunarYear, 1987);
      expect(lunar.lunarMonth, 9);
      expect(lunar.lunarDay, 10);
      expect(lunar.dayCn, '初十');
      expect(lunar.animal, '兔');
    });

    test('2026-01-01 = 乙巳年冬月十三（跨农历年）', () {
      final lunar = solar2lunar(2026, 1, 1)!;
      expect(lunar.lunarYear, 2025);
      expect(lunar.lunarMonth, 11);
      expect(lunar.lunarDay, 13);
      expect(lunar.monthCn, '冬月');
    });
  });

  group('节日', () {
    test('2025-01-29 春节', () {
      final lunar = solar2lunar(2025, 1, 29)!;
      expect(
        lunarFestival(lunar.lunarMonth, lunar.lunarDay, lunar.isLeapMonth),
        '春节',
      );
    });

    test('2025-10-06 中秋节', () {
      final lunar = solar2lunar(2025, 10, 6)!;
      expect(
        lunarFestival(lunar.lunarMonth, lunar.lunarDay, lunar.isLeapMonth),
        '中秋节',
      );
    });

    test('公历节日：2025-10-01 国庆节', () {
      expect(solarFestival(10, 1), '国庆节');
      expect(solarFestival(6, 1), '儿童节');
      expect(solarFestival(4, 1), null);
    });
  });

  group('边界', () {
    test('越界返回 null', () {
      expect(solar2lunar(1899, 12, 31), null);
      expect(solar2lunar(2101, 1, 1), null);
      expect(solar2lunar(1900, 1, 30), null); // 下限 1900-01-31
      expect(solar2lunar(2026, 2, 30), null); // 非法日
    });

    test('下限日 1900-01-31 可换算', () {
      final lunar = solar2lunar(1900, 1, 31)!;
      expect(lunar.lunarYear, 1900);
      expect(lunar.lunarMonth, 1);
      expect(lunar.lunarDay, 1);
    });

    test('lunar2solar 往返一致', () {
      for (final date in [
        DateTime(2026, 11, 20),
        DateTime(2026, 2, 17),
        DateTime(2025, 6, 15),
      ]) {
        final lunar = solar2lunar(date.year, date.month, date.day)!;
        final back = lunar2solar(
          lunar.lunarYear,
          lunar.lunarMonth,
          lunar.lunarDay,
        );
        expect(back, isNotNull);
        expect(back!.year, date.year);
        expect(back.month, date.month);
        expect(back.day, date.day);
      }
    });
  });
}
