import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/core.dart';
import 'note_migration.dart';
import 'toml_codec.dart';

/// 单篇笔记的元数据。
class NoteInfo {
  final String id;
  final String title;
  final int blockCount;
  final int fileSize;
  final DateTime updatedAt;
  final String fileName;
  final String filePath;

  const NoteInfo({
    required this.id,
    required this.title,
    required this.blockCount,
    required this.fileSize,
    required this.updatedAt,
    required this.fileName,
    required this.filePath,
  });
}

/// 笔记库汇总统计。
class NoteSummary {
  final int noteCount;
  final int totalBlocks;
  final int totalSize;

  const NoteSummary({
    required this.noteCount,
    required this.totalBlocks,
    required this.totalSize,
  });
}

/// 笔记文件仓库 — 扫描 notes/ 下的 .toml 笔记文件。
///
/// 首次访问目录时懒触发老 .json → .toml 迁移（幂等，进程内只跑一次）。
class NoteRepository {
  final BlockCodec _codec;
  final TomlCodec _tomlCodec;
  final Future<Directory> Function() _notesDirProvider;
  bool _migrated = false;

  /// [notesDirProvider] 可注入：生产用 [getApplicationDocumentsDirectory]，
  /// 测试用临时目录。默认走 path_provider。
  NoteRepository(
    this._codec, {
    TomlCodec? tomlCodec,
    Future<Directory> Function()? notesDirProvider,
  })  : _tomlCodec = tomlCodec ?? TomlCodec(),
        _notesDirProvider = notesDirProvider ?? _defaultNotesDir;

  /// 将 Block 序列化为 JSON Map。
  Map<String, dynamic> encodeBlock(Block block) => _codec.encode(block);

  /// Block → TOML 字符串（复用 [BlockCodec] + [TomlCodec]）。
  String encodeToml(Block block) => _tomlCodec.encode(_codec.encode(block));

  /// TOML 字符串 → Block。解析失败返回 null（不抛异常，由调用方降级）。
  Block? decodeToml(String toml) {
    try {
      final map = _tomlCodec.decode(toml);
      return _codec.decode(map);
    } catch (e, st) {
      // ignore: avoid_print
      print('[decodeToml] parse failed: $e\n$st');
      return null;
    }
  }

  Future<Directory> _getNotesDir() async {
    final dir = await _notesDirProvider();
    if (!_migrated) {
      await NoteMigration(_tomlCodec).migrateIfNeeded(dir);
      _migrated = true;
    }
    return dir;
  }

  static Future<Directory> _defaultNotesDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    return Directory('${docDir.path}${Platform.pathSeparator}notes');
  }

  /// 列出所有笔记文件的元数据。
  Future<List<NoteInfo>> listAllNotes() async {
    final dir = await _getNotesDir();
    if (!await dir.exists()) return [];

    final files = <File>[];
    try {
      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.toml')) {
          files.add(entity);
        }
      }
    } catch (e) {
      return [];
    }

    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    final notes = <NoteInfo>[];
    for (final file in files) {
      try {
        final toml = await file.readAsString();
        final block = _codec.decode(_tomlCodec.decode(toml));
        final title = _extractTitle(block);
        final count = _countBlocks(block);

        notes.add(NoteInfo(
          id: block.id,
          title: title,
          blockCount: count,
          fileSize: await file.length(),
          updatedAt: block.updatedAt,
          fileName: file.path.split(Platform.pathSeparator).last,
          filePath: file.path,
        ));
      } catch (e) {
        notes.add(NoteInfo(
          id: file.path,
          title: file.path.split(Platform.pathSeparator).last,
          blockCount: 0,
          fileSize: await file.length(),
          updatedAt: file.lastModifiedSync(),
          fileName: file.path.split(Platform.pathSeparator).last,
          filePath: file.path,
        ));
      }
    }

    return notes;
  }

  /// 获取汇总统计。
  Future<NoteSummary> getSummary() async {
    final notes = await listAllNotes();
    return NoteSummary(
      noteCount: notes.length,
      totalBlocks: notes.fold(0, (s, n) => s + n.blockCount),
      totalSize: notes.fold(0, (s, n) => s + n.fileSize),
    );
  }

  /// 读取笔记文件的原始 JSON 字符串。
  Future<String> readRawContent(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return '';
    return await file.readAsString();
  }

  /// 从根 block 中提取标题。
  String _extractTitle(Block block) {
    if (block.type is PageType) {
      final text = block.content.toPlainText().trim();
      if (text.isNotEmpty) return text;
    }

    final heading = _findFirstHeading(block);
    if (heading != null) return heading;

    final rootText = block.content.toPlainText().trim();
    if (rootText.isNotEmpty) {
      return rootText.length > 40
          ? '${rootText.substring(0, 40)}…'
          : rootText;
    }

    return '未命名笔记';
  }

  String? _findFirstHeading(Block block) {
    if (block.type is HeadingType) {
      final t = block.content.toPlainText().trim();
      if (t.isNotEmpty) return t;
    }
    for (final child in block.children) {
      final result = _findFirstHeading(child);
      if (result != null) return result;
    }
    return null;
  }

  /// 递归统计子树中的 block 总数。
  int _countBlocks(Block block) {
    int count = 1;
    for (final child in block.children) {
      count += _countBlocks(child);
    }
    return count;
  }

  /// 将根 block 保存为笔记文件。
  Future<void> saveNote(Block block) async {
    final dir = await _getNotesDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(
      '${dir.path}${Platform.pathSeparator}${block.id}.toml',
    );
    await file.writeAsString(_tomlCodec.encode(_codec.encode(block)));
  }

  /// 按 id 删除笔记文件。
  Future<void> deleteNote(String id) async {
    final dir = await _getNotesDir();
    final file = File(
      '${dir.path}${Platform.pathSeparator}$id.toml',
    );
    if (await file.exists()) await file.delete();
  }

  /// 读取笔记并解析为根 block。
  Future<Block?> readNote(String id) async {
    final dir = await _getNotesDir();
    final file = File(
      '${dir.path}${Platform.pathSeparator}$id.toml',
    );
    if (!await file.exists()) return null;
    try {
      final toml = await file.readAsString();
      return _codec.decode(_tomlCodec.decode(toml));
    } catch (_) {
      return null;
    }
  }
}
