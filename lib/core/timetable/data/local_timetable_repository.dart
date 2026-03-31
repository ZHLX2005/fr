import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models.dart';
import 'timetable_repository.dart';

/// 基于 SharedPreferences 的课表仓储实现
class LocalTimetableRepository implements TimetableRepository {
  static const String _configKey = 'timetable_config';
  static const String _coursesKey = 'timetable_courses';

  @override
  Future<TimetableConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_configKey);
    if (json != null) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        return TimetableConfig(
          id: map['id'] as String? ?? 'default',
          rows: map['rows'] as int? ?? 12,
          cols: map['cols'] as int? ?? 7,
        );
      } catch (e) {
        return TimetableConfig.defaultConfig;
      }
    }
    return TimetableConfig.defaultConfig;
  }

  @override
  Future<void> saveConfig(TimetableConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode({
      'id': config.id,
      'rows': config.rows,
      'cols': config.cols,
    });
    await prefs.setString(_configKey, json);
  }

  @override
  Future<List<Course>> listCourses() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_coursesKey);
    if (json == null) return [];

    try {
      final list = jsonDecode(json) as List;
      return list.map((e) => _courseFromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<Course?> getCourseByCell(String cellKey) async {
    final courses = await listCourses();
    try {
      return courses.firstWhere((c) => c.cellKey == cellKey);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> upsertCourse(Course course) async {
    final courses = await listCourses();
    final index = courses.indexWhere((c) => c.cellKey == course.cellKey);

    if (index >= 0) {
      courses[index] = course;
    } else {
      courses.add(course);
    }

    await _saveCourses(courses);
  }

  @override
  Future<void> deleteCourseByCell(String cellKey) async {
    final courses = await listCourses();
    courses.removeWhere((c) => c.cellKey == cellKey);
    await _saveCourses(courses);
  }

  @override
  Future<int> deleteOutOfBoundsCourses({required int rows, required int cols}) async {
    final courses = await listCourses();
    final initialLength = courses.length;

    courses.removeWhere((course) {
      final col = course.col;
      final row = course.row;
      return col >= cols || row >= rows;
    });

    await _saveCourses(courses);
    return initialLength - courses.length;
  }

  Future<void> _saveCourses(List<Course> courses) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(courses.map((c) => _courseToJson(c)).toList());
    await prefs.setString(_coursesKey, json);
  }

  Map<String, dynamic> _courseToJson(Course course) {
    return {
      'id': course.id,
      'cellKey': course.cellKey,
      'title': course.title,
      'weekStart': course.weekStart,
      'weekEnd': course.weekEnd,
      'colorSeed': course.colorSeed,
      'location': course.location,
      'teacher': course.teacher,
      'oddEven': course.oddEven.value,
      'version': course.version,
      'createdAt': course.createdAt,
      'updatedAt': course.updatedAt,
    };
  }

  Course _courseFromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as String,
      cellKey: json['cellKey'] as String,
      title: json['title'] as String,
      weekStart: json['weekStart'] as int,
      weekEnd: json['weekEnd'] as int,
      colorSeed: json['colorSeed'] as int,
      location: json['location'] as String?,
      teacher: json['teacher'] as String?,
      oddEven: WeekOddEven.fromValue(json['oddEven'] as int? ?? 0),
      version: json['version'] as int? ?? 1,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
    );
  }
}
