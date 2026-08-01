import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'storage_registry.dart';

/// 统一存储管理器
///
/// 所有 typed box 的信息（box 名、打开、格式化）通过 [StorageRegistry] 注册，
/// StorageManager 只作为纯查询代理——新增 typed box 时只需注册，不用改本文件。
///
/// ## 注册表模式一统
///
/// 每个 feature 在自己的 Hive init 处：
/// ```dart
/// StorageRegistry.register(BoxDescriptor<YourModel>(
///   name: 'your_box',
///   displayName: '你的中文名',
///   typeId: 92,
///   openTyped: () => Hive.openBox<YourModel>('your_box'),
///   formatValue: (v) { final m = v as YourModel; return '字段: ${m.x}'; },
/// ));
/// ```
class StorageManager {
  StorageManager._();
  static final StorageManager instance = StorageManager._();

  bool _isInitialized = false;

  /// 所有已知 box 名 —— 纯注册表驱动。
  ///
  /// 每个 feature 在自己的 Hive init 处注册 [BoxDescriptor]，这里就能遍历到。
  /// 不再有遗留硬编码 box 名（旧的 _legacyNameMap 含 focus_sessions /
  /// clock_records 等"幽灵条目"——它们其实是 SharedPreferences key，不是
  /// Hive box，会让面板误判并顺手建出空 box，已删除）。
  List<String> _allBoxNames() {
    return StorageRegistry.all.map((d) => d.name).toList();
  }

  // ── Public API ────────────────────────────────────────────

  /// 初始化所有存储
  Future<void> init() async {
    if (_isInitialized) return;
    await Hive.initFlutter();
    _isInitialized = true;
  }

  /// 获取所有存储信息
  Future<List<StorageInfo>> getAllStorageInfo() async {
    final result = <StorageInfo>[];

    // Hive boxes（每个 box 一个 entry）
    result.addAll(await _getHiveInfo());

    // SharedPreferences（作为一个整体）
    final prefs = await SharedPreferences.getInstance();
    final pKeys = prefs.getKeys();
    int pSize = 0;
    for (final k in pKeys) {
      final v = prefs.get(k);
      if (v != null) pSize += v.toString().length;
    }
    result.add(StorageInfo(
      type: StorageType.prefs,
      name: 'SharedPreferences',
      keyCount: pKeys.length,
      size: pSize,
    ));

    return result;
  }

  /// 获取特定存储类型的所有键
  Future<List<String>> getKeys(StorageType type, {String? boxName}) async {
    switch (type) {
      case StorageType.hive:
        if (boxName == null) return [];
        if (!Hive.isBoxOpen(boxName)) return [];
        final d = StorageRegistry.get(boxName);
        if (d != null) {
          return d.keys.map((k) => k.toString()).toList();
        }
        return Hive.box(boxName).keys.map((k) => k.toString()).toList();

      case StorageType.prefs:
        return (await SharedPreferences.getInstance()).getKeys().toList();
    }
  }

