// lib/core/xiangqi/engine/fen_codec.dart
//
// 中国象棋 FEN 编解码。
//
// 格式（中国象棋通用 / ICPC 风格）：
//
//   <局面> <轮次> <占位> <占位> <半回合数> <回合数>
//
//   · 局面：10 段用 '/' 分隔（自上而下 row 0 → row 9），
//     每段 9 格；数字 = 连续空格数；字母 = 棋子。
//     大写 = 红，小写 = 黑：
//       K 将/帅 · A 士 · B 象/相 · N 马 · R 车 · C 炮 · P 卒/兵
//   · 轮次：'r' = 红方走（红先），'b' = 黑方走。
//   · 两个占位段：象棋没有易位 / 吃过路兵，固定写 '-'。
//   · 两个计数：半回合数（自上次吃子）与回合数 —— 本项目只做展示，不参与规则。
//
// 例：`rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1`
//
// 与国际象棋 FEN 的差异：
//   · 没有 en-passant 目标格、没有 castling 权（两个 '-' 占位）。
//   · 没有 promotion 标记（无升变）。
//   · 棋种字母用 A/B/C/N/P/R/K（国际象棋是 K/Q/R/B/N/P）。

import '../constants/xiangqi_constants.dart';
import '../models/board_state.dart';
import '../models/piece.dart';

/// FEN 棋种字母 → 棋种。
const Map<String, XiangqiPieceType> _typeByChar = {
  'K': XiangqiPieceType.general,
  'A': XiangqiPieceType.advisor,
  'B': XiangqiPieceType.elephant,
  'N': XiangqiPieceType.horse,
  'R': XiangqiPieceType.chariot,
  'C': XiangqiPieceType.cannon,
  'P': XiangqiPieceType.pawn,
};

/// 该字符是否是 FEN 中的"连续空格"数字（'1'..'9'）。
bool _isDigitChar(String ch) {
  final code = ch.codeUnitAt(0);
  return code >= 0x31 && code <= 0x39;
}

/// 该字符的数值（'1'..'9' → 1..9）。
int _digitValue(String ch) => ch.codeUnitAt(0) - 0x30;

/// 该字符是否是合法棋子字母。
bool _isPieceChar(String ch) => 'KABNRCPkabnrcp'.contains(ch);

/// 局面部分（不含轮次与计数）—— 例如
/// `rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR`。
String xiangqiPositionToFen(XiangqiBoardState board) {
  final rows = <String>[];
  for (var row = 0; row < kXiangqiRows; row++) {
    final buf = StringBuffer();
    var empty = 0;
    for (var col = 0; col < kXiangqiCols; col++) {
      final piece = board.pieceAt(xiangqiIndex(row, col));
      if (piece == null) {
        empty++;
        continue;
      }
      if (empty > 0) {
        buf.write(empty);
        empty = 0;
      }
      buf.write(piece.fenChar);
    }
    if (empty > 0) buf.write(empty);
    rows.add(buf.toString());
  }
  return rows.join('/');
}

/// 完整 FEN（含轮次与计数）。
String fenFromBoardState(
  XiangqiBoardState board, {
  int halfMoveClock = 0,
  int fullMoveNumber = 1,
}) {
  final turn = board.sideToMove == XiangqiColor.red ? 'r' : 'b';
  return '${xiangqiPositionToFen(board)} $turn - - $halfMoveClock $fullMoveNumber';
}

/// 从 FEN 解析棋盘状态。
///
/// 非法 FEN 抛 [FormatException]（轮次字段必须是 'r' / 'b' —— 其它值
/// 不能静默当成红方，否则会与服务端判反）。
XiangqiBoardState boardStateFromFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) throw FormatException('empty FEN: $fen');
  final position = parts[0];
  final turn = parts.length > 1 ? parts[1] : 'r';
  if (turn != 'r' && turn != 'b') {
    throw FormatException("unknown turn field '$turn' (expect 'r' / 'b')");
  }

  final rows = position.split('/');
  if (rows.length != kXiangqiRows) {
    throw FormatException('expected $kXiangqiRows ranks, got ${rows.length}');
  }

  final cells = List<int?>.filled(kXiangqiCells, null, growable: false);
  for (var row = 0; row < kXiangqiRows; row++) {
    var col = 0;
    for (final ch in rows[row].split('')) {
      if (_isDigitChar(ch)) {
        col += _digitValue(ch);
        continue;
      }
      final type = _typeByChar[ch.toUpperCase()];
      if (type == null) throw FormatException('unknown piece char: $ch');
      if (col >= kXiangqiCols) {
        throw FormatException('rank $row overflows $kXiangqiCols columns');
      }
      final color =
          ch == ch.toUpperCase() ? XiangqiColor.red : XiangqiColor.black;
      cells[xiangqiIndex(row, col)] = XiangqiPiece(color, type).pack();
      col++;
    }
    if (col != kXiangqiCols) {
      throw FormatException('rank $row has $col columns, expected $kXiangqiCols');
    }
  }

  final side = turn == 'b' ? XiangqiColor.black : XiangqiColor.red;
  return XiangqiBoardState(cells: cells, sideToMove: side);
}

