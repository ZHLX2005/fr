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
  final String filePath;

  const ExportResult({
    required this.text,
    required this.totalKeys,
    required this.totalSize,
    required this.timestamp,
    required this.filePath,
  });
}

class StorageExporter {
  final StorageManager _storage;
  final void Function(ExportProgress)? onProgress;

  StorageExporter({StorageManager? storage, this.onProgress})
      : _storage = storage ?? StorageManager.instance;

  /// 全量导出到文件
  /// 返回 [ExportResult]，包含文件路径与文本内容（用于备份展示）。
  Future<ExportResult> exportAll() async {
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
        // 确保 box 已打开
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

        // 计算 box 内条目数
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
            // typed box 的 adapter 没注册时，读会抛；跳过该 key 不中断整体
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

    // 写入文件
    _emitProgress(ExportStage.done, '写入文件', 0, 1);
    final filePath = await _writeExportFile(text, timestamp);

    _emitProgress(ExportStage.done, '导出完成', 1, 1);

    return ExportResult(
      text: text,
      totalKeys: totalKeys,
      totalSize: totalSize,
      timestamp: timestamp,
      filePath: filePath,
    );
  }

  /// 把导出文本写入可见的外部存储目录
  ///
  /// 优先 [getExternalStorageDirectory]（Android:
  /// `/storage/emulated/0/Android/data/<pkg>/files/exports/`，文件管理器可见），
  /// 回退到 [getApplicationDocumentsDirectory]（iOS / web / 无外部存储时）。
  Future<String> _writeExportFile(String text, String isoTimestamp) async {
    final baseDir = await _resolveExportBaseDir();
    final exportsDir = Directory('${baseDir.path}${Platform.pathSeparator}$kExportDirName');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    final safeName = isoTimestamp.replaceAll(':', '-').replaceAll('.', '-');
    final file = File(
      '${exportsDir.path}${Platform.pathSeparator}$kExportFilePrefix$safeName$kExportFileExtension',
    );
    await file.writeAsString(text);
    return file.path;
  }

  /// 解析导出文件根目录：Android 优先用外部存储（文件管理器可见）。
  Future<Directory> _resolveExportBaseDir() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    } catch (e) {
      debugPrint('getExternalStorageDirectory 失败，回退 documents: $e');
    }
    return getApplicationDocumentsDirectory();
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
