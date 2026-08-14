import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../timetable/data/timetable_repository.dart';
import '../../timetable/domain/models.dart';
import '../box_descriptor.dart';
import '../storage_registry.dart';
import 'hive_repository.dart';
import 'hive_store.dart';

/// Hive 仓储实现
///
/// 多空间存储设计（保持旧数据兼容）：
/// - `default` 空间 = 旧 box（timetable_config / timetable_items），零迁移
/// - 新空间存 `timetable_spaces` box：key=spaceId → {name, config, items}
/// - 激活空间 id 持久化在 SharedPreferences（key=timetable-active-space）
class HiveTimetableRepository extends TimetableRepository
    implements HiveRepository {
  static const String _configBoxName = 'timetable_config';
  static const String _itemsBoxName = 'timetable_items';
  static const String _spacesBoxName = 'timetable_spaces';
  static const String _activeSpaceKey = 'timetable-active-space';

  @override
  String get boxName => _configBoxName;

  late Box _configBox;
  late Box _itemsBox;
  late Box _spacesBox;

  String _activeSpaceId = TimetableRepository.defaultSpaceId;

  bool _isInitialized = false;

  /// 初始化 Hive
  Future<void> init() async {
    try {
      _configBox = await HiveStore.instance.openUntyped(_configBoxName);
      _itemsBox = await HiveStore.instance.openUntyped(_itemsBoxName);
      _spacesBox = await HiveStore.instance.openUntyped(_spacesBoxName);
      final prefs = await SharedPreferences.getInstance();
      _activeSpaceId =
          prefs.getString(_activeSpaceKey) ??
          TimetableRepository.defaultSpaceId;
      if (!_spaceExists(_activeSpaceId)) {
        _activeSpaceId = TimetableRepository.defaultSpaceId;
        await prefs.setString(_activeSpaceKey, _activeSpaceId);
      }
      _registerToStorageRegistry();
      _isInitialized = true;
      debugPrint('HiveTimetableRepository: 初始化成功 (空间: $_activeSpaceId)');
      debugPrint(
        'HiveTimetableRepository: _itemsBox.length = ${_itemsBox.length}',
      );
    } catch (e, st) {
      debugPrint('HiveTimetableRepository: 初始化失败 $e\n$st');
      rethrow;
    }
  }

  /// 把 box 注册到 StorageRegistry，存储分析面板自动接管展示/清空。
  void _registerToStorageRegistry() {
    if (!StorageRegistry.has(_configBoxName)) {
      StorageRegistry.register(BoxDescriptor(
        name: _configBoxName,
        displayName: '课表配置',
        openUntyped: () => HiveStore.instance.openUntyped(_configBoxName),
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
        openUntyped: () => HiveStore.instance.openUntyped(_itemsBoxName),
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
    if (!StorageRegistry.has(_spacesBoxName)) {
      StorageRegistry.register(BoxDescriptor(
        name: _spacesBoxName,
        displayName: '课表空间',
        openUntyped: () => HiveStore.instance.openUntyped(_spacesBoxName),
        formatValue: (v) {
          if (v is! Map) return v.toString();
          final name = v['name']?.toString() ?? '未命名';
          final items = v['items'];
          final count = items is Map ? items.length : 0;
          return '$name · $count 个时段';
        },
      ));
    }
  }

  /// 检查是否已初始化
  bool get isInitialized => _isInitialized;

  // ---------- 空间管理 ----------

  @override
  String get activeSpaceId => _activeSpaceId;

  bool get _isDefaultActive =>
      _activeSpaceId == TimetableRepository.defaultSpaceId;

  bool _spaceExists(String spaceId) {
    if (spaceId == TimetableRepository.defaultSpaceId) return true;
    return _spacesBox.containsKey(spaceId);
  }

  @override
  Future<List<TimetableSpaceInfo>> listSpaces() async {
    final spaces = <TimetableSpaceInfo>[
      const TimetableSpaceInfo(
        id: TimetableRepository.defaultSpaceId,
        name: '默认课表',
      ),
    ];
    for (final key in _spacesBox.keys) {
      final json = _spacesBox.get(key);
      if (json is Map) {
        spaces.add(TimetableSpaceInfo(
          id: key.toString(),
          name: json['name']?.toString() ?? key.toString(),
        ));
      }
    }
    return spaces;
  }

  @override
  Future<void> setActiveSpace(String spaceId) async {
    if (!_spaceExists(spaceId)) return;
    _activeSpaceId = spaceId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeSpaceKey, spaceId);
    debugPrint('HiveTimetableRepository: 切换空间 -> $spaceId');
  }

  @override
  Future<String> createSpace(String name) async {
    final spaceId = 'space_${DateTime.now().millisecondsSinceEpoch}';
    await _spacesBox.put(spaceId, {
      'name': name,
      'config': _configToJson(TimetableConfig.defaultConfig),
      'items': <String, dynamic>{},
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
    debugPrint('HiveTimetableRepository: 创建空间 $spaceId ($name)');
    return spaceId;
  }

  @override
  Future<void> renameSpace(String spaceId, String name) async {
    if (!_spaceExists(spaceId)) return;
    final json = _spacesBox.get(spaceId);
    if (json is Map) {
      await _spacesBox.put(spaceId, {...json, 'name': name});
    }
  }

  @override
  Future<void> deleteSpace(String spaceId) async {
    if (spaceId == TimetableRepository.defaultSpaceId) return;
    if (!_spacesBox.containsKey(spaceId)) return;
    await _spacesBox.delete(spaceId);
    if (_activeSpaceId == spaceId) {
      await setActiveSpace(TimetableRepository.defaultSpaceId);
    }
    debugPrint('HiveTimetableRepository: 删除空间 $spaceId');
  }

  // ---------- 数据读写（按激活空间路由） ----------

  Map<String, dynamic>? _spaceRecord(String spaceId) {
    final json = _spacesBox.get(spaceId);
    return json is Map ? json.map((k, v) => MapEntry(k.toString(), v)) : null;
  }

  Future<void> _writeSpaceRecord(String spaceId, Map<String, dynamic> record) async {
    await _spacesBox.put(spaceId, record);
  }

  @override
  Future<TimetableConfig> loadConfig() async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.loadConfig: 未初始化');
      return TimetableConfig.defaultConfig;
    }
    if (_isDefaultActive) {
      final json = _configBox.get('config');
      if (json == null) return TimetableConfig.defaultConfig;
      // Hive returns _Map<dynamic, dynamic>, must convert keys to String
      final map = (json as Map).map((k, v) => MapEntry(k.toString(), v));
      return _configFromJson(map);
    }
    final record = _spaceRecord(_activeSpaceId);
    final configJson = record?['config'];
    if (configJson is Map) {
      return _configFromJson(
        configJson.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return TimetableConfig.defaultConfig;
  }

  @override
  Future<void> saveConfig(TimetableConfig config) async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.saveConfig: 未初始化');
      return;
    }
    if (_isDefaultActive) {
      await _configBox.put('config', _configToJson(config));
      debugPrint('HiveTimetableRepository.saveConfig: 配置已保存');
      return;
    }
    final record = _spaceRecord(_activeSpaceId) ?? _emptySpaceRecord();
    await _writeSpaceRecord(
      _activeSpaceId,
      {...record, 'config': _configToJson(config)},
    );
    debugPrint('HiveTimetableRepository.saveConfig: 配置已保存 (空间 $_activeSpaceId)');
  }

  @override
  Future<Map<String, List<CourseItem>>> loadItems() async {
    if (!_isInitialized) {
      return {};
    }
    final result = <String, List<CourseItem>>{};
    if (_isDefaultActive) {
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
    final record = _spaceRecord(_activeSpaceId);
    final itemsJson = record?['items'];
    if (itemsJson is Map) {
      for (final entry in itemsJson.entries) {
        final json = entry.value;
        if (json is List) {
          final itemList = <CourseItem>[];
          for (final itemJson in json) {
            if (itemJson is Map) {
              final typedJson = itemJson.map((k, v) => MapEntry(k.toString(), v));
              itemList.add(_courseItemFromJson(typedJson));
            }
          }
          result[entry.key.toString()] = itemList;
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
    final groupedJson = grouped.map(
      (k, v) => MapEntry(k, _courseListToJson(v)),
    );
    if (_isDefaultActive) {
      // 清空并按新格式保存（JSON 数组）
      await _itemsBox.clear();
      for (final entry in groupedJson.entries) {
        await _itemsBox.put(entry.key, entry.value);
      }
      debugPrint('HiveTimetableRepository.saveItems: 保存了 ${items.length} 个课程');
      return;
    }
    final record = _spaceRecord(_activeSpaceId) ?? _emptySpaceRecord();
    await _writeSpaceRecord(
      _activeSpaceId,
      {...record, 'items': groupedJson},
    );
    debugPrint('HiveTimetableRepository.saveItems: 保存了 ${items.length} 个课程 (空间 $_activeSpaceId)');
  }

  @override
  Future<void> upsertItems(String cellKey, List<CourseItem> items) async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.upsertItems: 未初始化');
      return;
    }
    if (_isDefaultActive) {
      await _itemsBox.put(cellKey, _courseListToJson(items));
      debugPrint(
        'HiveTimetableRepository.upsertItems: 保存课程 $cellKey (${items.length}个)，Box长度=${_itemsBox.length}',
      );
      return;
    }
    final record = _spaceRecord(_activeSpaceId) ?? _emptySpaceRecord();
    final itemsJson = record['items'];
    final itemsMap = itemsJson is Map
        ? itemsJson.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    itemsMap[cellKey] = _courseListToJson(items);
    await _writeSpaceRecord(
      _activeSpaceId,
      {...record, 'items': itemsMap},
    );
  }

  @override
  Future<void> clearItems() async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.clearItems: 未初始化');
      return;
    }
    if (_isDefaultActive) {
      await _itemsBox.clear();
      debugPrint('HiveTimetableRepository.clearItems: 已清空所有课程');
      return;
    }
    final record = _spaceRecord(_activeSpaceId) ?? _emptySpaceRecord();
    await _writeSpaceRecord(
      _activeSpaceId,
      {...record, 'items': <String, dynamic>{}},
    );
    debugPrint('HiveTimetableRepository.clearItems: 已清空所有课程 (空间 $_activeSpaceId)');
  }

  @override
  Future<void> deleteItem(String cellKey) async {
    if (!_isInitialized) {
      debugPrint('HiveTimetableRepository.deleteItem: 未初始化');
      return;
    }
    if (_isDefaultActive) {
      await _itemsBox.delete(cellKey);
      debugPrint(
        'HiveTimetableRepository.deleteItem: 删除课程 $cellKey 成功，Box长度=${_itemsBox.length}',
      );
      return;
    }
    final record = _spaceRecord(_activeSpaceId) ?? _emptySpaceRecord();
    final itemsJson = record['items'];
    final itemsMap = itemsJson is Map
        ? itemsJson.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    itemsMap.remove(cellKey);
    await _writeSpaceRecord(
      _activeSpaceId,
      {...record, 'items': itemsMap},
    );
  }

  Map<String, dynamic> _emptySpaceRecord() {
    return {
      'name': _activeSpaceId,
      'config': _configToJson(TimetableConfig.defaultConfig),
      'items': <String, dynamic>{},
    };
  }

  Map<String, dynamic> _configToJson(TimetableConfig config) {
    return {
      'startDateIso': config.startDateIso,
      'cycleCount': config.cycleCount,
      'daysPerCycle': config.daysPerCycle,
      'slotsPerDay': config.slotsPerDay,
      'id': config.id,
      'updatedAt': config.updatedAt,
      'backgroundImagePath': config.backgroundImagePath,
      'isSchoolMode': config.isSchoolMode,
      'isAnimeMode': config.isAnimeMode,
      'leftLabelMode': config.leftLabelMode,
      'slotLabels': config.slotLabels,
      'slotStartTimes': config.slotStartTimes,
      'slotDurationMin': config.slotDurationMin,
      'leftWidth': config.leftWidth,
    };
  }

  TimetableConfig _configFromJson(Map<String, dynamic> map) {
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
      isAnimeMode: map['isAnimeMode'] as bool? ?? false,
      leftLabelMode: map['leftLabelMode'] as int? ?? 0,
      slotLabels: (map['slotLabels'] as List?)?.cast<String>(),
      slotStartTimes: (map['slotStartTimes'] as List?)?.cast<String>(),
      slotDurationMin: map['slotDurationMin'] as int? ?? 45,
      leftWidth: (map['leftWidth'] as num?)?.toDouble() ?? 64,
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
    await _spacesBox.close();
  }

  /// 清空所有数据（用于测试）
  Future<void> clear() async {
    await _configBox.clear();
    await _itemsBox.clear();
    await _spacesBox.clear();
  }
}