  /// 获取某 box 的键值详情列表
  Future<List<KeyDetail>> getKeyDetails(StorageType type, {String? boxName}) async {
    final result = <KeyDetail>[];

    switch (type) {
      case StorageType.hive:
        final names = boxName != null ? [boxName] : _allBoxNames();
        for (final name in names) {
          try {
            if (!Hive.isBoxOpen(name)) {
              final d = StorageRegistry.get(name);
              if (d != null) {
                await d.ensureOpen();
              } else {
                await Hive.openBox(name);
              }
            }
            if (!Hive.isBoxOpen(name)) continue;

            // 通过 BoxDescriptor 读（支持 typed box 泛型 + 自定义格式化）
            final d = StorageRegistry.get(name);
            if (d != null) {
              for (final key in d.keys) {
                final value = d.get(key);
                result.add(KeyDetail(
                  key: '$name/$key',
                  value: d.formatValue != null && value != null
                      ? d.formatValue!(value)
                      : _formatValue(value),
                  rawValue: value,
                  size: d.estimateSize != null && value != null
                      ? d.estimateSize!(value)
                      : _estimateSize(value),
                ));
              }
            } else {
              // 遗留非 typed box
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
            debugPrint('StorageManager: getKeyDetails($name) 出错: $e');
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

          final d = StorageRegistry.get(actualBoxName);
          if (d != null) {
            value = d.get(actualKey);
          } else {
            value = Hive.box(actualBoxName).get(actualKey);
          }
          break;

        case StorageType.prefs:
          value = (await SharedPreferences.getInstance()).get(key);
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

  /// 删除单条
  Future<bool> delete(StorageType type, String key, {String? boxName}) async {
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
          if (actualBoxName.isEmpty) return false;

          final d = StorageRegistry.get(actualBoxName);
          if (d != null) {
            await d.delete(actualKey);
          } else {
            await Hive.box(actualBoxName).delete(actualKey);
          }
          return true;

        case StorageType.prefs:
          return (await SharedPreferences.getInstance()).remove(key);
      }
    } catch (e) {
      return false;
    }
  }

  /// 批量删除
  Future<int> deleteMany(StorageType type, List<String> keys, {String? boxName}) async {
    int deleted = 0;
    for (final key in keys) {
      if (await delete(type, key, boxName: boxName)) deleted++;
    }
    return deleted;
  }

  /// 清空指定存储
  Future<bool> clear(StorageType type, {String? boxName}) async {
    try {
      switch (type) {
        case StorageType.hive:
          if (boxName != null) {
            final d = StorageRegistry.get(boxName);
            if (d != null) {
              await d.clear();
            } else {
              await Hive.box(boxName).clear();
            }
            return true;
          }
          // 清空所有已知 box
          for (final name in _allBoxNames()) {
            try {
              if (Hive.isBoxOpen(name)) {
                final d = StorageRegistry.get(name);
                if (d != null) {
                  await d.clear();
                } else {
                  await Hive.box(name).clear();
                }
              }
            } catch (_) {}
          }
          return true;

        case StorageType.prefs:
          await (await SharedPreferences.getInstance()).clear();
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
    } catch (_) {
      return false;
    }
  }

  /// 删除所有 Hive 数据（保留 box 结构）
  Future<void> deleteAllHive() async {
    for (final name in _allBoxNames()) {
      try {
        if (Hive.isBoxOpen(name)) {
          final d = StorageRegistry.get(name);
          if (d != null) {
            await d.clear();
          } else {
            await Hive.box(name).clear();
          }
        }
      } catch (_) {}
    }
  }

  // ── 内部 ────────────────────────────────────────────

  /// 遍历所有注册 + 遗留 box，返回每个的 StorageInfo
  Future<List<StorageInfo>> _getHiveInfo() async {
    final result = <StorageInfo>[];

    for (final name in _allBoxNames()) {
      try {
        int length = 0;
        int size = 0;

        if (Hive.isBoxOpen(name)) {
          final d = StorageRegistry.get(name);
          if (d != null) {
            length = d.length;
            size = _estimateBoxSize(name);
          } else {
            final box = Hive.box(name);
            length = box.length;
            size = _estimateBoxSize(name);
          }
        } else {
          // 尝试打开
          final d = StorageRegistry.get(name);
          if (d != null) {
            await d.ensureOpen();
            length = d.length;
          } else {
            await Hive.openBox(name);
            length = Hive.box(name).length;
          }
          size = _estimateBoxSize(name);
        }

        result.add(StorageInfo(
          type: StorageType.hive,
          name: name,
          keyCount: length,
          size: size,
        ));
      } catch (e) {
        debugPrint('StorageManager: _getHiveInfo($name) 出错: $e');
      }
    }
    return result;
  }

  /// 估算某 box 的字节大小
  int _estimateBoxSize(String name) {
    try {
      if (!Hive.isBoxOpen(name)) return 0;
      final d = StorageRegistry.get(name);
      if (d != null) {
        int total = 0;
        for (final key in d.keys) {
          final value = d.get(key);
          if (value != null) {
            total += key.toString().length;
            total += d.estimateSize != null
                ? d.estimateSize!(value)
                : value.toString().length;
          }
        }
        return total;
      }
      final box = Hive.box(name);
      int total = 0;
      for (final key in box.keys) {
        final value = box.get(key);
        if (value != null) {
          total += key.toString().length + value.toString().length;
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    // 如果是 Map 或 List，格式化
    if (value is Map || value is List) {
      try {
        return _prettyJson(value);
      } catch (e) {
        return value.toString();
      }
    }
    return value.toString();
  }

  int _estimateSize(dynamic value) {
    if (value == null) return 0;
    return value.toString().length;
  }

  String _prettyJson(dynamic data) {
    final str = data.toString();
    try {
      final buffer = StringBuffer();
      int indent = 0;
      bool inString = false;
      for (int i = 0; i < str.length; i++) {
        final char = str[i];
        if (char == '"' && (i == 0 || str[i - 1] != '\\')) {
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
          } else if (char == ' ' && str[i - 1] == ':') {
            // skip
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
}

/// 存储类型
enum StorageType { hive, prefs }

/// 存储信息
class StorageInfo {
  final StorageType type;
  final String name;
  final int keyCount;
  final int size;

  const StorageInfo({
    required this.type,
    required this.name,
    required this.keyCount,
    required this.size,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
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
    if (name == 'SharedPreferences') return '应用配置';
    return StorageRegistry.get(name)?.displayName ?? name;
  }
}

/// 键值详情
class KeyDetail {
  final String key;
  final String value;
  final dynamic rawValue;
  final int size;

  const KeyDetail({
    required this.key,
    required this.value,
    required this.rawValue,
    required this.size,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  bool get isJson => rawValue is Map || rawValue is List;
}