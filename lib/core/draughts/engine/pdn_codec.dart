// lib/core/draughts/engine/pdn_codec.dart
//
// 国际跳棋 FEN / PDN 编解码。
//
// ## FEN（draughts.js / draughtsboardJS 兼容）
//
//   `W:W31-50:B1-20`
//     · 第 1 段 = 轮次方（W/B）
//     · 第 2 段 = 白方棋子列表（段首字母 W=白）；第 3 段 = 黑方
//     · 列表内：`K` 前缀 = 王；`a-b` = 连续区间；`,` 分隔。如 `WK31,32-35`
//   起点 = `W:W31-50:B1-20`（白先，各 20 兵）。
//
// ## PDN（Portable Draughts Notation，PDN 3.0）
//
//   走子 `32-28`；吃子 `32x23`；多跳 `32x23x14`。数字是方格号 1..50。
//
// 本文件只做「格式 ↔ 内部 (row,col) 索引」换算；几何计算一律在 move_generator。

import '../constants/draughts_constants.dart';
import '../models/board_state.dart';
import '../models/move.dart';
import '../models/piece.dart';

/// 解析 FEN 成棋盘状态。非法输入抛 [FormatException]。
DraughtsBoardState boardStateFromFen(String fen) {
  final trimmed = fen.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Empty FEN');
  }

  final cells = List<int?>.filled(kDraughtsCells, null, growable: false);

  final parts = trimmed.split(':');
  if (parts.length == 1) {
    // pydraughts "hub fen"：`W` + 50 字符（每字符 e/w/b/W/B）
    final hubSide = _parseHubFen(trimmed, cells);
    return DraughtsBoardState(cells: cells, sideToMove: hubSide);
  }
  if (parts.length < 3) {
    throw FormatException('Malformed FEN (need turn:W…:B…): $fen');
  }

  final turnChar = parts[0].toUpperCase();
  final sideToMove =
      turnChar == 'B' ? DraughtsColor.black : DraughtsColor.white;

  _parseSideList(parts[1], cells);
  _parseSideList(parts[2], cells);

  return DraughtsBoardState(cells: cells, sideToMove: sideToMove);
}

/// 生成 FEN 字符串（区间压缩，尽量贴近起点写法）。
String fenFromBoardState(DraughtsBoardState state) {
  final turn = state.sideToMove == DraughtsColor.black ? 'B' : 'W';
  final white = <int>[];
  final whiteKings = <int>[];
  final black = <int>[];
  final blackKings = <int>[];

  for (final (idx, piece) in state.occupied) {
    final n = draughtsSquareNumberOfIndex(idx);
    if (n < 0) continue;
    if (piece.isWhite) {
      (piece.isKing ? whiteKings : white).add(n);
    } else {
      (piece.isKing ? blackKings : black).add(n);
    }
  }

  final buf = StringBuffer(turn);
  buf.write(':');
  buf.write('W');
  buf.write(_encodeSide(white, whiteKings));
  buf.write(':');
  buf.write('B');
  buf.write(_encodeSide(black, blackKings));
  return buf.toString();
}

/// 解析 PDN 着法到 [DraughtsMove]（需要 [state] 定位被吃子）。
///
/// 非法 / 不合法返回 null。
DraughtsMove? pdnMoveToMove(DraughtsBoardState state, String pdn) {
  final text = pdn.trim();
  if (text.isEmpty) return null;
  final isCapture = text.contains('x') || text.contains('X');
  final sep = isCapture ? RegExp('[xX]') : RegExp('-');
  final tokens = text.split(sep);
  if (tokens.length < 2) return null;

  final indices = <int>[];
  for (final tok in tokens) {
    final n = int.tryParse(tok.trim());
    if (n == null) return null;
    final idx = draughtsIndexFromSquareNumber(n);
    if (idx < 0) return null;
    indices.add(idx);
  }

  final from = indices.first;
  final to = indices.last;
  final piece = state.pieceAt(from);
  if (piece == null) return null;

  final capturedSquares = <int>[];
  if (isCapture) {
    for (var i = 0; i + 1 < indices.length; i++) {
      final mid = _capturedOnRay(
        state,
        indices[i],
        indices[i + 1],
        piece.color,
        alreadyCaptured: capturedSquares,
      );
      if (mid == null) return null;
      capturedSquares.add(mid);
    }
  }

  return DraughtsMove(
    from: from,
    to: to,
    path: indices,
    capturedSquares: capturedSquares,
    isPromotion: !piece.isKing &&
        draughtsRowOf(to) == draughtsPromotionRowFor(piece.isWhite),
  );
}

// ─────────────────────────── 内部 helper ───────────────────────────

