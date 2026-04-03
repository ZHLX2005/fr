import 'package:hive_flutter/hive_flutter.dart';
import '../domain/models.dart';
import 'hive_timetable_repository.dart';

/// 课表存储管理器
///
/// 提供数据级别的直接查询和删除接口，用于缓存清理
class TimetableStorageManager {
  TimetableStorageManager._();
  static final TimetableStorageManager instance = TimetableStorageManager._();

  static const String _configBoxName = 'timetable_config';
  static const String _itemsBoxName = 'timetable_items';

  Box? _configBox;
  Box? _itemsBox;

  bool _isInitialized = false;

  /// 初始化存储管理器
  Future<void> init() async {
    if (_isInitialized) return;
    _configBox = await Hive.openBox(_configBoxName);
    _itemsBox = await Hive.openBox(_itemsBoxName);
    _isInitialized = true;
  }

  /// 检查是否已初始化
  bool get isInitialized => _isInitialized;

  /// 获取存储统计信息
  Future<StorageStats> getStats() async {
    await _ensureInitialized();

    final configData = _configBox?.get('config');
    final itemCount = _itemsBox?.length ?? 0;

    int configSize = 0;
    if (configData != null) {
      configSize = configData.toString().length;
    }

    int itemsSize = 0;
    if (_itemsBox != null) {
      for (final key in _itemsBox!.keys) {
        final value = _itemsBox!.get(key);
        if (value != null) {
          itemsSize += value.toString().length;
        }
      }
    }

    return StorageStats(
      configCount: configData != null ? 1 : 0,
      configSize: configSize,
      itemCount: itemCount,
      itemsSize: itemsSize,
      totalSize: configSize + itemsSize,
    );
  }

  /// 查询所有配置数据
  Future<Map<String, dynamic>> queryConfig() async {
    await _ensureInitialized();
    final config = _configBox?.get('config');
    if (config == null) return {};
    if (config is Map) {
      return config.map((k, v) => MapEntry(k.toString(), v));
    }
    return {'raw': config};
  }

  /// 查询所有课程项
  Future<List<StorageItemInfo>> queryAllItems() async {
    await _ensureInitialized();
    final items = <StorageItemInfo>[];

    if (_itemsBox == null) return items;

    for (final key in _itemsBox!.keys) {
      final value = _itemsBox!.get(key);
      if (value != null && value is Map) {
        final typedJson = value.map((k, v) => MapEntry(k.toString(), v));
        items.add(StorageItemInfo(
          cellKey: key.toString(),
          title: typedJson['title'] as String? ?? '未知',
          dayOfCycle: typedJson['dayOfCycle'] as int? ?? 0,
          slotIndex: typedJson['slotIndex'] as int? ?? 0,
          size: value.toString().length,
        ));
      }
    }

    // 按 dayOfCycle 和 slotIndex 排序
    items.sort((a, b) {
      final dayCompare = a.dayOfCycle.compareTo(b.dayOfCycle);
      if (dayCompare != 0) return dayCompare;
      return a.slotIndex.compareTo(b.slotIndex);
    });

    return items;
  }

  /// 按日期范围查询课程
  Future<List<StorageItemInfo>> queryItemsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final allItems = await queryAllItems();
    // 这里需要根据配置计算日期，暂时返回所有
    return allItems;
  }

  /// 删除单个课程项
  Future<bool> deleteItem(String cellKey) async {
    await _ensureInitialized();
    if (_itemsBox == null) return false;

    try {
      await _itemsBox!.delete(cellKey);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 批量删除课程项
  Future<int> deleteItems(List<String> cellKeys) async {
    await _ensureInitialized();
    if (_itemsBox == null) return 0;

    int deleted = 0;
    for (final key in cellKeys) {
      try {
        await _itemsBox!.delete(key);
        deleted++;
      } catch (e) {
        // 忽略单个删除失败
      }
    }
    return deleted;
  }

  /// 删除指定天的所有课程
  Future<int> deleteItemsByDay(int dayOfCycle) async {
    await _ensureInitialized();
    if (_itemsBox == null) return 0;

    final keysToDelete = <String>[];
    for (final key in _itemsBox!.keys) {
      final value = _itemsBox!.get(key);
      if (value != null && value is Map) {
        final dayIndex = value['dayOfCycle'] ?? value['dayIndex'];
        if (dayIndex == dayOfCycle) {
          keysToDelete.add(key.toString());
        }
      }
    }

    int deleted = 0;
    for (final key in keysToDelete) {
      await _itemsBox!.delete(key);
      deleted++;
    }
    return deleted;
  }

  /// 清空所有课程项
  Future<int> clearAllItems() async {
    await _ensureInitialized();
    if (_itemsBox == null) return 0;

    final count = _itemsBox!.length;
    await _itemsBox!.clear();
    return count;
  }

  /// 清空配置
  Future<bool> clearConfig() async {
    await _ensureInitialized();
    if (_configBox == null) return false;

    try {
      await _configBox!.clear();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 清空所有数据
  Future<void> clearAll() async {
    await _ensureInitialized();
    await _configBox?.clear();
    await _itemsBox?.clear();
  }

  /// 关闭存储
  Future<void> close() async {
    await _configBox?.close();
    await _itemsBox?.close();
    _isInitialized = false;
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await init();
    }
  }
}

/// 存储统计信息
class StorageStats {
  const StorageStats({
    required this.configCount,
    required this.configSize,
    required this.itemCount,
    required this.itemsSize,
    required this.totalSize,
  });

  final int configCount;
  final int configSize;
  final int itemCount;
  final int itemsSize;
  final int totalSize;

  String get formattedTotalSize {
    if (totalSize < 1024) return '$totalSize B';
    if (totalSize < 1024 * 1024) {
      return '${(totalSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedConfigSize {
    if (configSize < 1024) return '$configSize B';
    if (configSize < 1024 * 1024) {
      return '${(configSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(configSize / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedItemsSize {
    if (itemsSize < 1024) return '$itemsSize B';
    if (itemsSize < 1024 * 1024) {
      return '${(itemsSize / 1024).toStringAsFixed(1)} KB';
    }
    return '${(itemsSize / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

/// 存储项信息
class StorageItemInfo {
  const StorageItemInfo({
    required this.cellKey,
    required this.title,
    required this.dayOfCycle,
    required this.slotIndex,
    required this.size,
  });

  final String cellKey;
  final String title;
  final int dayOfCycle;
  final int slotIndex;
  final int size;

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
