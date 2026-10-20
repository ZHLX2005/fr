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
// 例：`rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1`
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
/// 非法 FEN 抛 [FormatException]。
XiangqiBoardState boardStateFromFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) throw FormatException('empty FEN: $fen');
  final position = parts[0];
  final turn = parts.length > 1 ? parts[1] : 'r';

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

/// FEN 结构校验（服务端 Lua 侧做同类校验）。
///
/// 只看字符集与段数，不做局面合理性（那由引擎负责）。
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
  return true;
}
