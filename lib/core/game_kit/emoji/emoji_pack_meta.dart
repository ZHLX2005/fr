// lib/core/game_kit/emoji/emoji_pack_meta.dart
//
// Emoji pack metadata — KV schema for emoji_<scope>:index (group 190).
//
// KV 约定（见 Track B 指令）：
//   key:   emoji_<scope>:index   e.g. emoji_common:index / emoji_chess:index
//   group: 190                   (复用 PublicKvReader.kPublicGroupId)
//   tag:   <scope>-emoji         e.g. common-emoji / chess-emoji
//
// Value 形如 JSON array：
//   [{ id, displayName, emojis: { <emojiId>: FileRef, ... } }, ...]
// 但为兼容历史／管理后台，`emojis` 字段同时接受：
//   1) Map<emojiId, FileRef>  — 规范形式
//   2) Array — 每项为 { id, ...FileRef } 或 { id, file: FileRef }
//
// 复用 [FileRef]（lib/core/game_kit/skin/game_skin_meta.dart）作为远端文件引用。

import 'dart:convert';

import '../skin/game_skin_meta.dart' show FileRef;

/// emoji pack id 正则（与 skin 一致：kebab-case）。
final RegExp kEmojiPackIdPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,31}$');

/// emoji id 正则（单个表情的 id，如 thumbs-up / heart）。
final RegExp kEmojiIdPattern = RegExp(r'^[a-z0-9][a-z0-9-_]{0,31}$');

/// 单个表情资产（id + 远端文件引用）。
///
/// 与 [FileRef] 解耦一层：上层拼 URL 时走 [FileResolver]；
/// 本地缓存校验走 [FileRef.fileId]。
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
/// [emojis] 为 id → [FileRef] 的扁平映射（便于 bundle 合并与 fileId 校验）。
/// 序列化时固定写成 Map 形式；反序列化同时接受 Map 与 Array。
class EmojiPackMeta {
  final String id;
  final String displayName;
  final Map<String, FileRef> emojis;

  /// 可选：作者／描述／版本（与 skin 对齐，非必须）。
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

  /// KV index key：`emoji_$scope:index`
  static String kvIndexKeyForScope(String scope) => 'emoji_$scope:index';

  /// KV tag：`$scope-emoji`
  static String kvTagForScope(String scope) => '$scope-emoji';

  static const int kGroupId = 190;

  /// scope 列表：common 永远存在；game 为各游戏 id（如 chess / gomoku）。
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

  static Map<String, FileRef> _parseEmojis(dynamic raw) {
    final out = <String, FileRef>{};
    if (raw == null) return out;
    if (raw is Map) {
      // Map emojiId -> FileRefJson
      for (final entry in raw.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        if (v is! Map) continue;
        try {
          out[k] = FileRef.fromJson(Map<String, dynamic>.from(v as Map<String, dynamic>));
        } catch (_) {
          // 跳过非法项
        }
      }
      return out;
    }
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item as Map<String, dynamic>);
        final id = (m['id'] ?? m['emojiId'] ?? m['emoji_id'])?.toString();
        if (id == null || id.isEmpty) continue;
        if (!kEmojiIdPattern.hasMatch(id)) continue;
        Map<String, dynamic>? fileJson;
        if (m['file'] is Map) {
          fileJson = Map<String, dynamic>.from(m['file'] as Map<String, dynamic>);
        } else if (m['fileRef'] is Map) {
          fileJson = Map<String, dynamic>.from(m['fileRef'] as Map<String, dynamic>);
        } else if (m['ref'] is Map) {
          fileJson = Map<String, dynamic>.from(m['ref'] as Map<String, dynamic>);
        } else if (m.containsKey('fileId')) {
          fileJson = Map<String, dynamic>.from(m);
          fileJson.remove('id');
          fileJson.remove('emojiId');
          fileJson.remove('emoji_id');
          fileJson.remove('displayName');
          fileJson.remove('name');
        }
        if (fileJson == null) continue;
        if (!fileJson.containsKey('fileId')) continue;
        try {
          out[id] = FileRef.fromJson(fileJson);
        } catch (_) {}
      }
      return out;
    }
    return out;
  }

  /// 解析 JSON array 文本为 [List<EmojiPackMeta>]。
  ///
  /// 校验：id 正则、重复 id 抛 [FormatException]。
  static List<EmojiPackMeta> parseList(String jsonText) {
    final raw = jsonDecode(jsonText);
    if (raw is! List) throw const FormatException('expected JSON array');
    final seen = <String>{};
    final out = <EmojiPackMeta>[];
    for (final e in raw) {
      if (e is! Map<String, dynamic>) {
        // jsonDecode 可能给出 Map<dynamic,dynamic>
        if (e is! Map) throw const FormatException('expected object in array');
        final m = Map<String, dynamic>.from(e as Map<String, dynamic>);
        final pack = EmojiPackMeta.fromJson(m);
        if (!kEmojiPackIdPattern.hasMatch(pack.id)) {
          throw FormatException('invalid emoji pack id: ${pack.id}');
        }
        if (!seen.add(pack.id)) {
          throw FormatException('duplicate emoji pack id: ${pack.id}');
        }
        out.add(pack);
        continue;
      }
      final pack = EmojiPackMeta.fromJson(e);
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
