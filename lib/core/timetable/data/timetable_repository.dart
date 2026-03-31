import '../domain/models.dart';

/// 课表仓储接口
abstract class TimetableRepository {
  /// 加载配置
  Future<TimetableConfig> loadConfig();

  /// 保存配置
  Future<void> saveConfig(TimetableConfig config);

  /// 获取所有课程
  Future<List<Course>> listCourses();

  /// 根据格子key获取课程
  Future<Course?> getCourseByCell(String cellKey);

  /// 插入或更新课程
  Future<void> upsertCourse(Course course);

  /// 根据格子key删除课程
  Future<void> deleteCourseByCell(String cellKey);

  /// 删除越界课程（当缩小网格时）
  Future<int> deleteOutOfBoundsCourses({required int rows, required int cols});
}
