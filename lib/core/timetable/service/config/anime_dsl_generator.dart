import '../../domain/models.dart';
import 'timetable_dsl_parser.dart';
import 'timetable_week_calculator.dart';

/// 追剧/番模式 —— 单部剧输入
class AnimeSeriesInput {
  /// 剧名
  final String title;

  /// 开始日期 YYYY-MM-DD
  final String startDateIso;

  /// 播出星期 1-7（1=周一）
  final int weekday;

  /// 当天播出时间 "HH:mm"
  final String time;

  /// 总期数（>=1）
  final int episodes;

  /// 每期时长（分钟），默认 45；同时间组的剧取第一个非默认值
  final int durationMin;

  const AnimeSeriesInput({
    required this.title,
    required this.startDateIso,
    required this.weekday,
    required this.time,
    required this.episodes,
    this.durationMin = 45,
  });
}

/// 追剧 DSL 生成结果
class AnimeDslResult {
  final TimetableConfig config;
  final List<CourseItem> items;
  final String dsl;

  const AnimeDslResult({
    required this.config,
    required this.items,
    required this.dsl,
  });
}

/// 根据剧列表自动生成稳定的课表配置 + 课程 + DSL 文本。
///
/// 算法（纯函数，无 I/O）：
/// 1. 播出时间分组：相同 "HH:mm" 归为同一竖直 cell（slot），按时间升序编号
/// 2. 起始日期 = 最早开播日期所在周的周一（自动对齐周一）
/// 3. 每部剧按开始周落位：visibleInCycles = [开始周 .. 开始周+期数-1]
/// 4. 周期总数 = 所有剧覆盖的最大周数（自动膨胀/收缩，无需手动配置）
/// 5. 一周 7 天；左侧指示 = 时间段模式（slotStartTimes 来自各时间组）
/// 6. 输出 DSL 文本（config 段 + 课程行 w 范围），可回灌 parseDsl 还原
AnimeDslResult buildAnimeDsl(List<AnimeSeriesInput> series) {
  final now = DateTime.now().millisecondsSinceEpoch;

  // 1. 时间分组（按 "HH:mm" 升序）
  final times = <String>{};
  for (final s in series) {
    times.add(s.time);
  }
  final sortedTimes = times.toList()..sort();
  final groupIndexOf = <String, int>{
    for (var i = 0; i < sortedTimes.length; i++) sortedTimes[i]: i,
  };

  // 2. 起始日期对齐周一
  final earliestStart = series
      .map((s) => DateTime.parse(s.startDateIso))
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final monday = findNearestMondayOnOrBefore(earliestStart);
  final startDateIso =
      '${monday.year.toString().padLeft(4, '0')}-'
      '${monday.month.toString().padLeft(2, '0')}-'
      '${monday.day.toString().padLeft(2, '0')}';

  // 3+4. 每部剧落位 + 周期总数
  final items = <CourseItem>[];
  var maxCycles = 1;
  final startTimes = List<String>.filled(sortedTimes.length, '');
  var duration = series.isEmpty ? 45 : series.first.durationMin;
  for (final s in series) {
    final start = DateTime.parse(s.startDateIso);
    final dayOffset = start.difference(monday).inDays;
    final weekOffset = dayOffset < 0 ? 0 : dayOffset ~/ 7;
    final cycles = List.generate(
      s.episodes,
      (i) => weekOffset + i,
    );
    final endCycle = weekOffset + s.episodes;
    if (endCycle > maxCycles) maxCycles = endCycle;

    final group = groupIndexOf[s.time]!;
    if (startTimes[group].isEmpty) startTimes[group] = s.time;
    if (s.durationMin != 45 && duration == 45) duration = s.durationMin;

    items.add(CourseItem(
      id: 'anime_${s.title}_${s.weekday}_${group}_$now',
      dayOfCycle: s.weekday - 1,
      slotIndex: group,
      title: s.title,
      location: '${s.time} 更新 · ${s.episodes}期',
      colorSeed: (s.title.hashCode.abs() % 1000),
      version: 1,
      visibleInCycles: cycles,
      createdAt: now,
      updatedAt: now,
    ));
  }

  // config
  final config = TimetableConfig(
    startDateIso: startDateIso,
    cycleCount: maxCycles,
    daysPerCycle: 7,
    slotsPerDay: sortedTimes.length,
    isSchoolMode: false,
    isAnimeMode: true,
    leftLabelMode: 1,
    slotStartTimes: startTimes,
    slotDurationMin: duration,
  );

  // DSL 文本（config 段 + 课程行 w 范围）
  final buffer = StringBuffer();
  buffer.writeln(
    'config: days=7 slots=${sortedTimes.length} cycles=$maxCycles '
    'start=$startDateIso mode=anime left=1 duration=$duration',
  );
  buffer.writeln('# 追剧模式自动生成：${series.length} 部剧 · 起始 $startDateIso · 共 $maxCycles 周');
  buffer.writeln('');
  for (final item in items) {
    final weekday = item.dayOfCycle + 1;
    final slot = item.slotIndex + 1;
    final weeks = formatCycleList(item.visibleInCycles ?? const []);
    buffer.writeln('${item.title} @ $weekday $slot w$weeks ${item.location}');
  }

  return AnimeDslResult(
    config: config,
    items: items,
    dsl: buffer.toString(),
  );
}
