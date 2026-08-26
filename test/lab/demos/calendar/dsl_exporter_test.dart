import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/calendar_config.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/event.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/anchor.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/period.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/service/dsl/dsl_exporter.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/service/dsl/dsl_parser.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/service/dsl/dsl_interpreter.dart';

void main() {
  Event yearly() => Event(
        id: 'e1',
        title: '妈生日',
        type: EventType.birthday,
        anchor: const LunarAnchor(month: 4, day: 15, isLeap: false, year: 2025),
        period: PeriodFactory.yearly(),
        colorTag: ColorTag.red,
        groupId: 'default',
        createdAt: DateTime(2025, 1, 1),
      );

  test('export yearly then parse then interpret preserves fields', () {
    final text = exportCalendarDsl([yearly()], config: const CalendarConfig(startDateIso: '2025-01-01'));
    final parsed = parseCalendarDsl(text);
    final interp = interpret(parsed.stmts, config: const CalendarConfig(startDateIso: '2025-01-01'));
    expect(interp.errors, isEmpty);
    final d = interp.drafts.single;
    expect(d.title, '妈生日');
    expect((d.anchor as LunarAnchor).month, 4);
    expect((d.anchor as LunarAnchor).day, 15);
    expect(d.period, PeriodFactory.yearly());
  });

  test('export one-shot produces oneline', () {
    final e = Event(
      id: 'e2',
      title: '聚餐',
      type: EventType.anniversary,
      anchor: const SolarAnchor(month: 8, day: 15, year: 2026),
      period: PeriodFactory.oneShot(),
      colorTag: ColorTag.gray,
      groupId: 'default',
      createdAt: DateTime(2026, 1, 1),
    );
    final text = exportCalendarDsl([e]);
    expect(text, contains('2026-08-15'));
    expect(text, contains('"聚餐"'));
  });
}