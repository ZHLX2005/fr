import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/timetable/service/config/timetable_week_calculator.dart';

void main() {
  group('resolveStartDateIso', () {
    test('通用模式：任意日期原样保存（不回退周一）', () {
      // 2026-08-14 是周五
      expect(resolveStartDateIso('2026-08-14', isSchoolMode: false), '2026-08-14');
    });
    test('通用模式：周一也原样', () {
      expect(resolveStartDateIso('2026-08-10', isSchoolMode: false), '2026-08-10');
    });
    test('学校模式：周五回退到最近周一', () {
      expect(resolveStartDateIso('2026-08-14', isSchoolMode: true), '2026-08-10');
    });
    test('无法解析 → 原样返回', () {
      expect(resolveStartDateIso('not-a-date', isSchoolMode: false), 'not-a-date');
    });
  });
}