/// 每方棋子数上限（用于局面合法性校验）。
///
/// 合法对局中数量只减不增 —— 中局 FEN 里兵可能只剩 3 个，所以是**上限**
/// 而非定值；「开局必须是满编」由 `initial_fen` 的入口另行校验。
const Map<String, int> kXiangqiPieceCountCaps = {
  'K': 1, // 将 / 帅
  'A': 2, // 士
  'B': 2, // 象 / 相
  'N': 2, // 马
  'R': 2, // 车
  'C': 2, // 炮
  'P': 5, // 卒 / 兵
};

/// 局面串里的棋子计数。
///
/// **key 保留原始大小写**（大写 = 红，小写 = 黑）—— 数量上限是**每方**的，
/// 合并统计会把双方加到一起（红将 1 + 黑将 1 = 2 > 上限 1）→ 误判非法。
Map<String, int> xiangqiPieceCounts(String position) {
  final counts = <String, int>{};
  for (final ch in position.split('')) {
    if (!'KABNRCPkabnrcp'.contains(ch)) continue;
    counts[ch] = (counts[ch] ?? 0) + 1;
  }
  return counts;
}

/// 局面合法性（不含轮次字段）。
///
/// 合法对局必然满足：
///   · 双方各恰好一个将 / 帅，且都在自己九宫内；
///   · 各类棋子数量不超过上限（士/象/马/车/炮 各 ≤ 2，卒/兵 ≤ 5）；
///   · 双将不同列相望（中间无子）—— 「将帅照面」是非法局面。
///
/// 用途：校验 `initial_fen` / 自定义开局，杜绝「缺将」之类的畸形局面
/// （缺将 → 引擎立刻判 noGeneral → 终局秒判负）。
bool isLegalXiangqiPosition(XiangqiBoardState board) {
  // 各棋种数量上限（**每方**：大写 = 红，小写 = 黑，分别比）
  final counts = <String, int>{};
  for (final (_, piece) in board.occupied) {
    final ch = piece.fenChar;
    counts[ch] = (counts[ch] ?? 0) + 1;
  }
  for (final entry in kXiangqiPieceCountCaps.entries) {
    final upper = counts[entry.key] ?? 0;
    final lower = counts[entry.key.toLowerCase()] ?? 0;
    if (upper > entry.value || lower > entry.value) return false;
  }

  // 双方各恰好一个将，且在各自九宫
  final redGeneral = board.generalSquareOf(XiangqiColor.red);
  final blackGeneral = board.generalSquareOf(XiangqiColor.black);
  if (redGeneral < 0 || blackGeneral < 0) return false;
  if (!xiangqiInPalaceOf(xiangqiRowOf(redGeneral), xiangqiColOf(redGeneral),
      isRed: true)) {
    return false;
  }
  if (!xiangqiInPalaceOf(xiangqiRowOf(blackGeneral), xiangqiColOf(blackGeneral),
      isRed: false)) {
    return false;
  }

  // 将帅照面：同列且中间无子 → 非法
  if (xiangqiGeneralsFaceEachOther(board)) return false;

  return true;
}

/// 双将是否同列相望（中间无子）—— 非法局面。
bool xiangqiGeneralsFaceEachOther(XiangqiBoardState board) {
  final red = board.generalSquareOf(XiangqiColor.red);
  final black = board.generalSquareOf(XiangqiColor.black);
  if (red < 0 || black < 0) return false;
  final rc = xiangqiColOf(red);
  final bc = xiangqiColOf(black);
  if (rc != bc) return false;
  final r1 = xiangqiRowOf(red);
  final r2 = xiangqiRowOf(black);
  final from = r1 < r2 ? r1 : r2;
  final to = r1 < r2 ? r2 : r1;
  for (var r = from + 1; r < to; r++) {
    if (!board.isEmpty(xiangqiIndex(r, rc))) return false;
  }
  return true;
}

/// FEN 结构校验（服务端 Lua 侧做同类校验）。
///
/// 结构：10 段局面（每段宽 9）+ 轮次 'r' / 'b'；
/// 另附**棋子数量与将帅存在性**校验（与 Lua `is_valid_xiangqi_fen` 同表）——
/// 杜绝「黑方无将」这类畸形局面被当作开局接受（会立刻触发 noGeneral 终局）。
bool isValidXiangqiFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return false;
  if (parts[1] != 'r' && parts[1] != 'b') return false;
  final rows = parts[0].split('/');
  if (rows.length != kXiangqiRows) return false;
  for (final row in rows) {
    var width = 0;
    for (final ch in row.split('')) {
      if (_isDigitChar(ch)) {
        width += _digitValue(ch);
      } else if (_isPieceChar(ch)) {
        width += 1;
      } else {
        return false;
      }
    }
    if (width != kXiangqiCols) return false;
  }
  // 双方各恰好一个将；各类棋子数量不超上限
  final counts = xiangqiPieceCounts(parts[0]);
  if ((counts['K'] ?? 0) != 1 || (counts['k'] ?? 0) != 1) return false;
  for (final entry in kXiangqiPieceCountCaps.entries) {
    // 上下限是**每方**的：大写 = 红、小写 = 黑，必须分别比。
    final upper = counts[entry.key] ?? 0;
    final lower = counts[entry.key.toLowerCase()] ?? 0;
    if (upper > entry.value || lower > entry.value) return false;
  }
  return true;
}
