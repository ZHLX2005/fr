import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/data/calendar_config.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/service/dsl/dsl_parser.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/service/dsl/dsl_interpreter.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/anchor.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/domain/period.dart';

void main() {
  CalendarConfig cfg() => const CalendarConfig(startDateIso: '2025-01-01');

  test('yearly solar → Anchor.solar + Period.yearly', () {
    final r = interpret(parseCalendarDsl(
      'event "x" { period=yearly /month=04 /day=15 }',
    ).stmts, config: cfg());
    expect(r.errors, isEmpty);
    final d = r.drafts.single;
    expect((d.anchor as SolarAnchor).day, 15);
    expect((d.anchor as SolarAnchor).year, 2025);
    expect(d.period, PeriodFactory.yearly());
  });

  test('every-days weekday-ignored', () {
    final r = interpret(parseCalendarDsl(
      'event "x" { period=every-days /days=4 /start=2025-01-01 /until=2025-01-31 }',
    ).stmts, config: cfg());
    expect(r.errors, isEmpty);
    final p = r.drafts.single.period as EveryNDaysPeriod;
    expect(p.n, 4);
  });

  test('monthly-nth rejects nth>5', () {
    final r = interpret(parseCalendarDsl(
      'event "x" { period=monthly-nth /nth=6 /weekday=Fri }',
    ).stmts, config: cfg());
    expect(r.errors, isNotEmpty);
  });

  test('illegal period key reports error', () {
    final r = interpret(parseCalendarDsl(
      'event "x" { period=yearly /month=04 /day=15 /banana=1 }',
    ).stmts, config: cfg());
    expect(r.errors, isNotEmpty);
  });

  test('lunar yearly sets isLeap', () {
    final r = interpret(parseCalendarDsl(
      'event "x" { period=yearly /system=lunar /month=04 /day=15 /isLeap=true }',
    ).stmts, config: cfg());
    expect(r.errors, isEmpty);
    final a = r.drafts.single.anchor as LunarAnchor;
    expect(a.isLeap, true);
  });

  test('monthly-nth anchors to first occurrence of rule', () {
    // 2025-01-01 是周三；3rd Friday of Jan 2025 = 2025-01-17
    final r = interpret(parseCalendarDsl(
      'event "pay" { period=monthly-nth /nth=3 /weekday=Fri }',
    ).stmts, config: cfg());
    expect(r.errors, isEmpty);
    final a = r.drafts.single.anchor as SolarAnchor;
    expect(a.month, 1);
    expect(a.day, 17);
  });
}