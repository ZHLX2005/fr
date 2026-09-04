// lib/core/game_kit/skin/game_skin_meta.dart
//
// Generic skin metadata — FileRef + GameSkinMeta (extracted from
// lib/core/chess/skins/chess_skin_meta.dart). Chess re-exports this.

import 'dart:convert';

/// 单张资源远端引用（generic；chess 的 wK/bp、gomoku 的 black/white 都用它）.
class FileRef {
  /// 32-char hex 字符串，对应 server 后端的 MD5 风格 file id。
  final String fileId;

  /// 原始文件名（debug / file list 显示用）。
  final String fileName;

  /// 字节数（客户端 cache key 校验）。
  final int sizeBytes;

  /// MIME（`image/webp` / `image/png` / `application/octet-stream`）。
  final String contentType;

  const FileRef({
    required this.fileId,
    required this.fileName,
    required this.sizeBytes,
    required this.contentType,
  });

  Map<String, dynamic> toJson() => {
        'fileId': fileId,
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'contentType': contentType,
      };

  factory FileRef.fromJson(Map<String, dynamic> j) => FileRef(
        fileId: j['fileId'] as String,
        fileName: j['fileName'] as String,
        sizeBytes: (j['sizeBytes'] as num).toInt(),
        contentType: j['contentType'] as String,
      );

  @override
  bool operator ==(Object other) =>
      other is FileRef &&
      fileId == other.fileId &&
      fileName == other.fileName &&
      sizeBytes == other.sizeBytes &&
      contentType == other.contentType;

  @override
  int get hashCode => Object.hash(fileId, fileName, sizeBytes, contentType);
}

/// skin id 正则（kebab-case 数字/小写字母/横线）
final RegExp kGameSkinIdPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,31}$');

/// 一套皮肤的 metadata（generic value 类型）.
///
/// 字段与 ChessSkinMeta 1:1，`pieces` 是通用资产 map（chess 放 12 keys，
/// gomoku 放 black/white）。`boardBackground` 可选，语义各游戏相同。
class GameSkinMeta {
  /// 唯一 skin id（如 `staunty`、`classic-wood`、`1`、`2`...）。
  final String id;

  /// UI 显示名（i18n 留给上层翻译）。
  final String displayName;

  /// 资产的资源引用（key 由 [GameSkinSpec.assetKeys] 定义）。
  ///
  /// 命名保留 `pieces` 作兼容（chess 现有代码大量使用 meta.pieces）；
  /// gomoku 也复用该字段（black/white）。
  final Map<String, FileRef> pieces;

  /// 棋盘底图（可选）。null 时 UI 走默认主题/BoardPalette。
  final FileRef? boardBackground;

  /// 作者署名（可空）
  final String? author;

  /// 描述（可空）
  final String? description;

  /// 单调递增版本号，UI 不强制校验
  final int version;

  /// 颜色风格：`warm`/`cool`/`mono`/`vivid`（可空）
  final String? colorStyle;

  /// ISO 8601（可空）
  final String? createdAt;

  /// ISO 8601（可空）
  final String? updatedAt;

  const GameSkinMeta({
    required this.id,
    required this.displayName,
    required this.pieces,
    this.boardBackground,
    this.author,
    this.description,
    this.version = 1,
    this.colorStyle,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        if (author != null) 'author': author,
        if (description != null) 'description': description,
        'version': version,
        if (colorStyle != null) 'colorStyle': colorStyle,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (boardBackground != null) 'boardBackground': boardBackground!.toJson(),
        'pieces': {
          for (final entry in pieces.entries)
            entry.key: entry.value.toJson(),
        },
      };

  factory GameSkinMeta.fromJson(Map<String, dynamic> j) {
    final rawPieces = j['pieces'] as Map<String, dynamic>;
    final pieces = <String, FileRef>{
      for (final entry in rawPieces.entries)
        entry.key: FileRef.fromJson(entry.value as Map<String, dynamic>),
    };
    return GameSkinMeta(
      id: j['id'] as String,
      displayName: j['displayName'] as String,
      pieces: pieces,
      boardBackground: j['boardBackground'] != null
          ? FileRef.fromJson(j['boardBackground'] as Map<String, dynamic>)
          : null,
      author: j['author'] as String?,
      description: j['description'] as String?,
      version: (j['version'] as num?)?.toInt() ?? 1,
      colorStyle: j['colorStyle'] as String?,
      createdAt: j['createdAt'] as String?,
      updatedAt: j['updatedAt'] as String?,
    );
  }

  /// 解析 [jsonText]（一个 JSON array）成 [List<GameSkinMeta>]。
  ///
  /// 错误：duplicate id 抛 [FormatException]；id 不符合正则抛 [FormatException]。
  static List<GameSkinMeta> parseList(String jsonText) {
    final raw = jsonDecode(jsonText);
    if (raw is! List) throw const FormatException('expected JSON array');
    final seen = <String>{};
    final out = <GameSkinMeta>[];
    for (final e in raw) {
      if (e is! Map<String, dynamic>) {
        throw const FormatException('expected object in array');
      }
      final s = GameSkinMeta.fromJson(e);
      if (!kGameSkinIdPattern.hasMatch(s.id)) {
        throw FormatException('invalid skin id: ${s.id}');
      }
      if (!seen.add(s.id)) {
        throw FormatException('duplicate skin id: ${s.id}');
      }
      out.add(s);
    }
    return out;
  }
}

/// 通用完整性：按给定 [assetKeys] 判断（便于 per-game spec 校验）.
extension GameSkinMetaCheck on GameSkinMeta {
  bool isCompleteFor(Set<String> assetKeys) {
    if (pieces.length != assetKeys.length) return false;
    for (final k in assetKeys) {
      if (!pieces.containsKey(k)) return false;
    }
    return true;
  }
}
