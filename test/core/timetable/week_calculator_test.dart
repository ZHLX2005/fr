// 课表起始日期工具测试 —— 验证 findNearestMondayOnOrBefore
// Dart DateTime.weekday: 1=Mon, 2=Tue, ... 7=Sun

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/timetable/service/config/timetable_week_calculator.dart';

void main() {
  group('findNearestMondayOnOrBefore', () {
    test('周一 → 自身', () {
      // 2026-08-03 是周一
      final d = DateTime(2026, 8, 3);
      final m = findNearestMondayOnOrBefore(d);
      expect(m, DateTime(2026, 8, 3));
    });

    test('周二 → 回退 1 天到本周一', () {
      // 2026-08-04 是周二
      final d = DateTime(2026, 8, 4);
      final m = findNearestMondayOnOrBefore(d);
      expect(m, DateTime(2026, 8, 3));
    });

    test('周三 → 回退 2 天', () {
      final m = findNearestMondayOnOrBefore(DateTime(2026, 8, 5));
      expect(m, DateTime(2026, 8, 3));
    });

    test('周日 → 回退 6 天到本周一', () {
      // 2026-08-09 是周日
      final m = findNearestMondayOnOrBefore(DateTime(2026, 8, 9));
      expect(m, DateTime(2026, 8, 3));
    });

    test('跨月：8/31 周一回退到 8/25', () {
      // 2026-08-31 是周一
      final m = findNearestMondayOnOrBefore(DateTime(2026, 8, 31));
      expect(m, DateTime(2026, 8, 31));
      // 2026-09-01 是周二 → 回退到 8/31
      expect(findNearestMondayOnOrBefore(DateTime(2026, 9, 1)),
          DateTime(2026, 8, 31));
    });

    test('跨年：1/1 周一回退到上年 12/29', () {
      // 2026-01-01 是周四
      final m = findNearestMondayOnOrBefore(DateTime(2026, 1, 1));
      expect(m, DateTime(2025, 12, 29));
    });

    test('开学日设为某周三 → 自动回退到开学前那周周一', () {
      // 场景：用户期望 2026-09-02 (周三) 开学 → 实际起始 2026-08-31 (周一)
      final start = findNearestMondayOnOrBefore(DateTime(2026, 9, 2));
      expect(start, DateTime(2026, 8, 31));
      // 用户期望 2026-08-31 (周一) 开学 → 原样
      expect(findNearestMondayOnOrBefore(DateTime(2026, 8, 31)),
          DateTime(2026, 8, 31));
    });
  });
}
