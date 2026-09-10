// lib/core/chess/engine/make_move.dart
//
// 应用走法 → 返回 (新 BoardState, 应用细节元数据)
// 不变量：
//   1. 输入 BoardState 不能被 mutate
//   2. 输出 BoardState 切换 sideToMove
//   3. 更新易位权（王/车移动会撤销对应易位权，吃对应车同）
//   4. 更新 enPassantTarget（兵双步进留下目标格）
//   5. 更新 halfmoveClock（吃子/兵动清零，否则 +1）
//   6. 更新 fullmoveNumber（黑方走完递增）

import '../models/board_state.dart';
import '../models/move.dart';
import '../models/piece.dart';

/// 应用走法的结果
class ApplyResult {
  final BoardState nextState;
  final bool isCapture;
  final bool isPawnMove;

  const ApplyResult({
    required this.nextState,
    required this.isCapture,
    required this.isPawnMove,
  });
}

/// 应用 [move] 到 [state]，返回新 BoardState
///
/// 注意：本函数假定 [move] 是合法走法（在 chess_engine 校验后才传入）；
/// 若应用伪合法走法（如送将走法），返回的状态可能仍处于将杀对方的位置。
ApplyResult applyMove(BoardState state, Move move) {
  // 复制 board 准备 mutate
  final board = List<int?>.of(state.cells);
  final from = board[move.from];
  if (from == null) {
    throw ArgumentError('No piece at from=${move.from}');
  }

  final pieceType = PieceSlot.unpackType(from);
  final pieceColor = PieceSlot.unpackColorEnum(from);
  final targetColor = state.sideToMove;

  // 检测：吃子（普通走法或升变吃子）
  var capturedSquare = move.capturedSquare;
  var isCapture = capturedSquare != null;

  // 应用前 board mutate
  var enPassantTarget = state.enPassantTarget;
  var castling = state.castling;
  var halfmoveClock = state.halfmoveClock;
  var halfmoveClockBump = true; // 多数走法 +1
  var fullmoveIncrement = false;

  // 裸 UCI（Move.fromUci）可能丢 castling flag：王从 e1/e8 横走两格 → 按易位处理。
  var flag = move.flag;
  if (flag == MoveFlags.none &&
      pieceType == PieceType.king &&
      move.promotion == null &&
      (move.from ~/ 8) == (move.to ~/ 8) &&
      (move.to % 8 - move.from % 8).abs() == 2) {
    if ((pieceColor == PieceColor.white && move.from == 60) ||
        (pieceColor == PieceColor.black && move.from == 4)) {
      flag = MoveFlags.castling;
    }
  }

  switch (flag) {
    case MoveFlags.none:
      // 普通走法（含吃子）
      if (isCapture) {
        // 普通吃子：被吃位置就是 to
        board[move.to] = null;
      }
      break;
    case MoveFlags.castling:
      // 王与车一并移动（搬原车 slot，不重新 pack，避免丢 flags / 凭空造车）
      if (targetColor == PieceColor.white) {
        if (move.to == 62) {
          // 王翼 O-O
          final rook = board[63];
          board[60] = null;
          board[63] = null;
          board[62] = from;
          if (rook != null) board[61] = rook;
        } else if (move.to == 58) {
          // 后翼 O-O-O
          final rook = board[56];
          board[60] = null;
          board[56] = null;
          board[58] = from;
          if (rook != null) board[59] = rook;
        }
      } else {
        if (move.to == 6) {
          final rook = board[7];
          board[4] = null;
          board[7] = null;
          board[6] = from;
          if (rook != null) board[5] = rook;
        } else if (move.to == 2) {
          final rook = board[0];
          board[4] = null;
          board[0] = null;
          board[2] = from;
          if (rook != null) board[3] = rook;
        }
      }
      isCapture = false;
      halfmoveClockBump = true;
      break;
    case MoveFlags.enPassant:
      // 兵吃过路兵：实际吃的是 from 同行的 nc 列
      board[capturedSquare!] = null;
      break;
  }

  // 处理升变：从 from slot → 新 slot（保持颜色，换 type）
  // 易位已在上方搬完王+车，禁止再跑"普通 from→to"（否则会重复写王格）。
  if (flag == MoveFlags.castling) {
    // no-op：棋子已就位
  } else if (move.promotion != null) {
    board[move.from] = null;
    board[move.to] = PieceSlot.pack(move.promotion, pieceColor, flags: 0);
  } else {
    board[move.from] = null;
    board[move.to] = from;
  }

  // 更新易位权
  final newCastling = _updateCastlingRights(
    castling,
    pieceType,
    pieceColor,
    move.from,
    move.to,
    capturedSquare,
  );

  // 更新吃过路兵目标格（只有兵的"双步进"才产生新目标）
  final isPawnAdvanceTwoSquares = pieceType == PieceType.pawn &&
      (move.from ~/ 8 - move.to ~/ 8).abs() == 2;
  if (isPawnAdvanceTwoSquares) {
    // 目标格 = from + (to - from) / 2 = from 的行进中点
    final midRow = (move.from ~/ 8 + move.to ~/ 8) ~/ 2;
    final midCol = move.from % 8;
    enPassantTarget = midRow * 8 + midCol;
  } else {
    enPassantTarget = null;
  }

  // 更新 halfmoveClock：吃子 / 兵移动 → 0；否则 +1
  if (pieceType == PieceType.pawn || isCapture) {
    halfmoveClock = 0;
  } else if (halfmoveClockBump) {
    halfmoveClock += 1;
  }

  // 更新 fullmove：黑方走完递增
  if (state.sideToMove == PieceColor.black) {
    fullmoveIncrement = true;
  }

  // 切换 sideToMove
  final nextColor = opposite(state.sideToMove);
  final nextFullmove =
      state.fullmoveNumber + (fullmoveIncrement ? 1 : 0);

  final nextState = state.copyWith(
    board: board,
    sideToMove: nextColor,
    castling: newCastling,
    enPassantTarget: enPassantTarget,
    clearEnPassant: enPassantTarget == null && state.enPassantTarget != null,
    halfmoveClock: halfmoveClock,
    fullmoveNumber: nextFullmove,
  );

  return ApplyResult(
    nextState: nextState,
    isCapture: isCapture,
    isPawnMove: pieceType == PieceType.pawn,
  );
}

