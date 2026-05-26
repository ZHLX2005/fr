import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../core/models/block.dart';
import '../core/models/block_codec.dart';
import '../core/type/type.dart';
import '../core/type/type_registry.dart';
import '../core/identity/identity.dart';
import '../core/text/inline_format_registry.dart';
import '../core/text/rich_text.dart';
import '../core/text/rich_text_codec.dart';

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

/// 笔记文件仓库 — 扫描 docDir/notes/ 下的 .json 笔记文件。
class NoteRepository {
  final BlockCodec _codec;
  final BlockIdentityFactory _idFactory;

  NoteRepository(this._codec, this._idFactory);

  /// 使用默认注册表 + ID 工厂 + 内联格式注册表的便利构造器。
  factory NoteRepository.withDefaults() {
    final typeRegistry = BlockTypeRegistry();
    BlockTypeRegistrar().registerAll(typeRegistry);
    final formatRegistry = InlineFormatRegistry();
    InlineFormatRegistrar().registerAll(formatRegistry);
    final idFactory = BlockIdentityFactory();
    return NoteRepository(
      BlockCodec(typeRegistry, RichTextCodec(formatRegistry), idFactory: idFactory),
      idFactory,
    );
  }

  Future<Directory> _getNotesDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    return Directory('${docDir.path}${Platform.pathSeparator}notes');
  }

  /// 列出所有笔记文件的元数据。
  Future<List<NoteInfo>> listAllNotes() async {
    final dir = await _getNotesDir();
    if (!await dir.exists()) return [];

    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        files.add(entity);
      }
    }

    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    final notes = <NoteInfo>[];
    for (final file in files) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final block = _codec.decode(json);
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

  /// 创建一篇新笔记，返回根 page block。
  Block createNote(String title) {
    return Block(
      id: _idFactory.generateId(),
      type: const PageType(),
      content: RichText.text(title),
    );
  }

  /// 将根 block 保存为笔记文件。
  Future<void> saveNote(Block block) async {
    final dir = await _getNotesDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(
      '${dir.path}${Platform.pathSeparator}${block.id}.json',
    );
    await file.writeAsString(jsonEncode(_codec.encode(block)));
  }

  /// 按 id 删除笔记文件。
  Future<void> deleteNote(String id) async {
    final dir = await _getNotesDir();
    final file = File(
      '${dir.path}${Platform.pathSeparator}$id.json',
    );
    if (await file.exists()) await file.delete();
  }

  /// 读取笔记并解析为根 block。
  Future<Block?> readNote(String id) async {
    final dir = await _getNotesDir();
    final file = File(
      '${dir.path}${Platform.pathSeparator}$id.json',
    );
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return _codec.decode(json);
    } catch (_) {
      return null;
    }
  }
}
