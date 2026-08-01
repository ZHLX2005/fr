import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../storage/box_descriptor.dart';
import '../../storage/storage_registry.dart';
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
      _registerToStorageRegistry();
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

  /// 把两个 box 注册到 StorageRegistry，存储分析面板自动接管展示/清空。
  void _registerToStorageRegistry() {
    if (!StorageRegistry.has(_configBoxName)) {
      StorageRegistry.register(BoxDescriptor(
        name: _configBoxName,
        displayName: '课表配置',
        openUntyped: () => Hive.openBox(_configBoxName),
        formatValue: (v) {
          if (v is! Map) return v.toString();
          final m = v.map((k, e) => MapEntry(k.toString(), e));
          final cycle = m['cycleCount'];
          final days = m['daysPerCycle'];
          final slots = m['slotsPerDay'];
          return '周期: $cycle · 每周期 $days 天 · 每天 $slots 节';
        },
      ));
    }
    if (!StorageRegistry.has(_itemsBoxName)) {
      StorageRegistry.register(BoxDescriptor(
        name: _itemsBoxName,
        displayName: '课表课程',
        openUntyped: () => Hive.openBox(_itemsBoxName),
        formatValue: (v) {
          if (v is List) {
            final titles = v
                .whereType<Map>()
                .map((m) => m['title'])
                .whereType<String>()
                .where((t) => t.isNotEmpty)
                .toList();
            final head = titles.isEmpty ? '（未命名）' : titles.first;
            return '${v.length} 节 · $head${titles.length > 1 ? ' 等' : ''}';
          }
          if (v is Map) {
            return v['title']?.toString() ?? '课程';
          }
          return v.toString();
        },
      ));
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

    // Hive returns _Map<dynamic, dynamic>, must convert keys to String
    final map = (json as Map).map((k, v) => MapEntry(k.toString(), v));
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
  Future<Map<String, List<CourseItem>>> loadItems() async {
    if (!_isInitialized) {
      return {};
    }
    final result = <String, List<CourseItem>>{};
    for (final key in _itemsBox.keys) {
      final json = _itemsBox.get(key);
      if (json != null) {
        // 兼容旧数据格式：单个 Map 为旧格式，List 为新格式
        if (json is Map) {
          // 旧格式迁移：单个课程项
          final typedJson = json.map((k, v) => MapEntry(k.toString(), v));
          final item = _courseItemFromJson(typedJson);
          result[key.toString()] = [item];
        } else if (json is List) {
          // 新格式：课程列表
          final itemList = <CourseItem>[];
          for (final itemJson in json) {
            if (itemJson is Map) {
              final typedJson = itemJson.map((k, v) => MapEntry(k.toString(), v));
              itemList.add(_courseItemFromJson(typedJson));
            }
          }
          result[key.toString()] = itemList;
        }
      }
    }
    return result;
  }

  @override
  Future<void> saveItems(List<CourseItem> items) async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.saveItems: 未初始化');
      return;
    }
    // 按 cellKey 分组
    final grouped = <String, List<CourseItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.cellKey, () => []).add(item);
    }
    // 清空并按新格式保存（JSON 数组）
    await _itemsBox.clear();
    for (final entry in grouped.entries) {
      await _itemsBox.put(entry.key, _courseListToJson(entry.value));
    }
    debugPrint('HiveTimetableRepository.saveItems: 保存了 ${items.length} 个课程');
  }

  @override
  Future<void> upsertItems(String cellKey, List<CourseItem> items) async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.upsertItems: 未初始化');
      return;
    }
    await _itemsBox.put(cellKey, _courseListToJson(items));
    debugPrint(
      'HiveTimetableRepository.upsertItems: 保存课程 $cellKey (${items.length}个)，Box长度=${_itemsBox.length}',
    );
  }

  @override
  Future<void> clearItems() async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.clearItems: 未初始化');
      return;
    }
    await _itemsBox.clear();
    debugPrint('HiveTimetableRepository.clearItems: 已清空所有课程');
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

  List<Map<String, dynamic>> _courseListToJson(List<CourseItem> items) {
    return items.map((item) => _courseItemToJson(item)).toList();
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
