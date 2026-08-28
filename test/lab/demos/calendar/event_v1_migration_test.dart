import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/calendar_config.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/event_v1_migration.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/anchor.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/period.dart';

/// Fake v1 Event instance (模拟 typed box → dynamic 读取后的对象）。
/// 仅暴露字段 getter；不实现 Event v2 API。
class _FakeV1Event {
  final String id;
  final String title;
  final String type;
  final String system;
  final int year;
  final int month;
  final int day;
  final String recurrence;
  final String colorTag;
  final int? everyNDays;
  final bool isLeap;
  final int? lunarAnchorYear;
  final String? note;
  _FakeV1Event({
    required this.id,
    required this.title,
    required this.type,
    required this.system,
    required this.year,
    required this.month,
    required this.day,
    required this.recurrence,
    required this.colorTag,
    this.everyNDays,
    this.isLeap = false,
    this.lunarAnchorYear,
    this.note,
  });
}

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

  test('decodes typed v1 Event instance (Box<dynamic> read)', () {
    final fake = _FakeV1Event(
      id: 'e1',
      title: 'typed-event',
      type: 'birthday',
      system: 'solar',
      year: 2024,
      month: 6,
      day: 1,
      recurrence: 'yearly',
      colorTag: 'red',
    );
    final r = EventV1Migration.run([fake]);
    expect(r.droppedIds, isEmpty);
    final d = r.drafts.single;
    expect(d.title, 'typed-event');
    expect(d.type.name, 'birthday');
    expect((d.anchor as SolarAnchor).month, 6);
    expect(d.period, PeriodFactory.yearly());
  });
}