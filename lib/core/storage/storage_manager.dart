import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 统一存储管理器
///
/// 管理所有持久化存储：Hive Box、SharedPreferences、文件等
class StorageManager {
  StorageManager._();
  static final StorageManager instance = StorageManager._();

  bool _isInitialized = false;

  /// 初始化所有存储
  Future<void> init() async {
    if (_isInitialized) return;

    // 初始化 Hive
    await Hive.initFlutter();

    _isInitialized = true;
  }

  /// 获取所有存储信息
  Future<List<StorageInfo>> getAllStorageInfo() async {
    final List<StorageInfo> result = [];

    // Hive boxes
    result.addAll(_getHiveBoxesInfo());

    // SharedPreferences
    result.add(await _getPrefsInfo());

    return result;
  }

  /// 获取特定存储类型的所有键
  Future<List<String>> getKeys(StorageType type, {String? boxName}) async {
    switch (type) {
      case StorageType.hive:
        if (boxName == null) return [];
        final box = Hive.box(boxName);
        return box.keys.map((k) => k.toString()).toList();

      case StorageType.prefs:
        final prefs = await SharedPreferences.getInstance();
        return prefs.getKeys().toList();
    }
  }

  /// 获取值
  Future<dynamic> getValue(StorageType type, String key, {String? boxName}) async {
    switch (type) {
      case StorageType.hive:
        if (boxName == null) return null;
        final box = Hive.box(boxName);
        return box.get(key);

      case StorageType.prefs:
        final prefs = await SharedPreferences.getInstance();
        return prefs.get(key);
    }
  }

  /// 删除单个值
  Future<bool> delete(StorageType type, String key, {String? boxName}) async {
    try {
      switch (type) {
        case StorageType.hive:
          if (boxName == null) return false;
          final box = Hive.box(boxName);
          await box.delete(key);
          return true;

        case StorageType.prefs:
          final prefs = await SharedPreferences.getInstance();
          return await prefs.remove(key);
      }
    } catch (e) {
      return false;
    }
  }

  /// 批量删除
  Future<int> deleteMany(StorageType type, List<String> keys, {String? boxName}) async {
    int deleted = 0;
    for (final key in keys) {
      if (await delete(type, key, boxName: boxName)) {
        deleted++;
      }
    }
    return deleted;
  }

  /// 清空指定存储
  Future<bool> clear(StorageType type, {String? boxName}) async {
    try {
      switch (type) {
        case StorageType.hive:
          if (boxName == null) return false;
          final box = Hive.box(boxName);
          await box.clear();
          return true;

        case StorageType.prefs:
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();
          return true;
      }
    } catch (e) {
      return false;
    }
  }

  /// 删除整个 Hive Box
  Future<bool> deleteBox(String boxName) async {
    try {
      await Hive.deleteBoxFromDisk(boxName);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取 Hive Box 信息
  List<StorageInfo> _getHiveBoxesInfo() {
    final List<StorageInfo> result = [];
    final boxNames = [
      'timetable_config',
      'timetable_items',
      'focus_sessions',
      'focus_subjects',
      'clock_records',
      'notes',
    ];

    for (final name in boxNames) {
      try {
        if (Hive.isBoxOpen(name)) {
          final box = Hive.box(name);
          result.add(StorageInfo(
            type: StorageType.hive,
            name: name,
            keyCount: box.length,
            size: _estimateBoxSize(box),
          ));
        }
      } catch (e) {
        // Box 可能不存在
      }
    }

    return result;
  }

  /// 获取 SharedPreferences 信息
  Future<StorageInfo> _getPrefsInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    int totalSize = 0;
    for (final key in keys) {
      final value = prefs.get(key);
      if (value != null) {
        totalSize += value.toString().length;
      }
    }

    return StorageInfo(
      type: StorageType.prefs,
      name: 'SharedPreferences',
      keyCount: keys.length,
      size: totalSize,
    );
  }

  /// 估算 Box 大小
  int _estimateBoxSize(Box box) {
    int size = 0;
    for (final key in box.keys) {
      final value = box.get(key);
      if (value != null) {
        size += key.toString().length + value.toString().length;
      }
    }
    return size;
  }
}

/// 存储类型
enum StorageType {
  hive,
  prefs,
}

/// 存储信息
class StorageInfo {
  const StorageInfo({
    required this.type,
    required this.name,
    required this.keyCount,
    required this.size,
  });

  final StorageType type;
  final String name;
  final int keyCount;
  final int size;

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get typeLabel {
    switch (type) {
      case StorageType.hive:
        return 'Hive';
      case StorageType.prefs:
        return 'Prefs';
    }
  }

  String get displayName {
    // 中文显示名称
    const nameMap = {
      'timetable_config': '课表配置',
      'timetable_items': '课表课程',
      'focus_sessions': '专注记录',
      'focus_subjects': '专注科目',
      'clock_records': '时钟记录',
      'notes': '笔记',
      'SharedPreferences': '应用配置',
    };
    return nameMap[name] ?? name;
  }
}
