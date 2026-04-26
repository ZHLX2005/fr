import '../domain/models.dart';

/// 时间周期仓储接口
abstract class TimetableRepository {
  /// 加载配置
  Future<TimetableConfig> loadConfig();

  /// 保存配置
  Future<void> saveConfig(TimetableConfig config);

  /// 加载所有课程项目（按 cellKey 分组）
  Future<Map<String, List<CourseItem>>> loadItems();

  /// 保存所有课程项目（展平后存储）
  Future<void> saveItems(List<CourseItem> items);

  /// 保存指定 cellKey 的课程列表
  Future<void> upsertItems(String cellKey, List<CourseItem> items);

  /// 删除指定 cellKey 的所有课程
  Future<void> deleteItem(String cellKey);

  /// 清空所有课程
  Future<void> clearItems();
}
