import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/anchor.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/period.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/person_patch.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/person.dart';

void main() {
  group('Anchor', () {
    test('SolarAnchor stores m/d/y', () {
      const a = SolarAnchor(month: 8, day: 15, year: 2025);
      expect(a.month, 8);
      expect(a.day, 15);
      expect(a.year, 2025);
    });

    test('LunarAnchor stores isLeap', () {
      const a = LunarAnchor(month: 4, day: 15, isLeap: true, year: 2025);
      expect(a.isLeap, true);
    });

    test('solar factory', () {
      final a = AnchorFactory.solar(month: 1, day: 1, year: 2025);
      expect(a, isA<SolarAnchor>());
    });

    test('lunar factory', () {
      final a = AnchorFactory.lunar(month: 1, day: 1, isLeap: false, year: 2025);
      expect(a, isA<LunarAnchor>());
    });
  });

  group('Period', () {
    test('Period.yearly equality', () {
      final a = PeriodFactory.yearly();
      final b = PeriodFactory.yearly();
      expect(a, equals(b));
      expect(PeriodFactory.yearly(until: DateTime(2030)), isNot(equals(a)));
    });

    test('Period.everyNDays equality includes n', () {
      expect(
        PeriodFactory.everyNDays(n: 4),
        equals(PeriodFactory.everyNDays(n: 4)),
      );
      expect(
        PeriodFactory.everyNDays(n: 4),
        isNot(equals(PeriodFactory.everyNDays(n: 5))),
      );
    });

    test('Period.everyNWeeks set equality', () {
      final a = PeriodFactory.everyNWeeks(n: 2, weekdays: {1, 3, 5});
      final b = PeriodFactory.everyNWeeks(n: 2, weekdays: {5, 1, 3});
      expect(a, equals(b));
    });

    test('Period.monthlyDay preserves day', () {
      expect(
        PeriodFactory.monthlyDay(day: 15),
        equals(PeriodFactory.monthlyDay(day: 15)),
      );
    });
  });

  group('PersonPatch', () {
    test('PersonPatch equality', () {
      const p = PersonPatch(name: '王站', relation: PersonRelation.colleague);
      expect(
        p,
        equals(const PersonPatch(name: '王站', relation: PersonRelation.colleague)),
      );
    });

    test('PersonPatch hashCode stable', () {
      expect(
        const PersonPatch(name: 'x').hashCode,
        const PersonPatch(name: 'x').hashCode,
      );
    });
  });
}