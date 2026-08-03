// 存储导入器
//
// 解析由 StorageExporter 生成的文本文件，把全部数据写入应用本地存储：
// - 写入 [hive:xxx] 每个 box 的键值
// - 写入 [prefs] SharedPreferences
// - 写入 [notes] 笔记文件
//
// 关键设计：
// - typed box（如 calendarEvents/calendarPeople/body_records）需要把 JSON
//   字符串反序列化为对应类的实例，通过 BoxDescriptor.getBox().put 写入。
// - 非 typed box 直接写入 dynamic 值。
// - 失败的单条记录不会中断整个导入，只统计错误数。
// - 媒体文件不参与导入（导出端已跳过）。
//
// 用法见 storage_analyze_demo.dart 的 _onImport 按钮。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage_manager.dart';
import '../storage_registry.dart';
import '../../body/models/body_record.dart';
import '../../../../lab/demos/calendar/domain/event.dart';
import '../../../../lab/demos/calendar/domain/person.dart';
import 'const_storage_export.dart';

/// 文本标记（导出端写入的 K/T/V/F/B）→ 消费者读取的字段名。
///
/// 历史坑：`_parse` 曾把每行直接存成 `{marker: value}`（即 `{'K':..,'T':..,'V':..}`），
/// 但 prefs/hive/notes 三处消费者读的是 `item['key'/'type'/'value'/'name'/'base64']`，
/// 导致 `item['key']!` 恒为 null 抛错、整段导入静默失败。这里统一把标记翻成字段名。
const Map<String, String> _kFieldByMarker = {
  'K': 'key',
  'T': 'type',
  'V': 'value',
  'F': 'name',
  'B': 'base64',
};

/// 导入进度
class ImportProgress {
  final ImportStage stage;
  final String message;
  final int current;
  final int total;

  const ImportProgress({
    required this.stage,
    required this.message,
    required this.current,
    required this.total,
  });
}

/// 导入结果
class ImportResult {
  final int prefsCount;
  final int hiveCount;
  final int notesCount;
  final int errorCount;
  final List<String> errors;

  /// 与 [errors] 一一对应的结构化条目（生产侧填充，UI 直接消费）。
  /// 默认空列表保证旧的 `ImportResult(...)` 构造兼容。
  final List<ImportError> structured;

  const ImportResult({
    required this.prefsCount,
    required this.hiveCount,
    required this.notesCount,
    required this.errorCount,
    required this.errors,
    this.structured = const [],
  });

  int get totalCount => prefsCount + hiveCount + notesCount;
}

/// 导入失败的单个错误条目。
///
/// 按 section 分组渲染：hive 显示 `hive:boxName[key]`，prefs 显示 `prefs:key`，
/// notes 显示 `notes:name`。reason 保留异常 toString 原样，不剥前缀。
class ImportError {
  final ImportErrorSection section;
  final String boxName;
  final String key;
  final String reason;

  const ImportError({
    required this.section,
    required this.boxName,
    required this.key,
    required this.reason,
  });
}

enum ImportErrorSection { hive, prefs, notes }

class StorageImporter {
  final StorageManager _storage;
  final void Function(ImportProgress)? onProgress;
  final bool _clearBeforeImport;

  StorageImporter({
    StorageManager? storage,
    this.onProgress,
    bool clearBeforeImport = false,
  })  : _storage = storage ?? StorageManager.instance,
        _clearBeforeImport = clearBeforeImport;

  /// 从文件读取并解析文本 + 写入。
  /// - [filePath] 选中的导出文件路径
  Future<ImportResult> importFromFile(String filePath) async {
    _emitProgress(ImportStage.read, '读取文件: $filePath', 0, 1);
    final file = File(filePath);
    if (!await file.exists()) {
      return ImportResult(
        prefsCount: 0,
        hiveCount: 0,
        notesCount: 0,
        errorCount: 1,
        errors: ['文件不存在: $filePath'],
      );
    }
    final text = await file.readAsString();
    _emitProgress(ImportStage.read, '读取文件完成', 1, 1);
    return importFromText(text);
  }

