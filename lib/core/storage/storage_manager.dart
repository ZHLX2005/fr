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

    // Hive 作为一个整体
    result.add(await _getHiveInfo());

    // SharedPreferences 作为一个整体
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

  /// 获取键值对详情列表
  Future<List<KeyDetail>> getKeyDetails(StorageType type, {String? boxName}) async {
    final List<KeyDetail> result = [];

    switch (type) {
      case StorageType.hive:
        if (boxName != null) {
          // 获取指定 Box 的键
          final box = Hive.box(boxName);
          for (final key in box.keys) {
            final value = box.get(key);
            result.add(KeyDetail(
              key: '$boxName/$key',
              value: _formatValue(value),
              rawValue: value,
              size: _estimateSize(value),
            ));
          }
        } else {
          // 获取所有 Hive Box 的所有键
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
                for (final key in box.keys) {
                  final value = box.get(key);
                  result.add(KeyDetail(
                    key: '$name/$key',
                    value: _formatValue(value),
                    rawValue: value,
                    size: _estimateSize(value),
                  ));
                }
              }
            } catch (e) {
              // Box 可能不存在
            }
          }
        }
        break;

      case StorageType.prefs:
        final prefs = await SharedPreferences.getInstance();
        for (final key in prefs.getKeys()) {
          final value = prefs.get(key);
          result.add(KeyDetail(
            key: key,
            value: _formatValue(value),
            rawValue: value,
            size: _estimateSize(value),
          ));
        }
        break;
    }

    // 按大小排序
    result.sort((a, b) => b.size.compareTo(a.size));
    return result;
  }

  /// 获取单个值的详细信息
  Future<KeyDetail?> getKeyDetail(StorageType type, String key, {String? boxName}) async {
    dynamic value;
    try {
      switch (type) {
        case StorageType.hive:
          String actualBoxName = boxName ?? '';
          String actualKey = key;

          if (boxName == null && key.contains('/')) {
            final parts = key.split('/');
            actualBoxName = parts[0];
            actualKey = parts.sublist(1).join('/');
          }

          if (actualBoxName.isEmpty) return null;
          if (!Hive.isBoxOpen(actualBoxName)) return null;

          final box = Hive.box(actualBoxName);
          value = box.get(actualKey);
          break;

        case StorageType.prefs:
          final prefs = await SharedPreferences.getInstance();
          value = prefs.get(key);
          break;
      }
    } catch (e) {
      return null;
    }

    if (value == null) return null;

    return KeyDetail(
      key: key,
      value: _formatValue(value),
      rawValue: value,
      size: _estimateSize(value),
    );
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';

    // 如果是 Map 或 List，尝试格式化
    if (value is Map || value is List) {
      try {
        return _prettyJson(value);
      } catch (e) {
        return value.toString();
      }
    }

    return value.toString();
  }

  String _prettyJson(dynamic data) {
    // 简单的 JSON 格式化
    final str = data.toString();
    // 尝试解析并重新格式化
    try {
      // 简单缩进处理
      final buffer = StringBuffer();
      int indent = 0;
      bool inString = false;

      for (int i = 0; i < str.length; i++) {
        final char = str[i];
        if (char == '"' && (i == 0 || str[i-1] != '\\')) {
          inString = !inString;
          buffer.write(char);
        } else if (!inString) {
          if (char == '{' || char == '[') {
            buffer.write(char);
            buffer.write('\n');
            indent++;
            buffer.write('  ' * indent);
          } else if (char == '}' || char == ']') {
            buffer.write('\n');
            indent--;
            buffer.write('  ' * indent);
            buffer.write(char);
          } else if (char == ',') {
            buffer.write(char);
            buffer.write('\n');
            buffer.write('  ' * indent);
          } else if (char == ':') {
            buffer.write(': ');
          } else if (char == ' ' && str[i-1] == ':') {
            // 跳过
          } else {
            buffer.write(char);
          }
        } else {
          buffer.write(char);
        }
      }
      return buffer.toString();
    } catch (e) {
      return str;
    }
  }

  int _estimateSize(dynamic value) {
    return value.toString().length;
  }

  /// 删除单个值
  Future<bool> delete(StorageType type, String key, {String? boxName}) async {
    try {
      switch (type) {
        case StorageType.hive:
          // Hive 的 key 格式是 "boxName/key"
          String actualBoxName = boxName ?? '';
          String actualKey = key;

          if (boxName == null && key.contains('/')) {
            final parts = key.split('/');
            actualBoxName = parts[0];
            actualKey = parts.sublist(1).join('/');
          }

          if (actualBoxName.isEmpty) return false;
          final box = Hive.box(actualBoxName);
          await box.delete(actualKey);
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
          if (boxName != null) {
            final box = Hive.box(boxName);
            await box.clear();
            return true;
          }
          // 清空所有 Hive Box
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
                await Hive.box(name).clear();
              }
            } catch (e) {
              // 忽略
            }
          }
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

  /// 删除所有 Hive 数据
  Future<void> deleteAllHive() async {
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
        await Hive.deleteBoxFromDisk(name);
      } catch (e) {
        // 忽略
      }
    }
  }

  /// 获取 Hive 整体信息
  Future<StorageInfo> _getHiveInfo() async {
    int totalSize = 0;
    int totalKeys = 0;
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
          totalKeys += box.length;
          totalSize += _estimateBoxSize(box);
        }
      } catch (e) {
        // Box 可能不存在
      }
    }

    return StorageInfo(
      type: StorageType.hive,
      name: 'Hive',
      keyCount: totalKeys,
      size: totalSize,
    );
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

/// 键值详情
class KeyDetail {
  const KeyDetail({
    required this.key,
    required this.value,
    required this.rawValue,
    required this.size,
  });

  final String key;
  final String value; // 格式化后的值
  final dynamic rawValue; // 原始值
  final int size;

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  bool get isJson => rawValue is Map || rawValue is List;
}
