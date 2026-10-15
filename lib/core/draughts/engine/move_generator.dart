// lib/core/draughts/engine/move_generator.dart
//
// 国际跳棋走法生成：兵/王走法 + flying king 滑动 + 吃子链 DFS + 最长吃子裁决。
//
// ## 规则要点（International / FMJD）
//
// · 兵（man）斜向**前进** 1 格；**吃子可前可后**（4 个斜向皆可）。
// · 王（king）斜向**任意距离**滑动（flying）；吃子时隔任意距离跳、自选落点。
// · **强制吃子**：只要能吃就必须吃。
// · **最长吃子规则**：必须选吃子数最多的着法（同数时保留全部）。
// · 多跳链：一回合内连吃；**被吃子在整手结束时才移除**（过程中仍占位、挡路）。
// · **同一子不可被跳两次**（captures 去重）。
// · 升王：只有整手**结束**停在对方底线才升；中途经过该行且还能吃 → 必须继续吃、不升。
//
// ## 实现要点
//
// 吃子用 DFS 穷举所有"极大序列"，只在死胡同（无法再吃）处落一条 move，
// 因此天然只产出极大链；再由 [generateMoves] 取最长者。
// 「起手格在过程中是空的」（子已离开）——用 emptyForLanding 特判。

import 'dart:math' as math;

import '../constants/draughts_constants.dart';
import '../models/board_state.dart';
import '../models/move.dart';
import '../models/piece.dart';

/// 生成 [state.sideToMove] 的全部**合法**着法。
///
/// 有吃子 → 只返回最长吃子链（强制吃子 + 最长吃子规则）；
/// 无吃子 → 返回全部普通走法。
List<DraughtsMove> generateMoves(DraughtsBoardState state) {
  final captures = generateCaptureMoves(state);
  if (captures.isNotEmpty) {
    var maxLen = 0;
    for (final m in captures) {
      if (m.captureCount > maxLen) maxLen = m.captureCount;
    }
    return [
      for (final m in captures)
        if (m.captureCount == maxLen) m,
    ];
  }
  return generateSimpleMoves(state);
}

/// 生成全部吃子链（**不**做最长裁决）—— 供引擎内部与测试使用。
List<DraughtsMove> generateCaptureMoves(DraughtsBoardState state) {
  final color = state.sideToMove;
  final out = <DraughtsMove>[];
  for (final (idx, piece) in state.occupied) {
    if (piece.color != color) continue;
    _exploreCaptures(state, idx, piece, idx, <int>[], <int>[idx], out);
  }
  return out;
}

/// 生成全部普通（非吃子）走法。
List<DraughtsMove> generateSimpleMoves(DraughtsBoardState state) {
  final color = state.sideToMove;
  final out = <DraughtsMove>[];
  for (final (idx, piece) in state.occupied) {
    if (piece.color != color) continue;
    final row = draughtsRowOf(idx);
    final col = draughtsColOf(idx);

    if (piece.isKing) {
      // flying king：沿 4 个斜向滑到第一个阻挡前
      for (final (dr, dc) in kDraughtsDiagonals) {
        var r = row + dr;
        var c = col + dc;
        while (draughtsOnBoard(r, c) && state.isEmpty(draughtsIndex(r, c))) {
          out.add(DraughtsMove.simple(idx, draughtsIndex(r, c)));
          r += dr;
          c += dc;
        }
      }
    } else {
      // 兵：仅向前 1 格
      final dr = piece.forwardDelta;
      for (final dc in const [-1, 1]) {
        final r = row + dr;
        final c = col + dc;
        if (!draughtsOnBoard(r, c)) continue;
        final to = draughtsIndex(r, c);
        if (!state.isEmpty(to)) continue;
        out.add(DraughtsMove.simple(
          idx,
          to,
          isPromotion: draughtsRowOf(to) == draughtsPromotionRowFor(piece.isWhite),
        ));
      }
    }
  }
  return out;
}