  /// 解析并导入文本
  Future<ImportResult> importFromText(String text) async {
    await _storage.init();

    final sections = _parse(text);
    final errors = <String>[];
    final structured = <ImportError>[];

    _emitProgress(ImportStage.parse, '解析文本', 0, 1);
    if (sections.isEmpty) {
      return ImportResult(
        prefsCount: 0,
        hiveCount: 0,
        notesCount: 0,
        errorCount: 1,
        errors: ['文本格式错误：未找到任何 section'],
      );
    }

    // ── prefs ──
    int prefsCount = 0;
    final prefs = await SharedPreferences.getInstance();
    final prefsSection = sections['prefs'] ?? {'items': []};
    final prefsItems = (prefsSection['items'] as List?) ?? [];
    if (_clearBeforeImport) {
      await prefs.clear();
    }
    _emitProgress(ImportStage.prefs, '写入应用配置', 0, prefsItems.length);
    for (var i = 0; i < prefsItems.length; i++) {
      final item = prefsItems[i] as Map<String, String>;
      try {
        final key = item['key']!;
        final type = item['type'] ?? HiveTypeNames.string;
        final value = item['value'] ?? '';
        // set* 返回 Future<bool> —— 必须 await，否则 setString 没落盘，
        // 紧接着 _loadStorageData 读 prefs 还是老值，整段导入看似成功但 0 生效。
        await _writePref(prefs, key, type, value);
        prefsCount++;
      } catch (e) {
        final keyStr = item['key'] ?? '';
        errors.add('prefs: $keyStr - $e');
        structured.add(ImportError(
          section: ImportErrorSection.prefs,
          boxName: '',
          key: keyStr,
          reason: e.toString(),
        ));
      }
      _emitProgress(ImportStage.prefs, '写入: ${item['key']}', i + 1, prefsItems.length);
    }
    // 强制 commit 让写入立刻落盘，避免 demo 立即 _loadStorageData 时拿到旧值
    await prefs.reload();

    // ── hive ──
    int hiveCount = 0;
    final hiveKeys = sections.keys.where((k) => k.startsWith('hive:')).toList();
    _emitProgress(ImportStage.hive, '写入 Hive Boxes', 0, hiveKeys.length);
    for (var i = 0; i < hiveKeys.length; i++) {
      final key = hiveKeys[i];
      final boxName = key.substring(5);
      final section = sections[key] as Map<String, dynamic>;
      final items = (section['items'] as List?) ?? [];
      try {
        await _writeHiveBox(boxName, items, errors, structured);
        hiveCount += items.length;
      } catch (e) {
        errors.add('hive:$boxName - $e');
        structured.add(ImportError(
          section: ImportErrorSection.hive,
          boxName: boxName,
          key: '',
          reason: e.toString(),
        ));
      }
      _emitProgress(ImportStage.hive, 'Box: $boxName', i + 1, hiveKeys.length);
    }

    // ── notes ──
    int notesCount = 0;
    final notesSection = sections['notes'] ?? {'items': []};
    final notesItems = (notesSection['items'] as List?) ?? [];
    _emitProgress(ImportStage.notes, '写入笔记', 0, notesItems.length);
    if (notesItems.isNotEmpty) {
      final docDir = await getApplicationDocumentsDirectory();
      final notesDir = Directory('${docDir.path}${Platform.pathSeparator}notes');
      if (!await notesDir.exists()) await notesDir.create(recursive: true);
      for (var i = 0; i < notesItems.length; i++) {
        final item = notesItems[i] as Map<String, String>;
        try {
          final name = item['name']!;
          final b64 = item['base64']!;
          final content = utf8.decode(base64Decode(b64));
          final file = File('${notesDir.path}${Platform.pathSeparator}$name');
          await file.writeAsString(content);
          notesCount++;
        } catch (e) {
          final nameStr = item['name'] ?? '';
          errors.add('notes: $nameStr - $e');
          structured.add(ImportError(
            section: ImportErrorSection.notes,
            boxName: '',
            key: nameStr,
            reason: e.toString(),
          ));
        }
        _emitProgress(ImportStage.notes, '笔记: ${item['name']}', i + 1, notesItems.length);
      }
    }

    _emitProgress(ImportStage.done, '导入完成', 1, 1);

    return ImportResult(
      prefsCount: prefsCount,
      hiveCount: hiveCount,
      notesCount: notesCount,
      errorCount: errors.length,
      errors: errors,
      structured: structured,
    );
  }

  // ── helpers ────────────────────────────────────────────

  void _emitProgress(ImportStage stage, String msg, int current, int total) {
    onProgress?.call(ImportProgress(
      stage: stage,
      message: msg,
      current: current,
      total: total,
    ));
  }

  /// 解析文本为 sections
  /// 返回 Map<sectionName, { 'items': List<Map<String, String>> }>
  Map<String, dynamic> _parse(String text) {
    final result = <String, dynamic>{};
    final lines = text.split('\n');

    String? currentSection;
    Map<String, String>? currentItem;

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        // 空行：可能结束一个 item
        if (currentItem != null) {
          _appendItem(result, currentSection!, currentItem);
          currentItem = null;
        }
        continue;
      }
      if (line.startsWith(kStorageDumpCommentPrefix) || line.startsWith('#')) {
        continue; // 跳过注释
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        if (currentItem != null) {
          _appendItem(result, currentSection!, currentItem);
          currentItem = null;
        }
        currentSection = line.substring(1, line.length - 1);
        if (!result.containsKey(currentSection)) {
          result[currentSection] = {'items': <Map<String, String>>[]};
        }
        continue;
      }
      if (currentSection == null) continue;