void _parseSideList(String segment, List<int?> cells) {
  if (segment.isEmpty) return;
  final colorChar = segment[0].toUpperCase();
  final isWhite = colorChar == 'W';
  final body = segment.substring(1);
  if (body.isEmpty) return;

  for (final part in body.split(',')) {
    final token = part.trim();
    if (token.isEmpty) continue;

    if (token.contains('-')) {
      // 支持 `31-35`（兵）与 `K31-33` / `K31-K33`（王区间）
      final rp = token.split('-');
      if (rp.length != 2) continue;
      var startTok = rp[0];
      var endTok = rp[1];
      var isKing = false;
      if (startTok.startsWith('K') || startTok.startsWith('k')) {
        isKing = true;
        startTok = startTok.substring(1);
      }
      if (endTok.startsWith('K') || endTok.startsWith('k')) {
        isKing = true;
        endTok = endTok.substring(1);
      }
      final start = int.tryParse(startTok);
      final end = int.tryParse(endTok);
      if (start == null || end == null) continue;
      for (var n = start; n <= end; n++) {
        _placeSquare(cells, n, isWhite, isKing: isKing);
      }
    } else if (token.startsWith('K') || token.startsWith('k')) {
      final n = int.tryParse(token.substring(1));
      if (n != null) _placeSquare(cells, n, isWhite, isKing: true);
    } else {
      final n = int.tryParse(token);
      if (n != null) _placeSquare(cells, n, isWhite, isKing: false);
    }
  }
}

/// 解析 pydraughts hub fen（`W` + 50 字符，每字符 e/w/b/W/B），返回轮次方。
DraughtsColor _parseHubFen(String hub, List<int?> cells) {
  var body = hub;
  var sideToMove = DraughtsColor.white;
  final first = hub[0].toUpperCase();
  if (first == 'W' || first == 'B') {
    sideToMove = first == 'B' ? DraughtsColor.black : DraughtsColor.white;
    body = hub.substring(1);
  }
  for (var i = 0; i < body.length && i < kDraughtsPlayableSquares; i++) {
    final ch = body[i];
    if (ch == 'e' || ch == 'E') continue;
    final isWhite = ch == 'w' || ch == 'W';
    final isKing = ch == 'W' || ch == 'B';
    _placeSquare(cells, i + 1, isWhite, isKing: isKing);
  }
  return sideToMove;
}

void _placeSquare(List<int?> cells, int square, bool isWhite, {required bool isKing}) {
  final idx = draughtsIndexFromSquareNumber(square);
  if (idx < 0) return;
  cells[idx] = DraughtsPiece(isWhite ? DraughtsColor.white : DraughtsColor.black,
          isKing: isKing)
      .pack();
}

String _encodeSide(List<int> men, List<int> kings) {
  final tokens = <String>[];
  tokens.addAll(_compress(men, isKing: false));
  tokens.addAll(_compress(kings, isKing: true));
  return tokens.join(',');
}

/// 把方格号列表压成 `K?a-b` / `a` 记号（连续 ≥3 压成区间）。
List<String> _compress(List<int> squares, {required bool isKing}) {
  if (squares.isEmpty) return const [];
  final sorted = List<int>.of(squares)..sort();
  final out = <String>[];
  var runStart = sorted[0];
  var prev = sorted[0];

  void flushRun(int start, int end) {
    final prefix = isKing ? 'K' : '';
    if (end - start >= 2) {
      out.add('$prefix$start-$end');
    } else {
      for (var n = start; n <= end; n++) {
        out.add('$prefix$n');
      }
    }
  }

  for (var i = 1; i < sorted.length; i++) {
    final n = sorted[i];
    if (n == prev + 1) {
      prev = n;
      continue;
    }
    flushRun(runStart, prev);
    runStart = n;
    prev = n;
  }
  flushRun(runStart, prev);
  return out;
}

/// 吃子 hop `a → b` 上被跳过的那一格。
///
/// 同斜线、至少隔 1 格；射线中间**恰好一枚**敌子（兵距离 2 / flying king 任意距离）。
/// [alreadyCaptured] 里的格仍占位但不算新吃 —— 再撞到则非法。
int? _capturedOnRay(
  DraughtsBoardState state,
  int a,
  int b,
  DraughtsColor mover, {
  List<int> alreadyCaptured = const [],
}) {
  final ar = draughtsRowOf(a);
  final ac = draughtsColOf(a);
  final br = draughtsRowOf(b);
  final bc = draughtsColOf(b);
  final dr = br - ar;
  final dc = bc - ac;
  if (dr == 0 || dr.abs() != dc.abs()) return null;
  final dist = dr.abs();
  if (dist < 2) return null;

  final stepR = dr.sign;
  final stepC = dc.sign;
  int? found;
  for (var i = 1; i < dist; i++) {
    final idx = draughtsIndex(ar + stepR * i, ac + stepC * i);
    final p = state.pieceAt(idx);
    if (p == null) continue;
    if (alreadyCaptured.contains(idx)) return null; // 同子不可再跳
    if (p.color == mover) return null; // 己方阻挡
    if (found != null) return null; // 中间多于一子
    found = idx;
  }
  return found;
}
