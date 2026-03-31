/// 周期管理 - 基础数据模型
/// 功能待开发，仅保留结构定义

/// 周单双类型枚举
enum WeekOddEven {
  all(0, '全部'),
  odd(1, '单周'),
  even(2, '双周');

  const WeekOddEven(this.value, this.label);
  final int value;
  final String label;

  static WeekOddEven fromValue(int value) {
    return WeekOddEven.values.firstWhere(
      (e) => e.value == value,
      orElse: () => WeekOddEven.all,
    );
  }
}

/// 周期配置模型
class TimetableConfig {
  const TimetableConfig({
    required this.rows,
    required this.cols,
    this.cycleCount = 4,
    this.id = 'default',
  });

  final String id;
  final int rows;      // 节数（行）
  final int cols;      // 天数（列）
  final int cycleCount; // 周期数

  TimetableConfig copyWith({int? rows, int? cols, int? cycleCount}) {
    return TimetableConfig(
      id: id,
      rows: rows ?? this.rows,
      cols: cols ?? this.cols,
      cycleCount: cycleCount ?? this.cycleCount,
    );
  }

  static const TimetableConfig defaultConfig = TimetableConfig(
    id: 'default',
    rows: 5,
    cols: 7,
    cycleCount: 4,
  );

  /// 最大限制
  static const int maxCols = 10;
  static const int maxRows = 5;
  static const int maxCycles = 16;
  static const int minCycles = 1;
}

/// 课程模型 - 待开发
class Course {
  const Course({
    required this.id,
    required this.row,
    required this.col,
    required this.title,
    required this.weekStart,
    required this.weekEnd,
    required this.colorSeed,
    this.location,
    this.teacher,
    this.oddEven = WeekOddEven.all,
    this.version = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final int row;
  final int col;
  final String title;
  final int weekStart;
  final int weekEnd;
  final int colorSeed;
  final String? location;
  final String? teacher;
  final WeekOddEven oddEven;
  final int version;
  final int createdAt;
  final int updatedAt;

  Course copyWith({
    String? id,
    int? row,
    int? col,
    String? title,
    int? weekStart,
    int? weekEnd,
    int? colorSeed,
    String? location,
    String? teacher,
    WeekOddEven? oddEven,
    int? version,
    int? createdAt,
    int? updatedAt,
  }) {
    return Course(
      id: id ?? this.id,
      row: row ?? this.row,
      col: col ?? this.col,
      title: title ?? this.title,
      weekStart: weekStart ?? this.weekStart,
      weekEnd: weekEnd ?? this.weekEnd,
      colorSeed: colorSeed ?? this.colorSeed,
      location: location ?? this.location,
      teacher: teacher ?? this.teacher,
      oddEven: oddEven ?? this.oddEven,
      version: version ?? this.version,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 课程草稿 - 待开发
class CourseDraft {
  CourseDraft({
    required this.row,
    required this.col,
    this.title = '',
    this.weekStart = 1,
    this.weekEnd = 16,
    this.location,
    this.teacher,
    this.colorSeed,
    this.oddEven = WeekOddEven.all,
  });

  final int row;
  final int col;
  String title;
  int weekStart;
  int weekEnd;
  String? location;
  String? teacher;
  int? colorSeed;
  WeekOddEven oddEven;

  bool get isValid =>
      title.trim().isNotEmpty &&
      weekStart >= 1 &&
      weekEnd >= weekStart;
}
