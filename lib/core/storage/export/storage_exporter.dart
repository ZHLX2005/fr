// 存储导出器
//
// 把应用核心本地存储序列化为可读文本格式：
// - Hive Boxes（注册表 + 遗留）
// - SharedPreferences
// - 笔记文件（TOML，Base64 编码）
//
// 媒体文件不导出（尺寸大、剪切板与文本编辑受限）。
// 导出结果写到 <docs>/exports/storage_dump_<timestamp>.txt，便于
// 通过文件管理器 / 分享面板传给另一台设备。
//
// 用法见 storage_analyze_demo.dart 的 _onExport 按钮。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage_manager.dart';
import '../storage_registry.dart';
import '../../body/models/body_record.dart';
import '../../../../lab/demos/calendar/domain/event.dart';
import '../../../../lab/demos/calendar/domain/person.dart';
import 'const_storage_export.dart';

/// 导出进度
class ExportProgress {
  final ExportStage stage;
  final String message;
  final int current;
  final int total;

  const ExportProgress({
    required this.stage,
    required this.message,
    required this.current,
    required this.total,
  });
}

/// 导出结果
class ExportResult {
  final String text;
  final int totalKeys;
  final int totalSize;
  final String timestamp;

  const ExportResult({
    required this.text,
    required this.totalKeys,
    required this.totalSize,
    required this.timestamp,
  });
}

class StorageExporter {
  final StorageManager _storage;
  final void Function(ExportProgress)? onProgress;

  StorageExporter({StorageManager? storage, this.onProgress})
      : _storage = storage ?? StorageManager.instance;

  /// 全量导出 —— 拼文本（不写文件）。
  ///
  /// 保留 _storage.init() + _discoverBoxNames() + 逐 box 打开 + meta +
  /// hive/prefs/notes + footer；不写文件。返回的 [ExportResult.text] 是
  /// 完整 dump 文本，可直接走 KV 上传 / 落盘（若日后需要）。
  Future<ExportResult> buildDumpText() async {
    await _storage.init();
    final prefs = await SharedPreferences.getInstance();

    final buffer = StringBuffer();
    final timestamp = DateTime.now().toIso8601String();
    int totalKeys = 0;
    int totalSize = 0;

    // 头部
    buffer.writeln('# $kStorageDumpHeader');
    buffer.writeln('# timestamp=$timestamp');
    buffer.writeln('# app=flutter_application_1');
    buffer.writeln();

    // === meta ===
    _emitProgress(ExportStage.meta, '写入元数据', 0, 1);
    buffer.writeln(storageSection('meta'));
    buffer.writeln('app=flutter_application_1');
    buffer.writeln('platform=${Platform.operatingSystem}');
    buffer.writeln('export_time=$timestamp');
    buffer.writeln('storage_dump_version=1');
    buffer.writeln();

    // === Hive boxes ===
    final boxNames = await _discoverBoxNames();
    _emitProgress(ExportStage.hive, '导出 Hive Boxes', 0, boxNames.length);
    int hiveIdx = 0;
    for (final name in boxNames) {
      _emitProgress(ExportStage.hive, '导出 Box: $name', hiveIdx, boxNames.length);
      try {
        if (!Hive.isBoxOpen(name)) {
          final d = StorageRegistry.get(name);
          if (d != null) {
            await d.ensureOpen();
          } else {
            await Hive.openBox(name);
          }
        }
        if (!Hive.isBoxOpen(name)) {
          hiveIdx++;
          continue;
        }

        final d = StorageRegistry.get(name);
        final keys = d != null ? d.keys.toList() : Hive.box(name).keys.toList();

        buffer.writeln(storageSection('hive:$name'));
        buffer.writeln('# type=${d?.isTyped == true ? 'typed' : 'untyped'}');
        buffer.writeln('# displayName=${d?.displayName ?? name}');
        buffer.writeln('# keyCount=${keys.length}');

        for (final key in keys) {
          dynamic raw;
          try {
            raw = d != null ? d.get(key) : Hive.box(name).get(key);
          } catch (e) {
            debugPrint('导出 Box $name key=$key 读值失败（可能缺 adapter）: $e');
            continue;
          }
          if (raw == null) continue;

          final typeName = _typeNameOf(raw);
          final valueStr = _encodeValue(raw);

          buffer.writeln(storageKeyMarker(key.toString()));
          buffer.writeln(storageTypeMarker(typeName));
          buffer.writeln(storageValueMarker(valueStr));
          buffer.writeln();

          totalKeys++;
          totalSize += valueStr.length;
        }
        buffer.writeln();
      } catch (e) {
        debugPrint('导出 Box $name 出错: $e');
      }
      hiveIdx++;
    }

    // === SharedPreferences ===
    _emitProgress(ExportStage.prefs, '导出应用配置', 0, 1);
    final pKeys = prefs.getKeys();
    buffer.writeln(storageSection('prefs'));
    buffer.writeln('# keyCount=${pKeys.length}');
    for (final key in pKeys) {
      final v = prefs.get(key);
      if (v == null) continue;
      final typeName = _typeNameOf(v);
      final valueStr = _encodeValue(v);

      buffer.writeln(storageKeyMarker(key));
      buffer.writeln(storageTypeMarker(typeName));
      buffer.writeln(storageValueMarker(valueStr));
      buffer.writeln();

      totalKeys++;
      totalSize += valueStr.length;
    }
    buffer.writeln();

    // === Notes ===
    final notes = await _collectNotes();
    _emitProgress(ExportStage.notes, '导出笔记文件', 0, notes.length);
    buffer.writeln(storageSection('notes'));
    buffer.writeln('# noteCount=${notes.length}');
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      _emitProgress(ExportStage.notes, '笔记: ${n.name}', i, notes.length);
      final b64 = base64Encode(utf8.encode(n.content));
      buffer.writeln(storageFileMarker(n.name));
      buffer.writeln(storageBase64Marker(b64));
      buffer.writeln();
      totalSize += n.content.length;
    }
    buffer.writeln();

