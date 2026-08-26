import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/occurrence_engine.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/event.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/anchor.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/period.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/lunar_adapter.dart';

void main() {
  final eng = OccurrenceEngine(LunarAdapter());

  Event mkEvent({
    required String id,
    required Anchor anchor,
    required Period period,
    EventType type = EventType.custom,
  }) =>
      Event(
        id: id,
        title: id,
        type: type,
        anchor: anchor,
        period: period,
        colorTag: ColorTag.gray,
        groupId: 'default',
        createdAt: DateTime(2024, 1, 1),
      );

  test('yearly solar emits one per year in range', () {
    final e = mkEvent(
      id: 'y1',
      anchor: const SolarAnchor(month: 1, day: 1, year: 2024),
      period: PeriodFactory.yearly(),
    );
    final occ = eng.occurrencesBetween([e], DateTime(2024, 1, 1), DateTime(2026, 12, 31));
    expect(occ.map((o) => o.date.year).toSet(), {2024, 2025, 2026});
  });

  test('oneShot only inside window', () {
    final e = mkEvent(
      id: 'os',
      anchor: const SolarAnchor(month: 5, day: 1, year: 2025),
      period: PeriodFactory.oneShot(),
    );
    expect(eng.eventsOn([e], DateTime(2025, 5, 1)), hasLength(1));
    expect(eng.eventsOn([e], DateTime(2025, 5, 2)), isEmpty);
  });

  test('every-N-days weekday-ignored: 1, 5, 9, 13, ...', () {
    final e = mkEvent(
      id: 'e3',
      anchor: const SolarAnchor(month: 1, day: 1, year: 2025),
      period: PeriodFactory.everyNDays(n: 4),
    );
    final occ = eng.occurrencesBetween([e], DateTime(2025, 1, 1), DateTime(2025, 1, 31));
    expect(occ.map((o) => o.date.day).toList(), [1, 5, 9, 13, 17, 21, 25, 29]);
  });

  test('monthly-nth: 3rd Friday of May 2025 = 2025-05-16', () {
    final e = mkEvent(
      id: 'pay',
      anchor: const SolarAnchor(month: 1, day: 1, year: 2025),
      period: PeriodFactory.monthlyNthWeekday(n: 3, weekday: 5), // 5 = Fri
    );
    final occ = eng.eventsOn([e], DateTime(2025, 5, 16));
    expect(occ, hasLength(1));
  });

  test('monthly-day skips month too short', () {
    final e = mkEvent(
      id: 'd31',
      anchor: const SolarAnchor(month: 1, day: 31, year: 2025),
      period: PeriodFactory.monthlyDay(day: 31),
    );
    expect(eng.eventsOn([e], DateTime(2025, 2, 28)), isEmpty);
    expect(eng.eventsOn([e], DateTime(2025, 3, 31)), hasLength(1));
  });

  test('count terminator', () {
    final e = mkEvent(
      id: 'cnt',
      anchor: const SolarAnchor(month: 1, day: 1, year: 2025),
      period: PeriodFactory.everyNDays(n: 7, count: 3),
    );
    final occ = eng.occurrencesBetween([e], DateTime(2025, 1, 1), DateTime(2025, 12, 31));
    expect(occ, hasLength(3));
  });
}