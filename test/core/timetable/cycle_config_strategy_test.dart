import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/timetable/domain/models.dart';
import 'package:xiaodouzi_fr/core/timetable/service/config/advanced/cycle_config_strategy.dart';

void main() {
  const school = TimetableConfig(
    startDateIso: '2026-01-01',
    cycleCount: 20,
    daysPerCycle: 7,
    slotsPerDay: 5,
    isSchoolMode: true,
  );
  const general = TimetableConfig(
    startDateIso: '2026-01-01',
    cycleCount: 20,
    daysPerCycle: 3,
    slotsPerDay: 5,
    isSchoolMode: false,
    isAnimeMode: false,
  );
  const anime = TimetableConfig(
    startDateIso: '2026-01-01',
    cycleCount: 20,
    daysPerCycle: 7,
    slotsPerDay: 5,
    isSchoolMode: false,
    isAnimeMode: true,
  );

  group('cycleStrategyFor 三模式路由', () {
    test('课表模式 → SchoolCycleStrategy（天数固定 7）', () {
      final s = cycleStrategyFor(school);
      expect(s, isA<SchoolCycleStrategy>());
      expect(s.fixedDaysPerCycle, 7);
      expect(s.allowsManualConfig, isTrue);
      expect(s.resolveDaysPerCycle(3), 7); // 用户改 3 也被强制 7
      expect(s.maxSlotsPerDay, TimetableConfig.maxManualSlotsPerDay);
    });

    test('通用模式 → GeneralCycleStrategy（天数可调 1-7）', () {
      final s = cycleStrategyFor(general);
      expect(s, isA<GeneralCycleStrategy>());
      expect(s.fixedDaysPerCycle, isNull);
      expect(s.allowsManualConfig, isTrue);
      expect(s.resolveDaysPerCycle(3), 3); // 用户值原样生效
      expect(s.resolveDaysPerCycle(5), 5);
    });

    test('番剧模式 → AnimeCycleStrategy（手动配置关闭）', () {
      final s = cycleStrategyFor(anime);
      expect(s, isA<AnimeCycleStrategy>());
      expect(s.fixedDaysPerCycle, 7);
      expect(s.allowsManualConfig, isFalse);
      expect(s.hint, isNotNull);
      expect(s.maxSlotsPerDay, TimetableConfig.maxSlotsPerDay); // 64
    });
  });
}