/// 单个子的吃子链 DFS。
///
/// [startSquare] 该子的原起手格（过程中视为空）；
/// [current] 当前所在格；[captured] 已吃格（回溯用）；[path] 已经过格（含起手）。
/// 只在"吃不动了"的死胡同处向 [out] 落一条 move。
void _exploreCaptures(
  DraughtsBoardState state,
  int startSquare,
  DraughtsPiece piece,
  int current,
  List<int> captured,
  List<int> path,
  List<DraughtsMove> out,
) {
  // 起手格在整手过程中是空的（子已离开）→ 可作落点
  bool emptyForLanding(int idx) => state.isEmpty(idx) || idx == startSquare;

  var extended = false;
  final row = draughtsRowOf(current);
  final col = draughtsColOf(current);

  for (final (dr, dc) in kDraughtsDiagonals) {
    if (piece.isKing) {
      // flying：跳过空格找第一个阻挡
      var r = row + dr;
      var c = col + dc;
      while (draughtsOnBoard(r, c) && emptyForLanding(draughtsIndex(r, c))) {
        r += dr;
        c += dc;
      }
      if (!draughtsOnBoard(r, c)) continue;
      final blockerIdx = draughtsIndex(r, c);
      final blocker = state.pieceAt(blockerIdx);
      if (blocker == null || blocker.color == piece.color) continue;
      if (captured.contains(blockerIdx)) continue; // 同一子不可跳两次

      // 阻挡之后的每个空格都是合法落点
      var lr = r + dr;
      var lc = c + dc;
      while (draughtsOnBoard(lr, lc) && emptyForLanding(draughtsIndex(lr, lc))) {
        final landIdx = draughtsIndex(lr, lc);
        extended = true;
        captured.add(blockerIdx);
        path.add(landIdx);
        _exploreCaptures(state, startSquare, piece, landIdx, captured, path, out);
        path.removeLast();
        captured.removeLast();
        lr += dr;
        lc += dc;
      }
    } else {
      // 兵：隔 1 格敌子、落其后 1 格
      final mr = row + dr;
      final mc = col + dc;
      final lr = row + 2 * dr;
      final lc = col + 2 * dc;
      if (!draughtsOnBoard(mr, mc) || !draughtsOnBoard(lr, lc)) continue;
      final midIdx = draughtsIndex(mr, mc);
      final landIdx = draughtsIndex(lr, lc);
      final midPiece = state.pieceAt(midIdx);
      if (midPiece == null || midPiece.color == piece.color) continue;
      if (captured.contains(midIdx)) continue;
      if (!emptyForLanding(landIdx)) continue;

      extended = true;
      captured.add(midIdx);
      path.add(landIdx);
      _exploreCaptures(state, startSquare, piece, landIdx, captured, path, out);
      path.removeLast();
      captured.removeLast();
    }
  }

  // 死胡同：记录一条极大吃子链
  if (!extended && captured.isNotEmpty) {
    final to = path.last;
    out.add(DraughtsMove(
      from: startSquare,
      to: to,
      path: List<int>.of(path),
      capturedSquares: List<int>.of(captured),
      // 只有兵、且整手结束停在对方底线才升王
      isPromotion:
          !piece.isKing && draughtsRowOf(to) == draughtsPromotionRowFor(piece.isWhite),
    ));
  }
}

/// 某方是否还有任何合法着法（用于终局判定）
bool draughtsHasAnyMove(DraughtsBoardState state) =>
    generateMoves(state).isNotEmpty;

/// 便利：吃子链中的最大吃子数（调试 / 测试用）
int draughtsMaxCaptureCount(DraughtsBoardState state) {
  final caps = generateCaptureMoves(state);
  var maxLen = 0;
  for (final m in caps) {
    maxLen = math.max(maxLen, m.captureCount);
  }
  return maxLen;
}
