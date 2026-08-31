// lib/core/chess/endgame/chess_endgame.dart
//
// 残局快照标准化数据结构（模型 + 解析 + 校验）。
//
// 残局 = 一个 JSON 文件 = 一个 ChessEndgame，内含 1..N 个快照（snapshots），
// 每个快照 = 一个局面（FEN，国际象棋标准记法）+ 可选来源谱（lineage）。
//
// 文件格式（fr-chess-endgame v1）：
// {
//   "format": "fr-chess-endgame",
//   "version": 1,
//   "id": "eg-20260831-a1b2c3",
//   "title": "后单王杀（必填）",
//   "description": "可选说明",
//   "createdAt": "2026-08-31T12:00:00Z",
//   "source": "builtin | imported | replay",
//   "tags": ["杀王"],
//   "difficulty": 3,
//   "snapshots": [
//     {
//       "label": "终局前 2 手",
//       "fen": "8/8/8/4k3/8/8/4Q3/4K3 w - - 0 1",
//       "lineage": { "moves": ["e2e4", ...], "moveIndex": 35 }   // 可选
//     }
//   ]
// }
//
// 校验规则（tryParse 全防御，任何失败返回 null 不抛异常）：
//   · format / version / title / snapshots 必填且合法
//   · 每个 snapshot.fen 必须能被 FenCodec.fromFen 解析
//   · 双方各恰一王（残局语义）
//
// FEN 是唯一局面必需字段；lineage 仅回放导出时附带（开局不用它）。

import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../engine/fen_codec.dart';
import '../models/board_state.dart';
import '../models/piece.dart';

/// 格式标识（文件级；解析时必须匹配）。
const String kChessEndgameFormatTag = 'fr-chess-endgame';

/// 当前格式版本。
const int kChessEndgameVersion = 1;

/// 本地文件扩展名（可识别 + 仍是 json）。
const String kChessEndgameFileExt = '.chessendgame.json';

/// 残局来源。
enum ChessEndgameSource {
  builtin('内置'),
  imported('导入'),
  replay('回放');

  const ChessEndgameSource(this.label);
  final String label;

  static ChessEndgameSource fromName(String? name) =>
      ChessEndgameSource.values.firstWhere(
        (s) => s.name == name,
        orElse: () => ChessEndgameSource.imported,
      );
}

/// 单个残局快照：一个局面 + 可选来源谱。
class ChessEndgameSnapshot {
  /// 快照展示名（可空 —— 列表 UI 回退 "快照 N"）。
  final String? label;

  /// 局面（FEN 6 字段标准串）。唯一局面必需字段。
  final String fen;

  /// 来源谱（UCI 走子序列，到本局面为止）。仅回放导出时附带，可为空。
  final List<String> lineageMoves;

  /// 来源谱中本局面是第几手之后（0 = 初始局面）。
  final int lineageMoveIndex;

  const ChessEndgameSnapshot({
    this.label,
    required this.fen,
    this.lineageMoves = const [],
    this.lineageMoveIndex = 0,
  });

  Map<String, dynamic> toJson() => {
        'fen': fen,
        if (label != null && label!.isNotEmpty) 'label': label,
        if (lineageMoves.isNotEmpty)
          'lineage': {
            'moves': lineageMoves,
            'moveIndex': lineageMoveIndex,
          },
      };

  /// 防御解析（null = 非法）。
  static ChessEndgameSnapshot? tryParse(Map<String, dynamic> j) {
    final fen = j['fen']?.toString() ?? '';
    if (!ChessEndgame.isValidEndgameFen(fen)) return null;
    final lineage = j['lineage'];
    final moves = <String>[];
    var moveIndex = 0;
    if (lineage is Map) {
      final rawMoves = lineage['moves'];
      if (rawMoves is List) {
        for (final m in rawMoves) {
          final uci = m?.toString() ?? '';
          // 宽松校验：4-5 位字母数字（服务端/引擎会做严格校验）。
          if (uci.length < 4 || uci.length > 5) return null;
          moves.add(uci);
        }
      }
      moveIndex = (lineage['moveIndex'] as num?)?.toInt() ?? moves.length;
    }
    final label = j['label']?.toString();
    return ChessEndgameSnapshot(
      label: (label == null || label.isEmpty) ? null : label,
      fen: fen,
      lineageMoves: moves,
      lineageMoveIndex: moveIndex,
    );
  }
}

/// 一个残局文件（1..N 个快照）。
class ChessEndgame {
  final String format;
  final int version;
  final String id;
  final String title;
  final String description;
  final String createdAt;
  final ChessEndgameSource source;
  final List<String> tags;
  final int difficulty; // 1..5，0 = 未标注
  final List<ChessEndgameSnapshot> snapshots;

  const ChessEndgame({
    this.format = kChessEndgameFormatTag,
    this.version = kChessEndgameVersion,
    required this.id,
    required this.title,
    this.description = '',
    required this.createdAt,
    this.source = ChessEndgameSource.imported,
    this.tags = const [],
    this.difficulty = 0,
    required this.snapshots,
  });

