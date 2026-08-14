import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/timetable/domain/models.dart';
import 'package:xiaodouzi_fr/core/timetable/service/config/timetable_dsl_parser.dart';

void main() {
  group('parseDsl config 段', () {
    test('config 段解析出行列/开始时间', () {
      final result = parseDsl(
        'config: days=7 slots=5 cycles=16 start=2026-08-15 mode=general left=1 duration=50\n'
        '高等数学 @ 1 1 教学楼',
      );
      expect(result.config, isNotNull);
      expect(result.config!.daysPerCycle, 7);
      expect(result.config!.slotsPerDay, 5);
      expect(result.config!.cycleCount, 16);
      expect(result.config!.startDateIso, '2026-08-15');
      expect(result.config!.isSchoolMode, false);
      expect(result.config!.leftLabelMode, 1);
      expect(result.config!.slotDurationMin, 50);
      expect(result.courses, hasLength(1));
    });

    test('mode=school 生效', () {
      final result = parseDsl('config: mode=school\n体育 @ 2 1');
      expect(result.config!.isSchoolMode, true);
    });

    test('非法 config 行记录 error 且不中断后续课程', () {
      final result = parseDsl('config: days=7 slots 5\n体育 @ 2 1');
      expect(result.errors, isNotEmpty);
      expect(result.courses, hasLength(1));
    });

    test('无 config 段时 config 为 null', () {
      final result = parseDsl('体育 @ 2 1');
      expect(result.config, isNull);
    });

    test('config slots 约束后续课程节次范围', () {
      final result = parseDsl('config: slots=3\n课程 @ 1 5');
      expect(result.errors, isNotEmpty);
      expect(result.courses, isEmpty);
    });
  });

  group('TimetableConfig.slotLabel', () {
    const base = TimetableConfig(
      startDateIso: '2026-01-01',
      cycleCount: 1,
      daysPerCycle: 7,
      slotsPerDay: 5,
    );

    test('模式0 序号', () {
      expect(base.slotLabel(2), '3');
    });

    test('模式1 时间段（含自动计算结束）', () {
      const c = TimetableConfig(
        startDateIso: '2026-01-01',
        cycleCount: 1,
        daysPerCycle: 7,
        slotsPerDay: 5,
        leftLabelMode: 1,
        slotStartTimes: ['08:00', '08:45'],
      );
      expect(c.slotLabel(0), '08:00\n08:45');
      expect(c.slotLabel(1), '08:45\n09:30');
      expect(c.slotLabel(2), '3'); // 缺时间回退序号
    });

    test('模式2 自定义文字（空回退序号）', () {
      const c = TimetableConfig(
        startDateIso: '2026-01-01',
        cycleCount: 1,
        daysPerCycle: 7,
        slotsPerDay: 5,
        leftLabelMode: 2,
        slotLabels: ['上午'],
      );
      expect(c.slotLabel(0), '上午');
      expect(c.slotLabel(1), '2');
    });
  });

  group('TimetableMappers.addMinutes', () {
    test('普通进位', () {
      expect(TimetableMappers.addMinutes('08:30', 45), '09:15');
    });

    test('跨天回绕 24h', () {
      expect(TimetableMappers.addMinutes('23:40', 45), '00:25');
    });

    test('非法输入原样返回', () {
      expect(TimetableMappers.addMinutes('abc', 45), 'abc');
    });
  });
}
