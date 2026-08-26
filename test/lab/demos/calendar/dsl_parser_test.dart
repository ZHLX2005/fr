import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/service/dsl/dsl_parser.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/service/dsl/dsl_ast.dart';

void main() {
  test('config block parses', () {
    final r = parseCalendarDsl('config { default-system=solar start=2025-01-01 }');
    expect(r.errors, isEmpty);
    expect(r.stmts, hasLength(1));
    expect(r.stmts.first, isA<AstConfig>());
    expect((r.stmts.first as AstConfig).pairs['default-system'], 'solar');
  });

  test('people block parses', () {
    final r = parseCalendarDsl('people { "妈" { relation=family avatar=👩 } }');
    expect(r.errors, isEmpty);
    expect(r.stmts, hasLength(1));
    final pb = r.stmts.first as AstPeopleBlock;
    expect(pb.entries, hasLength(1));
    expect(pb.entries.first.name, '妈');
    expect(pb.entries.first.attrs['relation'], 'family');
  });

  test('event block parses all fields including period path', () {
    final r = parseCalendarDsl('''
event "妈生日" {
  type=birthday
  system=lunar
  period=yearly /month=04 /day=15
  color=red
  people=[{name="妈", relation=family}]
  note=ok
}
''');
    expect(r.errors, isEmpty);
    expect(r.stmts, hasLength(1));
    final eb = r.stmts.first as AstEventBlock;
    expect(eb.title, '妈生日');
    expect((eb.fields['type'] as AstString).text, 'birthday');
    expect((eb.fields['period'] as AstPeriod).kind, 'yearly');
    expect(((eb.fields['period'] as AstPeriod).tail['month'] as AstNumber).n, 4);
  });

  test('one-liner event parses', () {
    final r = parseCalendarDsl('"聚餐" @2026-08-15 type=anniversary color=red');
    expect(r.errors, isEmpty);
    expect(r.stmts, hasLength(1));
    expect(r.stmts.first, isA<AstEventOneline>());
    final eo = r.stmts.first as AstEventOneline;
    expect(eo.title, '聚餐');
    expect(eo.dateExprText, '2026-08-15');
    expect(eo.attrs['type'], 'anniversary');
  });

  test('one-liner with period kind', () {
    final r = parseCalendarDsl('"生日" @yearly:08-15 type=birthday');
    expect(r.errors, isEmpty);
    expect(r.stmts, hasLength(1));
    final eo = r.stmts.first as AstEventOneline;
    expect(eo.dateExprText, 'yearly:08-15');
  });

  test('bad token inside event accumulates and recovers', () {
    final r = parseCalendarDsl('''
event "x" { =foo }
"y" @2026-01-01 type=task
''');
    expect(r.errors, isNotEmpty);
    expect(r.stmts.length, greaterThanOrEqualTo(1));
  });

  test('monthly-nth weekday path parses', () {
    final r = parseCalendarDsl('''
event "pay" {
  period=monthly-nth /nth=3 /weekday=Fri
}
''');
    expect(r.errors, isEmpty);
    final eb = r.stmts.first as AstEventBlock;
    final p = eb.fields['period'] as AstPeriod;
    expect(p.kind, 'monthly-nth');
    expect((p.tail['nth'] as AstNumber).n, 3);
    expect((p.tail['weekday'] as AstString).text, 'Fri');
  });

  test('unknown top-level keyword yields error', () {
    final r = parseCalendarDsl('garbage');
    expect(r.errors, isNotEmpty);
  });
}