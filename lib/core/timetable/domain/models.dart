// 课表系统 - Domain Models
// 配置驱动的多层级课表系统

/// 周期配置模型
class TimetableConfig {
  const TimetableConfig({
    required this.startDateIso,
    required this.cycleCount,
    required this.daysPerCycle,
    required this.slotsPerDay,
    this.id = 'default',
    this.updatedAt,
    this.backgroundImagePath,
    this.isSchoolMode = false,
    this.isAnimeMode = false,
    this.leftLabelMode = 0,
    this.slotLabels,
    this.slotStartTimes,
    this.slotDurationMin = 45,
    this.leftWidth = 64,
  });

  /// ISO 8601 日期字符串 (YYYY-MM-DD)
  final String startDateIso;

  /// 周期总数
  final int cycleCount;

  /// 每周期天数 (1-7)
  final int daysPerCycle;

  /// 每天节数 (1-6)
  final int slotsPerDay;
  final String id;
  final int? updatedAt;

  /// 背景图路径
  final String? backgroundImagePath;

  /// 学校模式（约束：固定7天，周一起始）
  final bool isSchoolMode;

  /// 追剧/番模式（与学校/通用平级的独立模式；行列周期由追剧 DSL 自动计算）
  final bool isAnimeMode;

  /// 左侧指示模式: 0=节次序号, 1=时间段(需 slotStartTimes), 2=自定义文字(需 slotLabels)
  final int leftLabelMode;

  /// 每节自定义文字 (leftLabelMode=2 时使用，长度可与 slotsPerDay 不同，越界回退序号)
  final List<String>? slotLabels;

  /// 每节开始时间 "HH:mm" (leftLabelMode=1 时使用)
  final List<String>? slotStartTimes;

  /// 每节时长(分钟)，默认 45（leftLabelMode=1 时计算结束时间）
  final int slotDurationMin;

  /// 左侧指示宽度 px，默认 64
  final double leftWidth;

  /// 取指定节次的左侧指示文字（按 leftLabelMode 路由，越界/空值回退节次序号）
  String slotLabel(int slotIndex) {
    switch (leftLabelMode) {
      case 1:
        final start = slotIndex < (slotStartTimes?.length ?? 0)
            ? slotStartTimes![slotIndex]
            : '';
        if (start.isEmpty) return '${slotIndex + 1}';
        final end = TimetableMappers.addMinutes(start, slotDurationMin);
        return '$start\n$end';
      case 2:
        final label = slotIndex < (slotLabels?.length ?? 0)
            ? slotLabels![slotIndex]
            : '';
        return label.isEmpty ? '${slotIndex + 1}' : label;
      default:
        return '${slotIndex + 1}';
    }
  }

  TimetableConfig copyWith({
    String? startDateIso,
    int? cycleCount,
    int? daysPerCycle,
    int? slotsPerDay,
    String? id,
    int? updatedAt,
    String? backgroundImagePath,
    bool clearBackgroundImage = false,
    bool? isSchoolMode,
    bool? isAnimeMode,
    int? leftLabelMode,
    List<String>? slotLabels,
    bool clearSlotLabels = false,
    List<String>? slotStartTimes,
    bool clearSlotStartTimes = false,
    int? slotDurationMin,
    double? leftWidth,
  }) {
    return TimetableConfig(
      startDateIso: startDateIso ?? this.startDateIso,
      cycleCount: cycleCount ?? this.cycleCount,
      daysPerCycle: daysPerCycle ?? this.daysPerCycle,
      slotsPerDay: slotsPerDay ?? this.slotsPerDay,
      id: id ?? this.id,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      backgroundImagePath: clearBackgroundImage
          ? null
          : (backgroundImagePath ?? this.backgroundImagePath),
      isSchoolMode: isSchoolMode ?? this.isSchoolMode,
      isAnimeMode: isAnimeMode ?? this.isAnimeMode,
      leftLabelMode: leftLabelMode ?? this.leftLabelMode,
      slotLabels: clearSlotLabels
          ? null
          : (slotLabels ?? this.slotLabels),
      slotStartTimes: clearSlotStartTimes
          ? null
          : (slotStartTimes ?? this.slotStartTimes),
      slotDurationMin: slotDurationMin ?? this.slotDurationMin,
      leftWidth: leftWidth ?? this.leftWidth,
    );
  }

  /// 总天数
  int get totalDays => cycleCount * daysPerCycle;

  /// 起始日期 DateTime
  DateTime get startDate => DateTime.parse(startDateIso);

  /// 截止日期（最后一天）
  DateTime get endDate => startDate.add(Duration(days: totalDays - 1));

  /// 今天所在周期索引（不在范围内返回 null）
  int? get todayCycleIndex {
    final now = DateTime.now();
    final start = startDate;
    final end = endDate;
    if (now.isBefore(start) || now.isAfter(end)) return null;
    final dayOffset = now.difference(start).inDays; // 0-based
    return dayOffset ~/ daysPerCycle;
  }

