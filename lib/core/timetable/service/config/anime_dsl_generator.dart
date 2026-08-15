import '../../domain/models.dart';
import 'timetable_dsl_parser.dart';
import 'timetable_week_calculator.dart';

/// 追剧/番模式 —— 单部剧输入
class AnimeSeriesInput {
  /// 剧名
  final String title;

  /// 开始日期 YYYY-MM-DD（可为空 —— 空时该剧锚到当前周，weekOffset=0）
  final String startDateIso;

  /// 播出星期 1-7（1=周一；冗余字段 —— startDateIso 合法时由它推算，
  /// 否则作为回退；保留是为了持久化兼容）
  final int weekday;

  /// 当天播出时间 "HH:mm"（空字符串表示未补，每部独占一个空标签 slot）
  final String time;

  /// 总期数（>=1）
  final int episodes;

  /// 每期时长（分钟），默认 45；同时间组的剧取第一个非默认值
  final int durationMin;

  const AnimeSeriesInput({
    required this.title,
    this.startDateIso = '',
    this.weekday = 1,
    this.time = '',
    this.episodes = 13,
    this.durationMin = 45,
  });
}

/// 可编辑的剧模型（追剧模式 SSOT，持久化于空间 record 的 animeSeries 字段）。
///
/// 字段完全使用"剧的语言"：剧名/开播日期(或当前期数反推)/星期/播出时间/
/// 总集数/每集时长 —— 不暴露行/列/周期/slot 等程序概念。
/// DSL 由剧模型自动派生（buildAnimeDsl），剧变更 → 自动重算并应用。
///
/// **fr 28 简化**：开始日期 / 星期 缺一不可共存 —— 若 [startDateIso] 合法，
/// dayOfCycle 直接由它推算，[weekday] 仅作兜底；用户实际只需记录「播出时间」即可。
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
    this.startDateIso = '',
    this.weekday = 1,
    this.time = '',
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

