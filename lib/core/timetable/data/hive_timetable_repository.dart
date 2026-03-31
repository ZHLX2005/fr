import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models.dart';
import 'timetable_repository.dart';

/// Hive 仓储实现
class HiveTimetableRepository extends TimetableRepository {
  static const String _configBoxName = 'timetable_config';
  static const String _itemsBoxName = 'timetable_items';

  late Box _configBox;
  late Box _itemsBox;

  /// 初始化 Hive
  Future<void> init() async {
    await Hive.initFlutter();
    _configBox = await Hive.openBox(_configBoxName);
    _itemsBox = await Hive.openBox(_itemsBoxName);
  }

  @override
  Future<TimetableConfig> loadConfig() async {
    final json = _configBox.get('config');
    if (json == null) return TimetableConfig.defaultConfig;

    final map = json as Map<String, dynamic>;
    return TimetableConfig(
      startDateIso: map['startDateIso'] as String? ?? TimetableConfig.defaultConfig.startDateIso,
      cycleCount: map['cycleCount'] as int? ?? TimetableConfig.defaultConfig.cycleCount,
      daysPerCycle: map['daysPerCycle'] as int? ?? TimetableConfig.defaultConfig.daysPerCycle,
      slotsPerDay: map['slotsPerDay'] as int? ?? TimetableConfig.defaultConfig.slotsPerDay,
      id: map['id'] as String? ?? 'default',
      updatedAt: map['updatedAt'] as int?,
    );
  }

  @override
  Future<void> saveConfig(TimetableConfig config) async {
    await _configBox.put('config', {
      'startDateIso': config.startDateIso,
      'cycleCount': config.cycleCount,
      'daysPerCycle': config.daysPerCycle,
      'slotsPerDay': config.slotsPerDay,
      'id': config.id,
      'updatedAt': config.updatedAt,
    });
  }

  @override
  Future<List<CourseItem>> loadItems() async {
    final items = <CourseItem>[];
    for (final key in _itemsBox.keys) {
      final json = _itemsBox.get(key);
      if (json != null && json is Map) {
        items.add(_courseItemFromJson(json as Map<String, dynamic>));
      }
    }
    return items;
  }

  @override
  Future<void> saveItems(List<CourseItem> items) async {
    await _itemsBox.clear();
    for (final item in items) {
      await _itemsBox.put(item.cellKey, _courseItemToJson(item));
    }
  }

  @override
  Future<void> upsertItem(CourseItem item) async {
    await _itemsBox.put(item.cellKey, _courseItemToJson(item));
  }

  @override
  Future<void> deleteItem(String cellKey) async {
    await _itemsBox.delete(cellKey);
  }

  Map<String, dynamic> _courseItemToJson(CourseItem item) {
    return {
      'id': item.id,
      'dayIndex': item.dayIndex,
      'slotIndex': item.slotIndex,
      'title': item.title,
      'location': item.location,
      'teacher': item.teacher,
      'colorSeed': item.colorSeed,
      'version': item.version,
      'createdAt': item.createdAt,
      'updatedAt': item.updatedAt,
    };
  }

  CourseItem _courseItemFromJson(Map<String, dynamic> json) {
    return CourseItem(
      id: json['id'] as String,
      dayIndex: json['dayIndex'] as int,
      slotIndex: json['slotIndex'] as int,
      title: json['title'] as String,
      location: json['location'] as String?,
      teacher: json['teacher'] as String?,
      colorSeed: json['colorSeed'] as int?,
      version: json['version'] as int? ?? 1,
      createdAt: json['createdAt'] as int,
      updatedAt: json['updatedAt'] as int,
    );
  }

  /// 关闭并释放资源
  Future<void> close() async {
    await _configBox.close();
    await _itemsBox.close();
  }

  /// 清空所有数据（用于测试）
  Future<void> clear() async {
    await _configBox.clear();
    await _itemsBox.clear();
  }
}