  /// 今天是否在课表范围内
  bool get isTodayInRange {
    final now = DateTime.now();
    return !now.isBefore(startDate) && !now.isAfter(endDate);
  }

  /// 默认配置（课表模式：一周7天 / 每天5节 / 20个周期）
  static const TimetableConfig defaultConfig = TimetableConfig(
    startDateIso: '2025-01-01',
    cycleCount: 20,
    daysPerCycle: 7,
    slotsPerDay: 5,
    isSchoolMode: true,
  );

  /// 约束
  static const int maxDaysPerCycle = 7;
  static const int maxSlotsPerDay = 6;
  static const int maxCycles = 32;
  static const int minDaysPerCycle = 1;
  static const int minSlotsPerDay = 1;
  static const int minCycles = 1;
}

/// 课程项目（排课最小单元）
/// 存储 dayOfCycle 表示在周期中的第几天，会在所有周期重复显示
class CourseItem {
  const CourseItem({
    required this.id,
    required this.dayOfCycle,
    required this.slotIndex,
    required this.title,
    this.location,
    this.teacher,
    this.colorSeed,
    this.version = 1,
    this.visibleInCycles,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// 周期中的第几天 (0 起, 0=周期第一天)
  final int dayOfCycle;

  /// 节次索引 (0 起)
  final int slotIndex;
  final String title;
  final String? location;
  final String? teacher;
  final int? colorSeed;
  final int version;

  /// null 表示所有周期都显示
  final List<int>? visibleInCycles;
  final int createdAt;
  final int updatedAt;

  bool isVisibleInCycle(int cycleIndex) {
    if (visibleInCycles == null || visibleInCycles!.isEmpty) return true;
    return visibleInCycles!.contains(cycleIndex);
  }

  CourseItem copyWith({
    String? id,
    int? dayOfCycle,
    int? slotIndex,
    String? title,
    String? location,
    String? teacher,
    int? colorSeed,
    int? version,
    List<int>? visibleInCycles,
    bool clearVisibleInCycles = false,
    int? createdAt,
    int? updatedAt,
  }) {
    return CourseItem(
      id: id ?? this.id,
      dayOfCycle: dayOfCycle ?? this.dayOfCycle,
      slotIndex: slotIndex ?? this.slotIndex,
      title: title ?? this.title,
      location: location ?? this.location,
      teacher: teacher ?? this.teacher,
      colorSeed: colorSeed ?? this.colorSeed,
      version: version ?? this.version,
      visibleInCycles: clearVisibleInCycles
          ? null
          : (visibleInCycles ?? this.visibleInCycles),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 生成 cellKey - 使用 dayOfCycle 存储，这样所有周期共享同一门课程
  String get cellKey => 'd${dayOfCycle}_s$slotIndex';
}

/// 映射函数工具类
class TimetableMappers {
  /// 全局 dayIndex → (cycleIndex, dayOfCycle)
  static (int cycle, int day) dayIndexToCycle(int dayIndex, int daysPerCycle) {
    final cycle = dayIndex ~/ daysPerCycle;
    final day = dayIndex % daysPerCycle;
    return (cycle, day);
  }

  /// (cycleIndex, dayOfCycle) → 全局 dayIndex
  static int cycleToDayIndex(int cycleIndex, int dayOfCycle, int daysPerCycle) {
    return cycleIndex * daysPerCycle + dayOfCycle;
  }

  /// 全局 dayIndex → 周数 (第几周)
  static int dayIndexToWeek(int dayIndex) => (dayIndex / 7).floor() + 1;

  /// 全局 dayIndex → 星期 (0-6, 0=周一)
  static int dayIndexToWeekday(int dayIndex) => dayIndex % 7;

  /// 格式化日期显示
  static String formatDate(String startDateIso, int dayIndex) {
    final date = DateTime.parse(startDateIso).add(Duration(days: dayIndex));
    return '${date.month}/${date.day}';
  }

  /// 获取周期显示标题
  static String getCycleTitle(int cycleIndex, int daysPerCycle) {
    final startWeek = cycleIndex * daysPerCycle ~/ 7 + 1;
    final endWeek = ((cycleIndex + 1) * daysPerCycle - 1) ~/ 7 + 1;
    return '第$startWeek-$endWeek周';
  }

  /// 获取星期几的名称
  static String getWeekdayName(int dayOfCycle) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[dayOfCycle % 7];
  }

  /// "HH:mm" + 分钟 → "HH:mm"（跨小时自动进位，跨天回绕 24h）
  static String addMinutes(String hhmm, int minutes) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return hhmm;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final total = h * 60 + m + minutes;
    final nh = (total ~/ 60) % 24;
    final nm = total % 60;
    return '${nh.toString().padLeft(2, '0')}:${nm.toString().padLeft(2, '0')}';
  }
}
