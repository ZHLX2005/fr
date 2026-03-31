import '../domain/models.dart';

/// 课表仓储接口
abstract class TimetableRepository {
  /// 加载配置
  Future<TimetableConfig> loadConfig();

  /// 保存配置
  Future<void> saveConfig(TimetableConfig config);

  /// 加载所有课程项目
  Future<List<CourseItem>> loadItems();

  /// 保存所有课程项目
  Future<void> saveItems(List<CourseItem> items);

  /// 新增或更新单个项目
  Future<void> upsertItem(CourseItem item);

  /// 删除单个项目
  Future<void> deleteItem(String cellKey);
}
