// lib/core/gomoku/skins/gomoku_skin_meta.dart
//
// 五子棋皮肤 metadata + hardcode catalog（对齐 chess 的 FileRef/kCatalog 模式，
// 但压缩为 3-key：black / white / board）。
//
// 与 plan/game-kit-unification.md §Naming Convention 对齐：
//   KV key:   gomoku_skin:index
//   KV tag:   gomoku-skin
//   file key: gomoku/<skinId>/<assetKey>  e.g. gomoku/1/black
//
// 命名来源：lib/core/game_kit/skin/game_skin_spec.dart 派生规则。

import 'dart:convert';

import '../../chess/skins/chess_skin_meta.dart' show FileRef;

/// 3 个 asset key（black=黑子, white=白子, board=棋盘底图）
///
/// board 可选（catalog 中缺失/为 null 时 UI 走 BoardColorStrategy.background）。
const Set<String> kGomokuAssetKeys = {
  'black',
  'white',
  'board',
};

/// 2 颗棋子 key 子集（black + white），board 排除在外。
const Set<String> kGomokuStoneKeys = {
  'black',
  'white',
};

final RegExp kGomokuSkinIdPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,31}$');

/// 一套五子棋皮肤的 metadata（immutable value；与 ChessSkinMeta 解耦）。
class GomokuSkinMeta {
  final String id;
  final String displayName;
  /// assetKey → FileRef（需含 black/white；board 可选）
  final Map<String, FileRef> assets;
  final String? author;
  final String? description;
  final int version;
  final String? createdAt;
  final String? updatedAt;

  const GomokuSkinMeta({
    required this.id,
    required this.displayName,
    required this.assets,
    this.author,
    this.description,
    this.version = 1,
    this.createdAt,
    this.updatedAt,
  });

  /// board 底图（assets['board'] 的别名，null 时走主题棋盘色）
  FileRef? get boardBackground => assets['board'];

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        if (author != null) 'author': author,
        if (description != null) 'description': description,
        'version': version,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
        'assets': {
          for (final e in assets.entries) e.key: e.value.toJson(),
        },
      };

  factory GomokuSkinMeta.fromJson(Map<String, dynamic> j) {
    final raw = j['assets'] as Map<String, dynamic>;
    final assets = <String, FileRef>{
      for (final e in raw.entries)
        e.key: FileRef.fromJson(e.value as Map<String, dynamic>),
    };
    return GomokuSkinMeta(
      id: j['id'] as String,
      displayName: j['displayName'] as String,
      assets: assets,
      author: j['author'] as String?,
      description: j['description'] as String?,
      version: (j['version'] as num?)?.toInt() ?? 1,
      createdAt: j['createdAt'] as String?,
      updatedAt: j['updatedAt'] as String?,
    );
  }

  static List<GomokuSkinMeta> parseList(String jsonText) {
    final raw = jsonDecode(jsonText);
    if (raw is! List) throw const FormatException('expected JSON array');
    final seen = <String>{};
    final out = <GomokuSkinMeta>[];
    for (final e in raw) {
      if (e is! Map<String, dynamic>) {
        throw const FormatException('expected object in array');
      }
      final s = GomokuSkinMeta.fromJson(e);
      if (!kGomokuSkinIdPattern.hasMatch(s.id)) {
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

extension GomokuSkinMetaCheck on GomokuSkinMeta {
  /// 完整性：至少含 black + white 两颗棋子（board 可选）
  bool get isComplete =>
      assets.containsKey('black') && assets.containsKey('white');
}

/// 五子棋硬编码 catalog（当前为空，待上传首套贴图后填入）。
///
/// 与 chess 不同：gomoku v1 不预置 7 套假数据，先以空 catalog 跑通
/// "本地 catalog → KV 覆盖追加 → 本地文件/网络渲染"链路（见
/// lib/core/chess/skins/chess_skin_meta_sync.dart 同款流程）。
///
/// 占位写法：保持 const 语义，Dart 允许 const []（空）作 catalog baseline；
/// KV 拉取路径将用 register 覆盖追加。
const List<GomokuSkinMeta> kGomokuSkinsCatalog = <GomokuSkinMeta>[];