/// 播出时间输入自动对齐（fr #25）：
/// 很多时候不需要精确到分钟——"22" → "22:00"，"9" → "09:00"，
/// "2230" → "22:30"，原有 "22:30" / "9:5" 形态同样归一为 "HH:mm"。
/// 规则：取纯数字；1-2 位 = 小时（分钟补 00）；3-4 位 = 前段小时后段分钟。
/// 空或非法（小时>23 / 分钟>59 / 数字超 4 位）返回 null，由调用方提示。
String? normalizeAnimeTimeInput(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty || digits.length > 4) return null;
  final int h;
  final int m;
  if (digits.length <= 2) {
    h = int.parse(digits);
    m = 0;
  } else {
    h = int.parse(digits.substring(0, digits.length - 2));
    m = int.parse(digits.substring(digits.length - 2));
  }
  if (h > 23 || m > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
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
/// 算法（纯函数，无 I/O；fr 28 简化 + 鲁棒化）：
/// 1. 每部剧独立占一个 slot（不再按时段堆叠），slot 标签只显示开始时间；
///    分桶 key = (weekday, time) —— 同一 time 但落在不同星期的剧分属不同桶
///    （不会同 cell 堆叠）→ 标签保持纯净不加后缀；
///    真正撞到同一 (星期, 时刻) 的多部剧按出现顺序在标签上加 "(1)", "(2)"
///    等后缀避免视觉覆盖；未补时间的剧每部独占空标签 slot，输入顺序在前
/// 2. 起始日期 = 所有合法 startDateIso 中最早那天对齐周一；
///    全部为空/非法时回退到本周一（修复 fr 28 之前
///    `DateTime.parse(null/'')` 抛异常导致 schedule 全空的崩溃）
/// 3. 每部剧的 dayOfCycle 优先由 startDateIso 推算（weekday 字段冗余但保留
///    兼容），weekOffset = (start - anchor_monday).inDays ~/ 7；
///    startDateIso 为空时 weekOffset=0，dayOfCycle 用 weekday 兜底
/// 4. visibleInCycles = [weekOffset .. weekOffset+episodes-1]
/// 5. 周期总数 = 最长覆盖
/// 6. 输出 DSL 文本（config 段 + 课程行 w 范围），可回灌 parseDsl 还原
AnimeDslResult buildAnimeDsl(List<AnimeSeriesInput> series) {
  final now = DateTime.now().millisecondsSinceEpoch;

  // 1. Slot 分配：每部剧一个 slot；time 重复的按出现顺序加 "(N)" 后缀
  final slotLabels = <String>[];
  final groupIndexOf = <String, int>{};

  // 未补时间的剧：每部独立 slot（在前），label 留空 → 渲染回退节次序号
  for (var i = 0; i < series.length; i++) {
    if (series[i].time.isEmpty) {
      groupIndexOf['untimed_$i'] = slotLabels.length;
      slotLabels.add('');
    }
  }
  // 有时间的剧：按 (weekday, time) 分桶 —— 同一 time 但落在不同星期
  // 不会同 cell 堆叠（不同列），无需 (N) 后缀；只有真正落在同一 (星期, 时刻)
  // 才加 "(1)", "(2)" 后缀保证显示完整
  final buckets = <String, List<int>>{};
  for (var i = 0; i < series.length; i++) {
    if (series[i].time.isNotEmpty) {
      final wd = series[i].weekday.clamp(1, 7);
      final key = '$wd|${series[i].time}';
      buckets.putIfAbsent(key, () => []).add(i);
    }
  }
  final sortedKeys = buckets.keys.toList()..sort();
  for (final k in sortedKeys) {
    final indices = buckets[k]!;
    final t = k.substring(k.indexOf('|') + 1);
    final withSuffix = indices.length > 1;
    for (var n = 0; n < indices.length; n++) {
      final i = indices[n];
      groupIndexOf['timed_$i'] = slotLabels.length;
      slotLabels.add(withSuffix ? '$t (${n + 1})' : t);
    }
  }
  final slotCount = slotLabels.length;

  // 2. 起始日期对齐周一（容忍空 / 非法 startDateIso）
  DateTime monday;
  final validDates = <DateTime>[];
  for (final s in series) {
    if (s.startDateIso.isEmpty) continue;
    try {
      validDates.add(DateTime.parse(s.startDateIso));
    } catch (_) {
      // 非法日期忽略，回退到默认 anchor
    }
  }
  if (validDates.isNotEmpty) {
    final earliest = validDates.reduce((a, b) => a.isBefore(b) ? a : b);
    monday = findNearestMondayOnOrBefore(earliest);
  } else {
    monday = findNearestMondayOnOrBefore(DateTime.now());
  }
  final startDateIso =
      '${monday.year.toString().padLeft(4, '0')}-'
      '${monday.month.toString().padLeft(2, '0')}-'
      '${monday.day.toString().padLeft(2, '0')}';

  // 3+4+5. 每部剧落位 + 周期总数
  final items = <CourseItem>[];
  var maxCycles = 1;
  for (var idx = 0; idx < series.length; idx++) {
    final s = series[idx];

    DateTime? start;
    if (s.startDateIso.isNotEmpty) {
      try {
        start = DateTime.parse(s.startDateIso);
      } catch (_) {
        start = null;
      }
    }

    int weekOffset = 0;
    int dayOfCycle;
    if (start != null) {
      dayOfCycle = start.weekday - 1; // Dart 1=Mon..7=Sun
      final dayOffset = start.difference(monday).inDays;
      weekOffset = dayOffset < 0 ? 0 : dayOffset ~/ 7;
    } else {
      dayOfCycle = (s.weekday - 1).clamp(0, 6);
    }

    final cycles = List.generate(s.episodes, (i) => weekOffset + i);
    final endCycle = weekOffset + s.episodes;
    if (endCycle > maxCycles) maxCycles = endCycle;

    final group = s.time.isEmpty
        ? groupIndexOf['untimed_$idx']!
        : groupIndexOf['timed_$idx']!;

    items.add(CourseItem(
      id: 'anime_${s.title}_${group}_$now',
      dayOfCycle: dayOfCycle,
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

  // config：左侧用「自定义标签」模型（leftLabelMode=2 + slotLabels），
  // 每个 slot 标签就是该剧的开始时间标识（HH:mm / HH:mm (N)），
  // 不走时间段模型（mode=1 需要 slotStartTimes+duration 拼开始/结束）
  final config = TimetableConfig(
    startDateIso: startDateIso,
    cycleCount: maxCycles,
    daysPerCycle: 7,
    slotsPerDay: slotCount,
    isSchoolMode: false,
    isAnimeMode: true,
    leftLabelMode: 2,
    slotLabels: slotLabels,
  );

  // DSL 文本（config 段 + 课程行 w 范围）
  final buffer = StringBuffer();
  buffer.writeln(
    'config: days=7 slots=$slotCount cycles=$maxCycles '
    'start=$startDateIso mode=anime left=2',
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
