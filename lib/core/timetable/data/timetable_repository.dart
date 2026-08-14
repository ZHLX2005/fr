import '../domain/models.dart';
import '../service/config/anime_dsl_generator.dart';

/// 课表空间元信息（多空间列表条目）
class TimetableSpaceInfo {
  const TimetableSpaceInfo({required this.id, required this.name});

  final String id;
  final String name;

  bool get isDefault => id == TimetableRepository.defaultSpaceId;
}

/// 时间周期仓储接口
abstract class TimetableRepository {
  /// 默认空间 id —— 永远映射旧 box（timetable_config / timetable_items），
  /// 保证既有数据零迁移兼容。
  static const String defaultSpaceId = 'default';

  /// 加载配置（当前激活空间）
  Future<TimetableConfig> loadConfig();

  /// 保存配置（当前激活空间）
  Future<void> saveConfig(TimetableConfig config);

  /// 加载所有课程项目（当前激活空间，按 cellKey 分组）
  Future<Map<String, List<CourseItem>>> loadItems();

  /// 保存所有课程项目（当前激活空间，展平后存储）
  Future<void> saveItems(List<CourseItem> items);

  /// 保存指定 cellKey 的课程列表（当前激活空间）
  Future<void> upsertItems(String cellKey, List<CourseItem> items);

  /// 删除指定 cellKey 的所有课程（当前激活空间）
  Future<void> deleteItem(String cellKey);

  /// 清空所有课程（当前激活空间）
  Future<void> clearItems();

  /// 加载追剧剧模型列表（当前激活空间；空列表 = 无剧）
  Future<List<AnimeSeriesDraft>> loadAnimeSeries();

  /// 保存追剧剧模型列表（当前激活空间，整体覆盖写）
  Future<void> saveAnimeSeries(List<AnimeSeriesDraft> series);

  /// 当前激活空间 id（default = 旧 box）
  String get activeSpaceId;

  /// 列出全部空间（含 default；default 恒在首位）
  Future<List<TimetableSpaceInfo>> listSpaces();

  /// 切换激活空间（default 恒合法）
  Future<void> setActiveSpace(String spaceId);

  /// 新建空间（返回新空间 id；config/items 从默认值开始）
  Future<String> createSpace(String name);

  /// 重命名空间
  Future<void> renameSpace(String spaceId, String name);

  /// 删除空间（default 不可删；删除激活空间时自动回退 default）
  Future<void> deleteSpace(String spaceId);
}
