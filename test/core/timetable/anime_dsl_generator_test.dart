import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/timetable/service/config/anime_dsl_generator.dart';
import 'package:xiaodouzi_fr/core/timetable/service/config/timetable_dsl_parser.dart';

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  group('AnimeSeriesDraft 序列化往返', () {
    test('toJson/fromJson 保持全部字段与 id', () {
      final draft = AnimeSeriesDraft(
        id: 'anime_123',
        title: '剧A',
        startDateIso: '2026-08-10',
        weekday: 6,
        time: '11:00',
        episodes: 10,
        durationMin: 60,
      );
      final restored = AnimeSeriesDraft.fromJson(draft.toJson());
      expect(restored.id, 'anime_123');
      expect(restored.title, '剧A');
      expect(restored.startDateIso, '2026-08-10');
      expect(restored.weekday, 6);
      expect(restored.time, '11:00');
      expect(restored.episodes, 10);
      expect(restored.durationMin, 60);
    });

    test('缺字段回退默认值', () {
      final restored = AnimeSeriesDraft.fromJson(const {});
      expect(restored.title, '');
      expect(restored.weekday, 1);
      expect(restored.episodes, 13);
      expect(restored.durationMin, 45);
    });
  });

  group('backfillStartDate 反推开始日期', () {    final today = DateTime.now();

    test('当前第1期 = 今天往前最近的该星期', () {
      final result = backfillStartDate(1, today.weekday);
      expect(result, _iso(today));
    });

    test('当前第3期 = 最近播出日 - 14 天', () {
      final expectDate = today.subtract(const Duration(days: 14));
      final result = backfillStartDate(3, today.weekday);
      expect(result, _iso(expectDate));
    });

    test('星期早于今天：最近播出日是本周该星期', () {
      // 目标星期 = 今天的星期 - 1（若今天周一则回绕到周日）
      final targetWeekday = today.weekday == 1 ? 7 : today.weekday - 1;
      final result = backfillStartDate(1, targetWeekday);
      // 最近 targetWeekday：若 target 星期在昨天之前，就是本周的；否则上周
      final expectDate = today.subtract(Duration(days: today.weekday - targetWeekday));
      expect(result, _iso(expectDate));
    });
  });

  group('normalizeAnimeTimeInput 时间自动对齐', () {
    test('2位数字补整点：22 → 22:00，9 → 09:00', () {
      expect(normalizeAnimeTimeInput('22'), '22:00');
      expect(normalizeAnimeTimeInput('9'), '09:00');
    });
    test('3-4位数字拆时分：2230 → 22:30，930 → 09:30', () {
      expect(normalizeAnimeTimeInput('2230'), '22:30');
      expect(normalizeAnimeTimeInput('930'), '09:30');
    });
    test('原有 HH:mm 形态归一：22:30 / 09:05', () {
      expect(normalizeAnimeTimeInput('22:30'), '22:30');
      expect(normalizeAnimeTimeInput('09:05'), '09:05');
      expect(normalizeAnimeTimeInput('0:00'), '00:00');
    });
    test('非法输入返回 null', () {
      expect(normalizeAnimeTimeInput(''), isNull);
      expect(normalizeAnimeTimeInput(':'), isNull);
      expect(normalizeAnimeTimeInput('24'), isNull); // 小时越界
      expect(normalizeAnimeTimeInput('2260'), isNull); // 分钟越界
      expect(normalizeAnimeTimeInput('12345'), isNull); // 超4位
      expect(normalizeAnimeTimeInput('9:5'), isNull); // 数字部分95=非法小时
    });
  });

  group('DSL 周次范围语法', () {
    test('w2-16 范围解析', () {
      final result = parseDsl('剧b @ 6 2 w2-16 23:00 更新');
      expect(result.errors, isEmpty);
      expect(result.courses, hasLength(1));
      expect(result.courses.first.visibleInCycles, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]);
    });

    test('混用列表与范围 w1-3,5', () {
      final result = parseDsl('课程 @ 1 1 w1-3,5');
      expect(result.courses.first.visibleInCycles, [0, 1, 2, 4]);
    });

    test('非法范围 w5-2 报错', () {
      final result = parseDsl('课程 @ 1 1 w5-2');
      expect(result.errors, isNotEmpty);
      expect(result.courses, isEmpty);
    });

    test('formatCycleList 范围压缩', () {
      expect(formatCycleList([0, 1, 2, 3, 4]), '1-5');
      expect(formatCycleList([0, 2, 4]), '1,3,5');
      expect(formatCycleList([1, 2, 3, 5, 6]), '2-4,6-7');
      expect(formatCycleList([]), '');
    });
  });

  group('buildAnimeDsl 追剧生成器', () {
    test('基础：单剧单时间组', () {
      final result = buildAnimeDsl([
        AnimeSeriesInput(
          title: '剧a',
          startDateIso: '2026-08-15', // 周六
          weekday: 6,
          time: '11:00',
          episodes: 10,
          durationMin: 60,
        ),
      ]);
      expect(result.config.daysPerCycle, 7);
      expect(result.config.slotsPerDay, 1);
      expect(result.config.cycleCount, 10);
      expect(result.config.isAnimeMode, true);
      expect(result.config.leftLabelMode, 1);
      expect(result.config.slotStartTimes, ['11:00']);
      expect(result.config.slotDurationMin, 60);
      expect(result.config.startDateIso, '2026-08-10'); // 对齐周一
      expect(result.items, hasLength(1));
      expect(result.items.first.dayOfCycle, 5); // 周六
      expect(result.items.first.visibleInCycles, List.generate(10, (i) => i));
      expect(result.dsl, contains('mode=anime'));
    });

    test('多剧多时间组：竖直两 cell + 自动周期（用户示例）', () {
      // 1周开始a，时间11-12；2周开始b，时间23点，15期 → 共16周期
      final result = buildAnimeDsl([
        AnimeSeriesInput(
          title: '剧a',
          startDateIso: '2026-08-10', // 周一（第1周）
          weekday: 1,
          time: '11:00',
          episodes: 5,
        ),
        AnimeSeriesInput(
          title: '剧b',
          startDateIso: '2026-08-17', // 周一（第2周）
          weekday: 1,
          time: '23:00',
          episodes: 15,
        ),
      ]);
      expect(result.config.slotsPerDay, 2); // 竖直两个 cell
      expect(result.config.slotStartTimes, ['11:00', '23:00']);
      expect(result.config.cycleCount, 16); // 2+15-1 = 16 周
      expect(result.items, hasLength(2));
      // 时间组：a → slot0, b → slot1
      final a = result.items.firstWhere((i) => i.title == '剧a');
      final b = result.items.firstWhere((i) => i.title == '剧b');
      expect(a.slotIndex, 0);
      expect(b.slotIndex, 1);
      expect(a.visibleInCycles, [0, 1, 2, 3, 4]);
      expect(b.visibleInCycles, List.generate(15, (i) => 1 + i));
    });

    test('相同播出时间归同一 cell', () {
      final result = buildAnimeDsl([
        AnimeSeriesInput(
          title: '剧a',
          startDateIso: '2026-08-10',
          weekday: 1,
          time: '20:00',
          episodes: 3,
        ),
        AnimeSeriesInput(
          title: '剧b',
          startDateIso: '2026-08-10',
          weekday: 3, // 不同星期
          time: '20:00',
          episodes: 3,
        ),
      ]);
      expect(result.config.slotsPerDay, 1);
      expect(
        result.items.map((i) => i.slotIndex).toSet(),
        {0},
      );
    });

    test('无时间的剧独立扩容 cell，按输入顺序排在有时间各组之前', () {
      // API 导入的 A/B/C 无时间 + 自定义 D 有时间 → 共 4 个 slot
      final result = buildAnimeDsl([
        AnimeSeriesInput(
          title: 'A',
          startDateIso: '2026-08-10',
          weekday: 1,
          time: '', // 未补时间
          episodes: 12,
        ),
        AnimeSeriesInput(
          title: 'B',
          startDateIso: '2026-08-10',
          weekday: 1,
          time: '',
          episodes: 12,
        ),
        AnimeSeriesInput(
          title: 'C',
          startDateIso: '2026-08-10',
          weekday: 1,
          time: '',
          episodes: 12,
        ),
        AnimeSeriesInput(
          title: 'D',
          startDateIso: '2026-08-10',
          weekday: 1,
          time: '22:00',
          episodes: 12,
        ),
      ]);
      expect(result.config.slotsPerDay, 4);
      final a = result.items.firstWhere((i) => i.title == 'A');
      final b = result.items.firstWhere((i) => i.title == 'B');
      final c = result.items.firstWhere((i) => i.title == 'C');
      final d = result.items.firstWhere((i) => i.title == 'D');
      expect(a.slotIndex, 0); // 输入顺序 1,2,3
      expect(b.slotIndex, 1);
      expect(c.slotIndex, 2);
      expect(d.slotIndex, 3); // 有时间的排最后
      // 未补时间组 slotStartTimes 留空 → 渲染回退节次序号 1/2/3
      expect(result.config.slotStartTimes, ['', '', '', '22:00']);
      expect(a.location, contains('时间待补'));
      expect(d.location, contains('22:00'));
    });

    test('全部无时间：每部独立 cell 且标签全空回退序号', () {
      final result = buildAnimeDsl([
        AnimeSeriesInput(
          title: 'A',
          startDateIso: '2026-08-10',
          weekday: 2,
          time: '',
          episodes: 10,
        ),
        AnimeSeriesInput(
          title: 'B',
          startDateIso: '2026-08-10',
          weekday: 5,
          time: '',
          episodes: 10,
        ),
      ]);
      expect(result.config.slotsPerDay, 2);
      expect(result.items.map((i) => i.slotIndex).toSet(), {0, 1});
      expect(result.config.slotStartTimes, ['', '']);
    });

    test('早于周一的开始日期也回退到周一（跨周安全）', () {
      final result = buildAnimeDsl([
        AnimeSeriesInput(
          title: '剧c',
          startDateIso: '2026-08-12', // 周三
          weekday: 3,
          time: '12:00',
          episodes: 2,
        ),
      ]);
      expect(result.config.startDateIso, '2026-08-10');
      expect(result.items.first.visibleInCycles, [0, 1]);
    });

    test('生成 DSL 可回灌解析还原', () {
      final result = buildAnimeDsl([
        AnimeSeriesInput(
          title: '剧a',
          startDateIso: '2026-08-10',
          weekday: 1,
          time: '11:00',
          episodes: 5,
        ),
      ]);
      final parsed = parseDsl(result.dsl);
      expect(parsed.errors, isEmpty);
      expect(parsed.config, isNotNull);
      expect(parsed.config!.cycleCount, result.config.cycleCount);
      expect(parsed.config!.startDateIso, result.config.startDateIso);
      expect(parsed.courses, hasLength(1));
      expect(parsed.courses.first.title, '剧a');
      expect(parsed.courses.first.visibleInCycles, [0, 1, 2, 3, 4]);
    });
  });
}
