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

/// 课表配置模型
class TimetableConfig {
  const TimetableConfig({
    required this.rows,
    required this.cols,
    this.id = 'default',
  });

  final String id;
  final int rows;
  final int cols;

  TimetableConfig copyWith({int? rows, int? cols}) {
    return TimetableConfig(
      id: id,
      rows: rows ?? this.rows,
      cols: cols ?? this.cols,
    );
  }

  static const TimetableConfig defaultConfig = TimetableConfig(
    id: 'default',
    rows: 12,
    cols: 7,
  );
}

/// 课程模型
class Course {
  const Course({
    required this.id,
    required this.cellKey,
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
  final String cellKey; // 格式: "c{col}_r{row}" 例如 "c3_r5"
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
    String? cellKey,
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
      cellKey: cellKey ?? this.cellKey,
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

  /// 从 cellKey 解析列索引
  int get col {
    final match = RegExp(r'c(\d+)').firstMatch(cellKey);
    return match != null ? int.parse(match.group(1)!) : 0;
  }

  /// 从 cellKey 解析行索引
  int get row {
    final match = RegExp(r'r(\d+)').firstMatch(cellKey);
    return match != null ? int.parse(match.group(1)!) : 0;
  }
}

/// 课程草稿（用于编辑）
class CourseDraft {
  CourseDraft({
    required this.cellKey,
    this.title = '',
    this.weekStart = 1,
    this.weekEnd = 16,
    this.location,
    this.teacher,
    this.colorSeed,
    this.oddEven = WeekOddEven.all,
  });

  final String cellKey;
  String title;
  int weekStart;
  int weekEnd;
  String? location;
  String? teacher;
  int? colorSeed;
  WeekOddEven oddEven;

  /// 从现有课程创建草稿
  factory CourseDraft.fromCourse(Course course) {
    return CourseDraft(
      cellKey: course.cellKey,
      title: course.title,
      weekStart: course.weekStart,
      weekEnd: course.weekEnd,
      location: course.location,
      teacher: course.teacher,
      colorSeed: course.colorSeed,
      oddEven: course.oddEven,
    );
  }

  /// 创建空草稿
  factory CourseDraft.empty(String cellKey) {
    return CourseDraft(cellKey: cellKey);
  }

  bool get isValid =>
      title.trim().isNotEmpty &&
      weekStart >= 1 &&
      weekEnd >= weekStart;
}

/// 错误类型
sealed class AppError {
  const AppError();
}

class ValidationError extends AppError {
  const ValidationError(this.message);
  final String message;
}

class StorageError extends AppError {
  const StorageError(this.message);
  final String message;
}

/// 结果包装
class Result<T> {
  Result.ok(this.value) : error = null;
  Result.err(this.error) : value = null;

  final T? value;
  final AppError? error;
  bool get isOk => error == null;
}
