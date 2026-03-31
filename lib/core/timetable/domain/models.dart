/// 课表系统 - Domain Models
/// 配置驱动的多层级课表系统

/// 周期配置模型
class TimetableConfig {
  const TimetableConfig({
    required this.startDateIso,
    required this.cycleCount,
    required this.daysPerCycle,
    required this.slotsPerDay,
    this.id = 'default',
    this.updatedAt,
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

  TimetableConfig copyWith({
    String? startDateIso,
    int? cycleCount,
    int? daysPerCycle,
    int? slotsPerDay,
    String? id,
    int? updatedAt,
  }) {
    return TimetableConfig(
      startDateIso: startDateIso ?? this.startDateIso,
      cycleCount: cycleCount ?? this.cycleCount,
      daysPerCycle: daysPerCycle ?? this.daysPerCycle,
      slotsPerDay: slotsPerDay ?? this.slotsPerDay,
      id: id ?? this.id,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 总天数
  int get totalDays => cycleCount * daysPerCycle;

  /// 默认配置
  static const TimetableConfig defaultConfig = TimetableConfig(
    startDateIso: '2025-01-01',
    cycleCount: 4,
    daysPerCycle: 7,
    slotsPerDay: 6,
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
class CourseItem {
  const CourseItem({
    required this.id,
    required this.dayIndex,
    required this.slotIndex,
    required this.title,
    this.location,
    this.teacher,
    this.colorSeed,
    this.version = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  /// 全局天数索引 (0 起)
  final int dayIndex;
  /// 节次索引 (0 起)
  final int slotIndex;
  final String title;
  final String? location;
  final String? teacher;
  final int? colorSeed;
  final int version;
  final int createdAt;
  final int updatedAt;

  CourseItem copyWith({
    String? id,
    int? dayIndex,
    int? slotIndex,
    String? title,
    String? location,
    String? teacher,
    int? colorSeed,
    int? version,
    int? createdAt,
    int? updatedAt,
  }) {
    return CourseItem(
      id: id ?? this.id,
      dayIndex: dayIndex ?? this.dayIndex,
      slotIndex: slotIndex ?? this.slotIndex,
      title: title ?? this.title,
      location: location ?? this.location,
      teacher: teacher ?? this.teacher,
      colorSeed: colorSeed ?? this.colorSeed,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 生成 cellKey
  String get cellKey => 'd${dayIndex}_s$slotIndex';
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
}