      final sepIdx = line.indexOf(':');
      if (sepIdx < 0) continue;
      final marker = line.substring(0, sepIdx);
      final value = line.substring(sepIdx + 1);

      currentItem ??= <String, String>{};
      // 标记 → 字段名（K→key / T→type / V→value / F→name / B→base64）
      currentItem[_kFieldByMarker[marker] ?? marker] = value;
    }
    if (currentItem != null && currentSection != null) {
      _appendItem(result, currentSection, currentItem);
    }
    return result;
  }

  void _appendItem(
    Map<String, dynamic> result,
    String section,
    Map<String, String> item,
  ) {
    final s = result[section];
    if (s is Map) {
      final items = (s['items'] as List?) ?? [];
      items.add(item);
    }
  }

  Future<void> _writePref(SharedPreferences prefs, String key, String type, String value) async {
    switch (type) {
      case HiveTypeNames.string:
        await prefs.setString(key, value);
        break;
      case HiveTypeNames.int:
        await prefs.setInt(key, int.parse(value));
        break;
      case HiveTypeNames.double:
        await prefs.setDouble(key, double.parse(value));
        break;
      case HiveTypeNames.bool:
        await prefs.setBool(key, value.toLowerCase() == 'true');
        break;
      case HiveTypeNames.list:
        final decoded = jsonDecode(value);
        if (decoded is List) {
          await prefs.setStringList(key, decoded.map((e) => e.toString()).toList());
        }
        break;
      default:
        // 兜底：原样存为 string
        await prefs.setString(key, value);
    }
  }

  Future<void> _writeHiveBox(
    String boxName,
    List<dynamic> items,
    List<String> errors,
    List<ImportError> structured,
  ) async {
    final d = StorageRegistry.get(boxName);
    if (d != null) {
      await d.ensureOpen();
      if (_clearBeforeImport) {
        await d.clear();
      }
      final box = d.getBox();
      for (final item in items) {
        final m = item as Map<String, String>;
        final key = m['key']!;
        final type = m['type'] ?? '';
        final value = m['value'] ?? '';
        try {
          final obj = _decodeTypedValue(value, type);
          final typedKey = _parseKey(key);
          await box.put(typedKey, obj);
        } catch (e) {
          errors.add('hive:$boxName[$key] - $e');
          structured.add(ImportError(
            section: ImportErrorSection.hive,
            boxName: boxName,
            key: key,
            reason: e.toString(),
          ));
        }
      }
    } else {
      // 遗留非 typed box
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      final box = Hive.box(boxName);
      if (_clearBeforeImport) {
        await box.clear();
      }
      for (final item in items) {
        final m = item as Map<String, String>;
        try {
          final key = _parseKey(m['key']!);
          final obj = _decodeDynamicValue(m['value'] ?? '', m['type'] ?? '');
          await box.put(key, obj);
        } catch (e) {
          final keyStr = m['key'] ?? '';
          errors.add('hive:$boxName[$keyStr] - $e');
          structured.add(ImportError(
            section: ImportErrorSection.hive,
            boxName: boxName,
            key: keyStr,
            reason: e.toString(),
          ));
        }
      }
    }
  }

  /// 把 key 字符串解析回原类型（int / String 都尝试）
  dynamic _parseKey(String keyStr) {
    final asInt = int.tryParse(keyStr);
    if (asInt != null) return asInt;
    return keyStr;
  }

  /// 按 type 标签反序列化为 typed 对象
  dynamic _decodeTypedValue(String value, String type) {
    switch (type) {
      case HiveTypeNames.event:
        final map = jsonDecode(value) as Map<String, dynamic>;
        return Event.fromJson(map);
      case HiveTypeNames.person:
        final map = jsonDecode(value) as Map<String, dynamic>;
        return Person.fromJson(map);
      case HiveTypeNames.bodyRecord:
        final map = jsonDecode(value) as Map<String, dynamic>;
        return BodyRecord(
          bodyPartId: map['bodyPartId'] as String,
          content: map['content'] as String,
          painLevel: map['painLevel'] as int?,
          createdAt: DateTime.parse(map['createdAt'] as String),
        );
      default:
        return _decodeDynamicValue(value, type);
    }
  }

  /// 把 value 字符串解析为 dynamic（兼容 Map / List / 基本类型）
  dynamic _decodeDynamicValue(String value, String type) {
    if (value.isEmpty) return null;
    switch (type) {
      case HiveTypeNames.string:
        return value;
      case HiveTypeNames.int:
        return int.parse(value);
      case HiveTypeNames.double:
        return double.parse(value);
      case HiveTypeNames.bool:
        return value.toLowerCase() == 'true';
      case HiveTypeNames.map:
      case HiveTypeNames.list:
        try {
          return jsonDecode(value);
        } catch (_) {
          return value;
        }
      default:
        // 未知类型：尝试 JSON 解析，失败回退到字符串
        try {
          return jsonDecode(value);
        } catch (_) {
          return value;
        }
    }
  }
}
