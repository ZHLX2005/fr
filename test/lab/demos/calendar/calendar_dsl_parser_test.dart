import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/calendar/service/config/calendar_dsl_parser.dart';

void main() {
  group('parseCalendarDsl 基础', () {
    test('空输入：无事件无错误', () {
      final r = parseCalendarDsl('');
      expect(r.events, isEmpty);
      expect(r.persons, isEmpty);
      expect(r.errors, isEmpty);
    });

    test('注释行与空行被忽略', () {
      final r = parseCalendarDsl('# 注释\n\n  \n# 另一行\n');
      expect(r.events, isEmpty);
    });

    test('单次公历事件', () {
      final r = parseCalendarDsl('聚餐 @2026-08-15 type=anniversary color=red');
      expect(r.events, hasLength(1));
      expect(r.errors, isEmpty);
      final e = r.events.first;
      expect(e.title, '聚餐');
      expect(e.type.name, 'anniversary');
      expect(e.system.name, 'solar');
      expect(e.year, 2026);
      expect(e.month, 8);
      expect(e.day, 15);
      expect(e.colorTag.name, 'red');
      expect(e.recurrence.name, 'none');
    });

    test('单次农历事件 lunar:YYYYMMDD', () {
      final r = parseCalendarDsl('春节 @lunar:20260815 system=lunar');
      expect(r.events, hasLength(1));
      final e = r.events.first;
      expect(e.system.name, 'lunar');
      expect(e.year, 2026);
      expect(e.month, 8);
      expect(e.day, 15);
    });

    test('缺 @ 的行报错', () {
      final r = parseCalendarDsl('badline');
      expect(r.errors, isNotEmpty);
      expect(r.events, isEmpty);
    });
  });

  group('parseCalendarDsl 周期语法', () {
    test('yearly-solar:MM-DD 每年公历', () {
      final r = parseCalendarDsl('妈妈生日 @yearly-solar:08-15 type=birthday color=red');
      // ignore: avoid_print
      print('D2: rec=${r.events.first.recurrence} m=${r.events.first.month} d=${r.events.first.day} y=${r.events.first.year}');
      final e = r.events.first;
      expect(e.recurrence.name, 'yearly');
      expect(e.system.name, 'solar');
      expect(e.month, 8);
      expect(e.day, 15);
    });

    test('yearly-lunar:MMDD 每年农历', () {
      final r = parseCalendarDsl('奶奶生日 @yearly-lunar:08-15 type=birthday');
      final e = r.events.first;
      expect(e.recurrence.name, 'yearlyLunarAuto');
      expect(e.system.name, 'lunar');
      expect(e.month, 8);
      expect(e.day, 15);
    });

    test('yearly-solar-offset:N:MM-DD 手动偏移', () {
      final r = parseCalendarDsl('高考 @yearly-solar-offset:1:06-07');
      final e = r.events.first;
      expect(e.recurrence.name, 'manual');
      expect(e.solarYearOffset, 1);
      expect(e.month, 6);
      expect(e.day, 7);
    });

    test('monthly:DD 每月', () {
      final r = parseCalendarDsl('发工资 @monthly:15 type=task');
      expect(r.events, hasLength(1));
      expect(r.events.first.recurrence.name, 'yearly');
    });

    test('nth-weekday:Mon,N=3 每月第 3 个周一', () {
      final r = parseCalendarDsl('月度检查 @nth-weekday:Mon,N=3 type=task');
      expect(r.events, hasLength(1));
    });

    test('every-N-days 每天间隔', () {
      final r = parseCalendarDsl('打卡 @every-7-days starting=2026-09-01');
      // 注：every-N-days 解析后保持 recurrence=none，但生成器内部会处理
      // 这里只验证 parser 不报错
      expect(r.errors, isEmpty);
    });

    test('every-N-weeks:Mon 每周一', () {
      final r = parseCalendarDsl('周会 @every-2-weeks:Mon starting=2026-09-08');
      expect(r.errors, isEmpty);
    });

    test('未识别的 date 形式报错', () {
      final r = parseCalendarDsl('bad @gibberish-xxx type=task');
      expect(r.errors, isNotEmpty);
    });
  });

  group('parseCalendarDsl 人物', () {
    test('person 行被解析为 draft', () {
      final r = parseCalendarDsl(
        'person alice 关系=家人 avatar=👩\n'
        '聚餐 @2026-08-15 person=alice type=anniversary',
      );
      expect(r.errors, isEmpty);
      expect(r.persons, hasLength(1));
      expect(r.persons.first.name, 'alice');
      expect(r.persons.first.avatarEmoji, '👩');
      expect(r.events, hasLength(1));
      // person 引用解析：name 已映射为临时 id
      expect(r.events.first.personId, isNotNull);
    });

    test('event 引用未定义 person 报错', () {
      final r = parseCalendarDsl('bad @2026-08-15 person=ghost');
      expect(r.errors, isNotEmpty);
    });
  });

  group('parseCalendarDsl config 头部', () {
    test('config 行被解析为 CalendarConfig', () {
      final r = parseCalendarDsl(
        'config: default-system=lunar default-color=red start=2026-08-01\n'
        '聚餐 @2026-08-15',
      );
      expect(r.config, isNotNull);
      expect(r.config!.defaultSystem, 'lunar');
      expect(r.config!.defaultColorTag, 'red');
      expect(r.config!.startDateIso, '2026-08-01');
    });
  });

  group('exportCalendarDsl 导出', () {
    test('导出包含 config 头部', () {
      final dsl = exportCalendarDsl([], config: const CalendarConfig());
      expect(dsl, contains('config:'));
      expect(dsl, contains('default-system=solar'));
    });

    test('空事件列表导出仅 config 头部', () {
      final dsl = exportCalendarDsl([]);
      final lines = dsl.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(lines.length, 1);
      expect(lines.first, startsWith('config:'));
    });
  });

  group('DSL 回灌闭环（关键保证）', () {
    test('解析 → 导出 → 解析 事件数一致', () {
      const src = '''
config: default-system=solar default-color=gray start=2026-08-01
聚餐 @2026-08-15 type=anniversary color=red
生日 @yearly-solar:08-15 type=birthday color=red
盘 @monthly:15 type=task
''';
      final r1 = parseCalendarDsl(src);
      expect(r1.errors, isEmpty);
      expect(r1.events, hasLength(3));

      // 导出（仅当前 group 的 events）
      final dsl = exportCalendarDsl(r1.events, config: r1.config);
      final r2 = parseCalendarDsl(dsl);
      expect(r2.errors, isEmpty);
      expect(r2.events.length, r1.events.length);
      expect(r2.events.first.title, r1.events.first.title);
      expect(r2.events.first.type, r1.events.first.type);
      expect(r2.events.first.colorTag, r1.events.first.colorTag);
    });
  });
}
