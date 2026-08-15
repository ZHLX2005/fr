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

/// 可编辑的剧模型（追剧模式 SSOT，持久化于空间 record 的 animeSeries 字段）。
///
/// 字段完全使用"剧的语言"：剧名/开播日期(或当前期数反推)/星期/播出时间/
/// 总期数/每集时长 —— 不暴露行/列/周期/slot 等程序概念。
/// DSL 由剧模型自动派生（buildAnimeDsl），剧变更 → 自动重算并应用。
class AnimeSeriesDraft {
  final String id;
  String title;
  String startDateIso;
  int weekday;
  String time;
  int episodes;
  int durationMin;

  AnimeSeriesDraft({
    String? id,
    required this.title,
    required this.startDateIso,
    this.weekday = 1,
    required this.time,
    this.episodes = 13,
    this.durationMin = 45,
  }) : id = id ?? 'anime_${DateTime.now().microsecondsSinceEpoch}';

  AnimeSeriesInput toInput() => AnimeSeriesInput(
    title: title,
    startDateIso: startDateIso,
    weekday: weekday,
    time: time,
    episodes: episodes,
    durationMin: durationMin,
  );

  factory AnimeSeriesDraft.fromInput(AnimeSeriesInput i) => AnimeSeriesDraft(
    title: i.title,
    startDateIso: i.startDateIso,
    weekday: i.weekday,
    time: i.time,
    episodes: i.episodes,
    durationMin: i.durationMin,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startDateIso': startDateIso,
    'weekday': weekday,
    'time': time,
    'episodes': episodes,
    'durationMin': durationMin,
  };

  factory AnimeSeriesDraft.fromJson(Map<String, dynamic> json) =>
      AnimeSeriesDraft(
        id: json['id'] as String?,
        title: json['title'] as String? ?? '',
        startDateIso: json['startDateIso'] as String? ?? '',
        weekday: json['weekday'] as int? ?? 1,
        time: json['time'] as String? ?? '',
        episodes: json['episodes'] as int? ?? 13,
        durationMin: json['durationMin'] as int? ?? 45,
      );
}

/// 反推开始日期：当前第 [currentEpisode] 期、播出星期 [weekday]，
/// 从"今天往前最近的该星期"再回推 (期数-1) 周。
/// 返回 YYYY-MM-DD；[weekday] 1=周一 … 7=周日。
String backfillStartDate(int currentEpisode, int weekday) {
  final today = DateTime.now();
  var daysBack = today.weekday - weekday; // DateTime.weekday 1=周一
  if (daysBack < 0) daysBack += 7;
  final anchor = today.subtract(Duration(days: daysBack));
  final start = anchor.subtract(Duration(days: (currentEpisode - 1) * 7));
  return '${start.year.toString().padLeft(4, '0')}-'
      '${start.month.toString().padLeft(2, '0')}-'
      '${start.day.toString().padLeft(2, '0')}';
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
/// 1. 时间分组：相同 "HH:mm" 归为同一竖直 cell（slot），按时间升序编号；
///    未补时间的剧（time 为空，多来自 API 导入）每部独立扩容一个 cell，
///    按输入顺序编号排在有时间各组之前，避免同 cell 堆叠不可读
/// 2. 起始日期 = 最早开播日期所在周的周一（自动对齐周一）
/// 3. 每部剧按开始周落位：visibleInCycles = [开始周 .. 开始周+期数-1]
/// 4. 周期总数 = 所有剧覆盖的最大周数（自动膨胀/收缩，无需手动配置）
/// 5. 一周 7 天；左侧指示 = 时间段模式（slotStartTimes 来自各时间组，
///    空 time 组留空 → 渲染回退为节次序号）
/// 6. 输出 DSL 文本（config 段 + 课程行 w 范围），可回灌 parseDsl 还原
AnimeDslResult buildAnimeDsl(List<AnimeSeriesInput> series) {
  final now = DateTime.now().millisecondsSinceEpoch;

  // 1. 时间分组：未补时间的剧独立成组（输入顺序在前），
  //    有时间的按 "HH:mm" 去重升序在后
  final timeSet = <String>{};
  for (final s in series) {
    if (s.time.isNotEmpty) timeSet.add(s.time);
  }
  final sortedTimes = timeSet.toList()..sort();
  final groupIndexOf = <String, int>{};
  // 未补时间的剧：以输入序号为 key，各占一组
  for (var i = 0; i < series.length; i++) {
    if (series[i].time.isEmpty) groupIndexOf['untimed_$i'] = groupIndexOf.length;
  }
  // 有时间的剧：按时间归组
  for (final t in sortedTimes) {
    groupIndexOf[t] = groupIndexOf.length;
  }
  final slotCount = groupIndexOf.length;

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
  final startTimes = List<String>.filled(slotCount, '');
  var duration = series.isEmpty ? 45 : series.first.durationMin;
  for (var idx = 0; idx < series.length; idx++) {
    final s = series[idx];
    final start = DateTime.parse(s.startDateIso);
    final dayOffset = start.difference(monday).inDays;
    final weekOffset = dayOffset < 0 ? 0 : dayOffset ~/ 7;
    final cycles = List.generate(
      s.episodes,
      (i) => weekOffset + i,
    );
    final endCycle = weekOffset + s.episodes;
    if (endCycle > maxCycles) maxCycles = endCycle;

    final group = s.time.isEmpty
        ? groupIndexOf['untimed_$idx']!
        : groupIndexOf[s.time]!;
    if (startTimes[group].isEmpty) startTimes[group] = s.time;
    if (s.durationMin != 45 && duration == 45) duration = s.durationMin;

    items.add(CourseItem(
      id: 'anime_${s.title}_${s.weekday}_${group}_$now',
      dayOfCycle: s.weekday - 1,
      slotIndex: group,
      title: s.title,
      location: s.time.isEmpty
          ? '时间待补 · ${s.episodes}期'
          : '${s.time} 更新 · ${s.episodes}期',
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
    slotsPerDay: slotCount,
    isSchoolMode: false,
    isAnimeMode: true,
    leftLabelMode: 1,
    slotStartTimes: startTimes,
    slotDurationMin: duration,
  );

  // DSL 文本（config 段 + 课程行 w 范围）
  final buffer = StringBuffer();
  buffer.writeln(
    'config: days=7 slots=$slotCount cycles=$maxCycles '
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
