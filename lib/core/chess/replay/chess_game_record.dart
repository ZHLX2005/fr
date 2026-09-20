// lib/core/chess/replay/chess_game_record.dart
//
// 整局对局记录（模型 + 解析）—— 回放"保存整局"的持久化单元。
//
// 一个记录 = 一个 JSON 文件 = 一整局棋：
//   initialFen（起始局面，含残局房间的 initial_fen）+ uciMoves（整局 UCI 谱）
//   + 终局元数据。回放页用 ChessGameReplayResolver 从这两项重演全部快照。
//
// 文件格式（fr-chess-game v1）：
// {
//   "format": "fr-chess-game",
//   "version": 1,
//   "id": "game-123456-1758285594000",
//   "title": "对局 09-19 23:19",
//   "initialFen": "rnbqkbnr/... w KQkq - 0 1",   // 标准开局房间也显式落盘
//   "uciMoves": ["e2e4", "e7e5", ...],            // 整局谱（防御截断在重演层）
//   "status": "checkmate",                        // 终局状态（playing 不应出现）
//   "roomCode": "123456",                         // 来源房间（追溯用，可空）
//   "savedAt": "2026-09-19T23:19:54Z"
// }
//
// 校验规则（tryParse 全防御，任何失败返回 null 不抛异常）：
//   · format / version / id / title / initialFen / uciMoves 必填且合法
//   · initialFen 必须能被 FenCodec.fromFen 解析
//   · uciMoves 每项 4-5 位（宽松；严格校验在重演层）

import 'dart:convert';

import '../engine/fen_codec.dart';

/// 格式标识（文件级；解析时必须匹配）。
const String kChessGameFormatTag = 'fr-chess-game';

/// 当前格式版本。
const int kChessGameVersion = 1;

/// 本地文件扩展名（可识别 + 仍是 json）。
const String kChessGameFileExt = '.chessgame.json';

/// 终局状态 → 中文徽标文案（列表页 / 回放页 AppBar 共用）。
///
/// 输入为房间快照 context['status'] 的原始值；
/// playing/check 等非终局值回退为空串（不显示徽标）。
String chessGameStatusLabel(String? status) => switch (status) {
      'checkmate' => '将杀',
      'stalemate' => '僵局',
      'resigned' => '认输',
      'draw' => '和棋',
      _ => '',
    };

/// 整局对局记录。
class ChessGameRecord {
  /// 唯一 id（保存时生成：game-<房间号>-<毫秒时间戳>）。
  final String id;

  /// 展示标题（如 "对局 09-19 23:19" / "残局·XXX 对局"）。
  final String title;

  /// 起始局面 FEN（残局房间为残局局面；标准房间为标准开局 FEN）。
  final String initialFen;

  /// 整局 UCI 谱（每项 4-5 位，如 e2e4 / e7e8q）。
  final List<String> uciMoves;

  /// 终局状态原始值（checkmate/stalemate/resigned/draw；展示用
  /// [chessGameStatusLabel] 映射）。
  final String status;

  /// 来源房间号（追溯用，可空）。
  final String? roomCode;

  /// 保存时间（ISO8601 UTC）。
  final String savedAt;

  const ChessGameRecord({
    required this.id,
    required this.title,
    required this.initialFen,
    required this.uciMoves,
    this.status = '',
    this.roomCode,
    required this.savedAt,
  });

  int get moveCount => uciMoves.length;

  Map<String, dynamic> toJson() => {
        'format': kChessGameFormatTag,
        'version': kChessGameVersion,
        'id': id,
        'title': title,
        'initialFen': initialFen,
        'uciMoves': uciMoves,
        if (status.isNotEmpty) 'status': status,
        if (roomCode != null && roomCode!.isNotEmpty) 'roomCode': roomCode,
        'savedAt': savedAt,
      };

  String encode() => jsonEncode(toJson());

  /// 内容指纹（保存幂等查重：同起始局面 + 同整谱 = 同一局）。
  String contentKey() => '$initialFen\n${uciMoves.join(' ')}';

  /// 防御解析（null = 非法）。
  static ChessGameRecord? tryParse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['format'] != kChessGameFormatTag) return null;
    if (decoded['version'] != kChessGameVersion) return null;
    final id = decoded['id']?.toString() ?? '';
    final title = decoded['title']?.toString() ?? '';
    final initialFen = decoded['initialFen']?.toString() ?? '';
    if (id.isEmpty || title.isEmpty || initialFen.isEmpty) return null;

    // FEN 可解析性校验（残局 / 标准开局统一走引擎编解码）。
    try {
      FenCodec.fromFen(initialFen);
    } on Object {
      return null;
    }

    final rawMoves = decoded['uciMoves'];
    if (rawMoves is! List) return null;
    final moves = <String>[];
    for (final m in rawMoves) {
      final uci = m?.toString() ?? '';
      // 宽松校验：4-5 位（严格合法性与局面匹配在重演层防御截断）。
      if (uci.length < 4 || uci.length > 5) return null;
      moves.add(uci);
    }

    return ChessGameRecord(
      id: id,
      title: title,
      initialFen: initialFen,
      uciMoves: moves,
      status: decoded['status']?.toString() ?? '',
      roomCode: decoded['roomCode']?.toString(),
      savedAt: decoded['savedAt']?.toString() ?? '',
    );
  }
}
