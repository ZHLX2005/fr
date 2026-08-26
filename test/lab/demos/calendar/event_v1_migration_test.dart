import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/calendar_config.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/event_v1_migration.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/anchor.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/period.dart';

void main() {
  test('yearly solar', () {
    final r = EventV1Migration.run([
      {
        'id': 'e1',
        'title': 't',
        'type': 'custom',
        'system': 'solar',
        'year': 2025,
        'month': 8,
        'day': 15,
        'recurrence': 'yearly',
        'colorTag': 'gray',
      },
    ]);
    expect(r.droppedIds, isEmpty);
    final d = r.drafts.single;
    expect((d.anchor as SolarAnchor).day, 15);
    expect(d.period, PeriodFactory.yearly());
  });

  test('every-N-days', () {
    final r = EventV1Migration.run([
      {
        'id': 'e2',
        'title': '值班',
        'type': 'task',
        'system': 'solar',
        'year': 2025,
        'month': 1,
        'day': 1,
        'everyNDays': 4,
        'recurrence': 'none',
        'colorTag': 'gray',
      },
    ]);
    final p = r.drafts.single.period;
    expect(p, isA<EveryNDaysPeriod>());
    expect((p as EveryNDaysPeriod).n, 4);
  });

  test('unrecognized shape dropped, others kept', () {
    final r = EventV1Migration.run([
      {'this': 'is', 'broken': true},
      {
        'id': 'e1',
        'title': 't',
        'type': 'custom',
        'system': 'solar',
        'year': 2025,
        'month': 8,
        'day': 15,
        'recurrence': 'yearly',
        'colorTag': 'gray',
      },
    ]);
    expect(r.droppedIds, hasLength(1));
    expect(r.drafts, hasLength(1));
  });

  test('config is used for anchor year', () {
    final r = EventV1Migration.run(
      [
        {
          'id': 'e1',
          'title': 't',
          'type': 'custom',
          'system': 'solar',
          'month': 1,
          'day': 1,
          'recurrence': 'yearly',
          'colorTag': 'gray',
        },
      ],
      config: const CalendarConfig(startDateIso: '2030-01-01'),
    );
    expect((r.drafts.single.anchor as SolarAnchor).year, 2030);
  });
}