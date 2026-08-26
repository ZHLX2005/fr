import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/event.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/anchor.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/period.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/person_patch.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/person.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/event_draft.dart';

void main() {
  group('Event v2', () {
    test('toJson / fromJson roundtrip preserves all fields', () {
      final e = Event(
        id: 'e1',
        title: '妈生日',
        type: EventType.birthday,
        anchor: const LunarAnchor(month: 4, day: 15, isLeap: false, year: 2025),
        period: PeriodFactory.yearly(),
        colorTag: ColorTag.red,
        people: const [PersonPatch(name: '妈', relation: PersonRelation.family)],
        note: '每年农历四月十五',
        groupId: 'default',
        createdAt: DateTime(2025, 1, 1),
      );
      final j = e.toJson();
      final back = Event.fromJson(j);
      expect(back, equals(e));
    });

    test('Period monthlyNthWeekday roundtrip', () {
      final e = Event(
        id: 'e2',
        title: '发薪',
        type: EventType.custom,
        anchor: const SolarAnchor(month: 1, day: 1, year: 2025),
        period: PeriodFactory.monthlyNthWeekday(n: 3, weekday: 5),
        colorTag: ColorTag.gray,
        groupId: 'default',
        createdAt: DateTime(2025, 1, 1),
      );
      expect(Event.fromJson(e.toJson()), equals(e));
    });

    test('Period everyNWeeks roundtrip preserves weekday set', () {
      final e = Event(
        id: 'e3',
        title: '值班',
        type: EventType.task,
        anchor: const SolarAnchor(month: 1, day: 1, year: 2025),
        period: PeriodFactory.everyNWeeks(n: 2, weekdays: {1, 3, 5}),
        colorTag: ColorTag.gray,
        groupId: 'default',
        createdAt: DateTime(2025, 1, 1),
      );
      expect(Event.fromJson(e.toJson()), equals(e));
    });
  });

  group('EventDraft', () {
    test('carries domain fields', () {
      final d = EventDraft(
        title: 't',
        type: EventType.task,
        anchor: const SolarAnchor(month: 1, day: 1, year: 2025),
        period: PeriodFactory.oneShot(),
        colorTag: ColorTag.gray,
        people: const [],
      );
      expect(d.title, 't');
      expect(d.period, PeriodFactory.oneShot());
    });
  });
}