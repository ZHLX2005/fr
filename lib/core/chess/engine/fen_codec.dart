// lib/core/chess/engine/fen_codec.dart
//
// FEN (Forsyth-Edwards Notation) 字符串 ↔ BoardState 转换
//
// FEN 格式（6 个空格分隔字段）：
//   <board> <sideToMove> <castling> <en-passant> <halfmove> <fullmove>
//
// <board>：8 行（rank 8 → rank 1），斜杠 `/` 分隔；每行从左 a → 右 h
//   · 大写 = 白方，小写 = 黑方
//   · 数字 = 空格子数（1-8）
//
// 示例起点：rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1
//
// 本 codec 还附 SAN 序列化（just for PGN-like 输出）的辅助。

import '../constants/chess_constants.dart';
import '../models/board_state.dart';
import '../models/piece.dart';

class FenCodec {
  FenCodec._();

  /// 解析 FEN 字符串 → BoardState
  ///
  /// 错误时抛 ArgumentError
  static BoardState fromFen(String fen) {
    final parts = fen.split(' ');
    if (parts.length < 4) {
      throw ArgumentError('Invalid FEN: not enough fields');
    }

    final boardStr = parts[0];
    final sideStr = parts[1];
    final castlingStr = parts[2];
    final epStr = parts[3];
    final halfmoveStr = parts.length >= 5 ? parts[4] : '0';
    final fullmoveStr = parts.length >= 6 ? parts[5] : '1';

    // 1. board 解析
    final board = List<int?>.filled(kBoardSquares, null, growable: false);
    final rankStrs = boardStr.split('/');
    if (rankStrs.length != 8) {
      throw ArgumentError('Invalid FEN board: $boardStr');
    }

    for (var rankIdx = 0; rankIdx < 8; rankIdx++) {
      // rankIdx 0 → row 0 (= rank 8)
      // rankIdx 7 → row 7 (= rank 1)
      final row = rankIdx;
      final rankStr = rankStrs[rankIdx];

      var col = 0;
      for (var i = 0; i < rankStr.length; i++) {
        final ch = rankStr[i];
        final code = ch.codeUnitAt(0);
        if (code >= 48 && code <= 57) {
          // 数字 0-9
          final n = code - 48;
          col += n;
        } else {
          if (col >= 8) {
            throw ArgumentError(
              'Invalid FEN rank $row: too many pieces ($rankStr)',
            );
          }
          final idx = row * 8 + col;
          final piece = pieceFromFenChar(ch);
          if (piece == null) {
            throw ArgumentError('Invalid FEN piece char: $ch');
          }
          board[idx] = PieceSlot.pack(piece.$1, piece.$2);
          col++;
        }
      }
      if (col != 8) {
        throw ArgumentError('Invalid FEN rank $row: not exactly 8 squares');
      }
    }

    // 2. sideToMove
    final side = sideStr == 'w'
        ? PieceColor.white
        : (sideStr == 'b' ? PieceColor.black : (throw ArgumentError('Invalid side: $sideStr')));

    // 3. castling
    final castling = CastlingRights.fromFenString(castlingStr);

    // 4. en-passant
    int? ep;
    if (epStr != '-' && epStr.length == 2) {
      ep = squareToIndex(epStr);
      if (ep == -1) {
        throw ArgumentError('Invalid en-passant square: $epStr');
      }
    }

    // 5. halfmove
    final halfmove = int.tryParse(halfmoveStr);
    if (halfmove == null || halfmove < 0) {
      throw ArgumentError('Invalid halfmove: $halfmoveStr');
    }

    // 6. fullmove
    final fullmove = int.tryParse(fullmoveStr);
    if (fullmove == null || fullmove < 1) {
      throw ArgumentError('Invalid fullmove: $fullmoveStr');
    }

    return BoardState(
      board: board,
      sideToMove: side,
      castling: castling,
      enPassantTarget: ep,
      halfmoveClock: halfmove,
      fullmoveNumber: fullmove,
    );
  }

  /// BoardState → FEN 字符串
  static String toFen(BoardState state) {
    final buf = StringBuffer();

    // 1. board
    for (var row = 0; row < 8; row++) {
      var emptyRun = 0;
      for (var col = 0; col < 8; col++) {
        final idx = row * 8 + col;
        final slot = state.cells[idx];
        if (slot == null) {
          emptyRun++;
        } else {
          if (emptyRun > 0) {
            buf.write(emptyRun);
            emptyRun = 0;
          }
          final t = PieceSlot.unpackType(slot);
          final c = PieceSlot.unpackColorEnum(slot);
          buf.write(pieceToFenChar(t, c));
        }
      }
      if (emptyRun > 0) buf.write(emptyRun);
      if (row < 7) buf.write('/');
    }

    // 2. sideToMove
    buf.write(' ${pieceColorToFenChar(state.sideToMove)}');

    // 3. castling
    buf.write(' ${state.castling.toFenString()}');

    // 4. en-passant
    buf.write(' ');
    if (state.enPassantTarget == null) {
      buf.write('-');
    } else {
      buf.write(indexToSquare(state.enPassantTarget!));
    }

    // 5. halfmove
    buf.write(' ${state.halfmoveClock}');

    // 6. fullmove
    buf.write(' ${state.fullmoveNumber}');

    return buf.toString();
  }
}
