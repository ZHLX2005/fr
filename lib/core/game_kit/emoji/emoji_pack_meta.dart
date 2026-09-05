// lib/core/game_kit/emoji/emoji_pack_meta.dart
//
// Emoji pack metadata — KV schema for emoji_<scope>:index (group 190).
//
// KV 约定（与 ve emoji-pack-admin 对齐）：
//   key:   emoji_<scope>:index   e.g. emoji_common:index / emoji_chess:index
//   group: 190
//   tag:   <scope>-emoji
//
// Value 支持两种形态：
//   A) 管理后台 open-set（现行）：
//      [{ id, displayName?, file: FileRef, ... }, ...]
//   B) 历史 pack 嵌套：
//      [{ id, displayName, emojis: { <emojiId>: FileRef } | [{id,file}...] }, ...]
//
// 复用 [FileRef]（lib/core/game_kit/skin/game_skin_meta.dart）。

import 'dart:convert';

import '../skin/game_skin_meta.dart' show FileRef;

/// emoji pack id 正则（与 skin 一致：kebab-case）。
final RegExp kEmojiPackIdPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,31}$');

/// emoji id 正则（单个表情的 id，如 thumbs-up / happy）。
final RegExp kEmojiIdPattern = RegExp(r'^[a-z0-9][a-z0-9-_]{0,31}$');

/// 单个表情资产（id + 远端文件引用）。
class EmojiAsset {
  final String id;
  final FileRef file;

  const EmojiAsset({required this.id, required this.file});

  Map<String, dynamic> toJson() => {
        'id': id,
        ...file.toJson(),
      };

  factory EmojiAsset.fromJson(Map<String, dynamic> j) => EmojiAsset(
        id: j['id'] as String,
        file: FileRef.fromJson(j),
      );

  @override
  bool operator ==(Object other) =>
      other is EmojiAsset && id == other.id && file == other.file;

  @override
  int get hashCode => Object.hash(id, file);
}

/// 一套 emoji pack 的 metadata。
///
/// [emojis] 为 id → [FileRef] 的扁平映射。
class EmojiPackMeta {
  final String id;
  final String displayName;
  final Map<String, FileRef> emojis;

  final String? author;
  final String? description;
  final int version;

  const EmojiPackMeta({
    required this.id,
    required this.displayName,
    required this.emojis,
    this.author,
    this.description,
    this.version = 1,
  });

  static String kvIndexKeyForScope(String scope) => 'emoji_$scope:index';

  static String kvTagForScope(String scope) => '$scope-emoji';

  static const int kGroupId = 190;

  static String commonScopeIndexKey() => kvIndexKeyForScope('common');
  static String gameScopeIndexKey(String gameId) =>
      kvIndexKeyForScope(gameId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        if (author != null) 'author': author,
        if (description != null) 'description': description,
        'version': version,
        'emojis': {
          for (final e in emojis.entries) e.key: e.value.toJson(),
        },
      };

  factory EmojiPackMeta.fromJson(Map<String, dynamic> j) {
    final rawEmojis = j['emojis'];
    final emojis = _parseEmojis(rawEmojis);
    return EmojiPackMeta(
      id: j['id'] as String,
      displayName: j['displayName'] as String? ?? j['id'] as String,
      emojis: emojis,
      author: j['author'] as String?,
      description: j['description'] as String?,
      version: (j['version'] as num?)?.toInt() ?? 1,
    );
  }

  /// 宽松 FileRef 解析（sizeBytes / contentType / fileName 可缺）。
  static FileRef? _fileRefFrom(Map<String, dynamic> j) {
    final fileId = j['fileId']?.toString();
    if (fileId == null || fileId.isEmpty) return null;
    return FileRef(
      fileId: fileId,
      fileName: j['fileName']?.toString() ?? '$fileId.webp',
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      contentType: j['contentType']?.toString() ?? 'image/webp',
    );
  }

  static Map<String, FileRef> _parseEmojis(dynamic raw) {
    final out = <String, FileRef>{};
    if (raw == null) return out;
    if (raw is Map) {
      for (final entry in raw.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        if (v is! Map) continue;
        final ref = _fileRefFrom(Map<String, dynamic>.from(v));
        if (ref != null) out[k] = ref;
      }
      return out;
    }
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final id = (m['id'] ?? m['emojiId'] ?? m['emoji_id'])?.toString();
        if (id == null || id.isEmpty) continue;
        if (!kEmojiIdPattern.hasMatch(id)) continue;
        Map<String, dynamic>? fileJson;
        if (m['file'] is Map) {
          fileJson = Map<String, dynamic>.from(m['file'] as Map);
        } else if (m['fileRef'] is Map) {
          fileJson = Map<String, dynamic>.from(m['fileRef'] as Map);
        } else if (m['ref'] is Map) {
          fileJson = Map<String, dynamic>.from(m['ref'] as Map);
        } else if (m.containsKey('fileId')) {
          fileJson = Map<String, dynamic>.from(m)
            ..remove('id')
            ..remove('emojiId')
            ..remove('emoji_id')
            ..remove('displayName')
            ..remove('name')
            ..remove('author')
            ..remove('version')
            ..remove('createdAt')
            ..remove('updatedAt');
        }
        if (fileJson == null) continue;
        final ref = _fileRefFrom(fileJson);
        if (ref != null) out[id] = ref;
      }
      return out;
    }
    return out;
  }

  /// 是否为管理后台的扁平 open-set 列表项（有 file / fileId，无 emojis）。
  static bool _looksLikeFlatEmojiItem(Map raw) {
    if (raw.containsKey('emojis')) return false;
    return raw.containsKey('file') || raw.containsKey('fileId');
  }

  /// 解析 JSON array 文本为 [List<EmojiPackMeta>]。
  ///
  /// 自动识别：
  /// - 扁平 open-set → 合成一个 id=`default` 的 pack
  /// - pack 嵌套数组 → 原样解析
  static List<EmojiPackMeta> parseList(String jsonText) {
    final raw = jsonDecode(jsonText);
    if (raw is! List) throw const FormatException('expected JSON array');
    if (raw.isEmpty) return const [];

    // 探测首项：扁平 open-set（emoji-pack-admin 现行格式）
    final first = raw.first;
    if (first is Map && _looksLikeFlatEmojiItem(first)) {
      final emojis = _parseEmojis(raw);
      if (emojis.isEmpty) return const [];
      return [
        EmojiPackMeta(
          id: 'default',
          displayName: 'default',
          emojis: emojis,
        ),
      ];
    }

    final seen = <String>{};
    final out = <EmojiPackMeta>[];
    for (final e in raw) {
      if (e is! Map) throw const FormatException('expected object in array');
      final m = Map<String, dynamic>.from(e);
      final pack = EmojiPackMeta.fromJson(m);
      if (!kEmojiPackIdPattern.hasMatch(pack.id)) {
        throw FormatException('invalid emoji pack id: ${pack.id}');
      }
      if (!seen.add(pack.id)) {
        throw FormatException('duplicate emoji pack id: ${pack.id}');
      }
      out.add(pack);
    }
    return out;
  }
}