    // === footer ===
    buffer.writeln('# END_STORAGE_DUMP_V1');
    buffer.writeln('# total_keys=$totalKeys');
    buffer.writeln('# total_size=$totalSize');

    final text = buffer.toString();

    _emitProgress(ExportStage.done, '导出完成', 1, 1);

    return ExportResult(
      text: text,
      totalKeys: totalKeys,
      totalSize: totalSize,
      timestamp: timestamp,
    );
  }

  // ── helpers ────────────────────────────────────────────

  void _emitProgress(ExportStage stage, String msg, int current, int total) {
    onProgress?.call(ExportProgress(
      stage: stage,
      message: msg,
      current: current,
      total: total,
    ));
  }

  /// 发现所有 Hive box：注册表 + 遗留名 + 磁盘扫描（兜底未注册的 box）。
  ///
  /// 磁盘扫描是关键 —— 像 `price_compare` 这类直接 `Hive.openBox` 但没
  /// 注册到 StorageRegistry 的 box，靠注册表发现不到；扫描 `<docs>/*.hive`
  /// 才能把它们也导出。
  Future<List<String>> _discoverBoxNames() async {
    final names = <String>{};
    // 1. 注册表
    for (final d in StorageRegistry.all) {
      names.add(d.name);
    }
    // 2. 遗留硬编码名
    for (final n in const [
      'timetable_config',
      'timetable_items',
      'focus_sessions',
      'focus_subjects',
      'clock_records',
      'notes',
    ]) {
      names.add(n);
    }
    // 3. 磁盘扫描兜底
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dir = Directory(docDir.path);
      if (await dir.exists()) {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File) {
            final fileName = entity.path.split(Platform.pathSeparator).last;
            // Hive 非 lazy box 文件为 <name>.hive
            if (fileName.endsWith('.hive')) {
              names.add(fileName.substring(0, fileName.length - 5));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('磁盘扫描 box 失败: $e');
    }
    return names.toList()..sort();
  }

  String _typeNameOf(dynamic v) {
    if (v == null) return HiveTypeNames.null_;
    // 已知 typed
    if (v.runtimeType.toString() == 'Event') return HiveTypeNames.event;
    if (v.runtimeType.toString() == 'Person') return HiveTypeNames.person;
    if (v.runtimeType.toString() == 'BodyRecord') return HiveTypeNames.bodyRecord;
    if (v is Map) return HiveTypeNames.map;
    if (v is List) return HiveTypeNames.list;
    if (v is String) return HiveTypeNames.string;
    if (v is int) return HiveTypeNames.int;
    if (v is double) return HiveTypeNames.double;
    if (v is bool) return HiveTypeNames.bool;
    return HiveTypeNames.dynamic;
  }

  String _encodeValue(dynamic v) {
    if (v == null) return '';
    // typed 对象必须走 toJson / 显式序列化 —— toString() 产出 "Instance of 'X'"
    // 会让导入端 jsonDecode + fromJson 必败，typed box（日历事件/人物/身体记录）无法还原。
    if (v is Event) return jsonEncode(v.toJson());
    if (v is Person) return jsonEncode(v.toJson());
    if (v is BodyRecord) {
      // BodyRecord 无 toJson；按导入端 _decodeTypedValue 的字段契约手工序列化
      return jsonEncode({
        'bodyPartId': v.bodyPartId,
        'content': v.content,
        'painLevel': v.painLevel,
        'createdAt': v.createdAt.toIso8601String(),
      });
    }
    if (v is Map || v is List) {
      try {
        return jsonEncode(v);
      } catch (e) {
        return v.toString();
      }
    }
    return v.toString();
  }

  Future<List<_NoteEntry>> _collectNotes() async {
    final result = <_NoteEntry>[];
    final docDir = await getApplicationDocumentsDirectory();
    final notesDir = Directory('${docDir.path}${Platform.pathSeparator}notes');
    if (!await notesDir.exists()) return result;
    await for (final entity in notesDir.list(followLinks: false)) {
      if (entity is File) {
        final path = entity.path;
        if (path.endsWith('.toml') || path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final name = path.split(Platform.pathSeparator).last;
            result.add(_NoteEntry(name: name, content: content));
          } catch (_) {}
        }
      }
    }
    return result;
  }
}

class _NoteEntry {
  final String name;
  final String content;
  _NoteEntry({required this.name, required this.content});
}
