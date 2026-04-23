import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models.dart';
import 'timetable_repository.dart';

/// Hive 仓储实现
class HiveTimetableRepository extends TimetableRepository {
  static const String _configBoxName = 'timetable_config';
  static const String _itemsBoxName = 'timetable_items';

  late Box _configBox;
  late Box _itemsBox;

  bool _isInitialized = false;

  /// 初始化 Hive
  Future<void> init() async {
    try {
      await Hive.initFlutter();
      _configBox = await Hive.openBox(_configBoxName);
      _itemsBox = await Hive.openBox(_itemsBoxName);
      _isInitialized = true;
      debugPrint('HiveTimetableRepository: 初始化成功');
      debugPrint(
        'HiveTimetableRepository: _itemsBox.length = ${_itemsBox.length}',
      );
    } catch (e, st) {
      debugPrint('HiveTimetableRepository: 初始化失败 $e\n$st');
      rethrow;
    }
  }

  /// 检查是否已初始化
  bool get isInitialized => _isInitialized;

  @override
  Future<TimetableConfig> loadConfig() async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.loadConfig: 未初始化');
      return TimetableConfig.defaultConfig;
    }
    final json = _configBox.get('config');
    if (json == null) {
      debugPrint('HiveTimetableRepository.loadConfig: 没有保存的配置');
      return TimetableConfig.defaultConfig;
    }

    final map = json as Map<String, dynamic>;
    return TimetableConfig(
      startDateIso:
          map['startDateIso'] as String? ??
          TimetableConfig.defaultConfig.startDateIso,
      cycleCount:
          map['cycleCount'] as int? ?? TimetableConfig.defaultConfig.cycleCount,
      daysPerCycle:
          map['daysPerCycle'] as int? ??
          TimetableConfig.defaultConfig.daysPerCycle,
      slotsPerDay:
          map['slotsPerDay'] as int? ??
          TimetableConfig.defaultConfig.slotsPerDay,
      id: map['id'] as String? ?? 'default',
      updatedAt: map['updatedAt'] as int?,
      backgroundImagePath: map['backgroundImagePath'] as String?,
      isSchoolMode: map['isSchoolMode'] as bool? ?? false,
    );
  }

  @override
  Future<void> saveConfig(TimetableConfig config) async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.saveConfig: 未初始化');
      return;
    }
    await _configBox.put('config', {
      'startDateIso': config.startDateIso,
      'cycleCount': config.cycleCount,
      'daysPerCycle': config.daysPerCycle,
      'slotsPerDay': config.slotsPerDay,
      'id': config.id,
      'updatedAt': config.updatedAt,
      'backgroundImagePath': config.backgroundImagePath,
      'isSchoolMode': config.isSchoolMode,
    });
    debugPrint('HiveTimetableRepository.saveConfig: 配置已保存');
  }

  @override
  Future<List<CourseItem>> loadItems() async {
    if (!_isInitialized) {
      return [];
    }
    final items = <CourseItem>[];
    for (final key in _itemsBox.keys) {
      final json = _itemsBox.get(key);
      if (json != null && json is Map) {
        // Hive returns _Map<dynamic, dynamic>, convert to Map<String, dynamic>
        final typedJson = json.map((k, v) => MapEntry(k.toString(), v));
        items.add(_courseItemFromJson(typedJson));
      }
    }
    return items;
  }

  @override
  Future<void> saveItems(List<CourseItem> items) async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.saveItems: 未初始化');
      return;
    }
    await _itemsBox.clear();
    for (final item in items) {
      await _itemsBox.put(item.cellKey, _courseItemToJson(item));
    }
    debugPrint('HiveTimetableRepository.saveItems: 保存了 ${items.length} 个课程');
  }

  @override
  Future<void> upsertItem(CourseItem item) async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.upsertItem: 未初始化');
      return;
    }
    await _itemsBox.put(item.cellKey, _courseItemToJson(item));
    debugPrint(
      'HiveTimetableRepository.upsertItem: 保存课程 ${item.cellKey} 成功，Box长度=${_itemsBox.length}',
    );
  }

  @override
  Future<void> deleteItem(String cellKey) async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.deleteItem: 未初始化');
      return;
    }
    await _itemsBox.delete(cellKey);
    debugPrint(
      'HiveTimetableRepository.deleteItem: 删除课程 $cellKey 成功，Box长度=${_itemsBox.length}',
    );
  }

  Map<String, dynamic> _courseItemToJson(CourseItem item) {
    return {
      'id': item.id,
      'dayOfCycle': item.dayOfCycle,
      'slotIndex': item.slotIndex,
      'title': item.title,
      'location': item.location,
      'teacher': item.teacher,
      'colorSeed': item.colorSeed,
      'version': item.version,
      'visibleInCycles': item.visibleInCycles,
      'createdAt': item.createdAt,
      'updatedAt': item.updatedAt,
    };
  }

  CourseItem _courseItemFromJson(Map<String, dynamic> json) {
    // 兼容旧数据：如果有 dayIndex 但没有 dayOfCycle，迁移时使用 dayIndex
    final dayOfCycle =
        json['dayOfCycle'] as int? ?? json['dayIndex'] as int? ?? 0;
    // visibleInCycles: 兼容旧数据（没有该字段时为 null）
    final visibleInCyclesRaw = json['visibleInCycles'];
    List<int>? visibleInCycles;
    if (visibleInCyclesRaw != null && visibleInCyclesRaw is List) {
      visibleInCycles = visibleInCyclesRaw.cast<int>();
    }
    return CourseItem(
      id: json['id'] as String,
      dayOfCycle: dayOfCycle,
      slotIndex: json['slotIndex'] as int,
      title: json['title'] as String,
      location: json['location'] as String?,
      teacher: json['teacher'] as String?,
      colorSeed: json['colorSeed'] as int?,
      version: json['version'] as int? ?? 1,
      visibleInCycles: visibleInCycles,
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