  /// 生成新 id（eg-yyyymmdd-6hex）。
  static String generateId({DateTime? now}) {
    final t = now ?? DateTime.now();
    final ymd = '${t.year.toString().padLeft(4, '0')}'
        '${t.month.toString().padLeft(2, '0')}'
        '${t.day.toString().padLeft(2, '0')}';
    final hex = (t.microsecondsSinceEpoch & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    return 'eg-$ymd-$hex';
  }

  Map<String, dynamic> toJson() => {
        'format': format,
        'version': version,
        'id': id,
        'title': title,
        if (description.isNotEmpty) 'description': description,
        'createdAt': createdAt,
        'source': source.name,
        if (tags.isNotEmpty) 'tags': tags,
        if (difficulty > 0) 'difficulty': difficulty,
        'snapshots': snapshots.map((s) => s.toJson()).toList(),
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  // ─────────────────────────── 解析 + 校验 ───────────────────────────

  /// 全防御解析：任何结构 / 校验失败返回 null（不抛异常）。
  ///
  /// [source] 是加载侧上下文信息（builtin/imported/replay），不在文件内强制。
  static ChessEndgame? tryParse(String rawJson, {ChessEndgameSource? source}) {
    Map<String, dynamic> j;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return null;
      j = decoded;
    } catch (_) {
      return null;
    }
    return tryParseMap(j, source: source);
  }

  /// [tryParse] 的 Map 入口（store 直接拿解码后的 map 用）。
  static ChessEndgame? tryParseMap(
    Map<String, dynamic> j, {
    ChessEndgameSource? source,
  }) {
    // 1. 格式 + 版本
    if (j['format']?.toString() != kChessEndgameFormatTag) return null;
    final version = (j['version'] as num?)?.toInt() ?? -1;
    if (version < 1 || version > kChessEndgameVersion) return null;

    // 2. 必填字段
    final id = j['id']?.toString() ?? '';
    final title = j['title']?.toString() ?? '';
    if (id.isEmpty || title.isEmpty) return null;

    // 3. 快照列表（非空 + 每个快照合法）
    final rawSnaps = j['snapshots'];
    if (rawSnaps is! List || rawSnaps.isEmpty) return null;
    final snapshots = <ChessEndgameSnapshot>[];
    for (final s in rawSnaps) {
      if (s is! Map) return null;
      final snap =
          ChessEndgameSnapshot.tryParse(Map<String, dynamic>.from(s));
      if (snap == null) return null; // 一坏全坏：整文件拒绝（防半残残局）
      snapshots.add(snap);
    }

    // 4. 可选字段
    final createdAt = j['createdAt']?.toString() ??
        DateTime.now().toUtc().toIso8601String();
    final description = j['description']?.toString() ?? '';
    final tags = <String>[];
    final rawTags = j['tags'];
    if (rawTags is List) {
      for (final t in rawTags) {
        final v = t?.toString() ?? '';
        if (v.isNotEmpty) tags.add(v);
      }
    }
    final difficulty = (j['difficulty'] as num?)?.toInt() ?? 0;
    final src = source ??
        ChessEndgameSource.fromName(j['source']?.toString());

    return ChessEndgame(
      id: id,
      title: title,
      description: description,
      createdAt: createdAt,
      source: src,
      tags: tags,
      difficulty: difficulty.clamp(0, 5),
      snapshots: snapshots,
    );
  }

  // ─────────────────────────── FEN 校验 ───────────────────────────

  /// 残局局面合法性：FEN 可解析 + 双方各恰一王。
  ///
  /// 解析失败 / 王数不对 → false。这是残局语义的最低门槛
  /// （不校验将杀 / 僵局 —— 那些也是合法残局起点）。
  static bool isValidEndgameFen(String fen) {
    BoardState board;
    try {
      board = FenCodec.fromFen(fen);
    } on Object {
      return false;
    }
    var whiteKings = 0;
    var blackKings = 0;
    for (var i = 0; i < 64; i++) {
      if (board.pieceTypeAt(i) == PieceType.king) {
        if (board.pieceColorAt(i) == PieceColor.white) {
          whiteKings++;
        } else {
          blackKings++;
        }
      }
    }
    return whiteKings == 1 && blackKings == 1;
  }

  /// 从 FEN 读先手方（'w' / 'b'）。解析失败回退 'w'。
  static String sideFromFen(String fen) {
    try {
      return pieceColorToFenChar(FenCodec.fromFen(fen).sideToMove);
    } on Object {
      return 'w';
    }
  }

  /// 测试专用：构造一个合法残局（供 store / list 测试）。
  @visibleForTesting
  static ChessEndgame fixture({
    String? id,
    String title = '测试残局',
    ChessEndgameSource source = ChessEndgameSource.imported,
  }) =>
      ChessEndgame(
        id: id ?? generateId(),
        title: title,
        createdAt: '2026-08-31T00:00:00Z',
        source: source,
        snapshots: const [
          ChessEndgameSnapshot(
            label: '终局',
            fen: '8/8/8/4k3/8/8/4Q3/4K3 w - - 0 1',
          ),
        ],
      );
}
