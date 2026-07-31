// 存储导出器
//
// 把应用全部本地存储序列化为可读文本格式：
// - Hive Boxes（注册表 + 遗留）
// - SharedPreferences
// - 笔记文件（TOML，Base64 编码）
// - 媒体文件（图片/视频/音频，Base64 编码）
//
// 用法见 storage_analyze_demo.dart 的 _onExport 按钮。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/storage/storage_manager.dart';
import '../../../core/storage/storage_registry.dart';
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

  /// 全量导出
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
    final boxNames = _allBoxNames();
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
          final raw = d != null ? d.get(key) : Hive.box(name).get(key);
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

    // === Media ===
    final media = await _collectMedia();
    _emitProgress(ExportStage.media, '导出媒体文件', 0, media.length);
    buffer.writeln(storageSection('media'));
    buffer.writeln('# mediaCount=${media.length}');
    for (var i = 0; i < media.length; i++) {
      final m = media[i];
      _emitProgress(ExportStage.media, '媒体: ${m.relPath}', i, media.length);
      final b64 = base64Encode(m.bytes);
      buffer.writeln(storagePathMarker(m.relPath));
      buffer.writeln(storageTypeMarker(m.type));
      buffer.writeln(storageBase64Marker(b64));
      buffer.writeln();
      totalSize += m.bytes.length;
    }
    buffer.writeln();

    // === footer ===
    buffer.writeln('# END_STORAGE_DUMP_V1');
    buffer.writeln('# total_keys=$totalKeys');
    buffer.writeln('# total_size=$totalSize');

    _emitProgress(ExportStage.done, '导出完成', 1, 1);

    return ExportResult(
      text: buffer.toString(),
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

  /// 已知 box 列表（注册表 + 遗留）
  List<String> _allBoxNames() {
    final fromRegistry = StorageRegistry.all.map((d) => d.name).toList();
    const legacy = [
      'timetable_config',
      'timetable_items',
      'focus_sessions',
      'focus_subjects',
      'clock_records',
      'notes',
    ];
    final all = <String>[];
    for (final n in legacy) {
      if (!all.contains(n)) all.add(n);
    }
    for (final n in fromRegistry) {
      if (!all.contains(n)) all.add(n);
    }
    return all;
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

  Future<List<_MediaEntry>> _collectMedia() async {
    final result = <_MediaEntry>[];
    const mediaExt = {
      'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
      'mp4', 'mov', 'avi', 'mkv', 'webm',
      'mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac',
    };
    final dirs = <Directory>[];
    try {
      dirs.add(await getTemporaryDirectory());
    } catch (_) {}
    try {
      dirs.add(await getApplicationDocumentsDirectory());
    } catch (_) {}

    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final ext = entity.path.split('.').last.toLowerCase();
            if (!mediaExt.contains(ext)) continue;
            try {
              final bytes = await entity.readAsBytes();
              final dirPath = dir.path;
              var relPath = entity.path;
              if (entity.path.startsWith(dirPath)) {
                relPath = entity.path.substring(dirPath.length);
                if (relPath.startsWith(Platform.pathSeparator)) {
                  relPath = relPath.substring(1);
                }
              }
              // 标记目录来源
              final tag = (dirPath.contains('cache') || dirPath.contains('tmp'))
                  ? 'temp'
                  : 'docs';
              final type = _mediaTypeOf(ext);
              result.add(_MediaEntry(
                relPath: '$tag/$relPath',
                type: type,
                bytes: bytes,
              ));
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    return result;
  }

  String _mediaTypeOf(String ext) {
    const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
    const videos = {'mp4', 'mov', 'avi', 'mkv', 'webm'};
    const audios = {'mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac'};
    if (images.contains(ext)) return 'image';
    if (videos.contains(ext)) return 'video';
    if (audios.contains(ext)) return 'audio';
    return 'file';
  }
}

class _NoteEntry {
  final String name;
  final String content;
  _NoteEntry({required this.name, required this.content});
}

class _MediaEntry {
  final String relPath;
  final String type;
  final List<int> bytes;
  _MediaEntry({required this.relPath, required this.type, required this.bytes});
}