CastlingRights _updateCastlingRights(
  CastlingRights castling,
  PieceType pieceType,
  PieceColor pieceColor,
  int from,
  int to,
  int? capturedSquare,
) {
  // 任何王动 → 撤销该颜色所有易位权
  // 任何车动 → 撤销该车所在侧的易位权
  // 吃车 → 撤销被吃侧易位权（跟王无关）
  var wk = castling.whiteKingSide;
  var wq = castling.whiteQueenSide;
  var bk = castling.blackKingSide;
  var bq = castling.blackQueenSide;

  if (pieceType == PieceType.king) {
    if (pieceColor == PieceColor.white) {
      wk = false;
      wq = false;
    } else {
      bk = false;
      bq = false;
    }
  }

  // 王从 from 走 / 车从 from 走
  if (pieceColor == PieceColor.white && pieceType == PieceType.rook) {
    if (from == 56) wq = false; // a1
    if (from == 63) wk = false; // h1
  } else if (pieceColor == PieceColor.black && pieceType == PieceType.rook) {
    if (from == 0) bq = false;
    if (from == 7) bk = false;
  }

  // 吃车：from / to 中的车格
  if (capturedSquare != null) {
    if (capturedSquare == 56) wq = false;
    if (capturedSquare == 63) wk = false;
    if (capturedSquare == 0) bq = false;
    if (capturedSquare == 7) bk = false;
  }

  return CastlingRights(
    whiteKingSide: wk,
    whiteQueenSide: wq,
    blackKingSide: bk,
    blackQueenSide: bq,
  );
}
