// lib/core/xiangqi/jieqi/jieqi_engine.dart
//
// 揭棋引擎：走法生成 + 将军判定 + 终局判定 + 棋谱重放。
//
// ## 与标准象棋引擎（engine/）的分工
//
//   · 走法生成 / 合法性过滤 / 将军判定**复用** move_generator.dart，
//     载体是**虚拟棋盘**：暗子按点位棋种替换（[jieqiVirtualBoard]）——
//     「暗子按所在位置照中国象棋规则走出第一步」与「把暗子当作
//     点位棋种的明子走」是同一件事。
//   · 唯一的规则放宽在**翻开的士 / 象**：士斜行一格全盘（可出九宫、
//     可过河）、象走田全盘（可过河、保留塞象眼）。标准生成器会把士锁
//     九宫、象锁半场，因此这两类子的走法单独生成后拼进伪合法集。
//   · 合法性过滤（走后自己将不被攻击）必须基于**走后**的虚拟棋盘：
//     走的是暗子 → 走后它是**真实棋种**的明子；其余暗子仍按点位棋种
//     攻击。这也是走法过滤不能用标准 xiangqiLegalMoves 的原因之一
//     （它不知道「暗子走完会变脸」）。
//   · 终局判定（[jieqiStatus]）与 XiangqiEngine.status 同构：
//     缺将判负；无着可走无论是否被将军都判负（将死 / 困毙）。

import '../constants/xiangqi_constants.dart';
import '../engine/make_move.dart';
import '../engine/move_generator.dart';
import '../models/board_state.dart';
import '../models/game_status.dart';
import '../models/move.dart';
import '../models/piece.dart';
import 'jieqi_state.dart';

/// 虚拟棋盘：把 [state.hidden] 里的棋子替换为其**点位棋种**（颜色不变）。
///
/// 用途：
///   · 走法生成 —— 暗子按点位棋种走出第一步；
///   · 将军判定 —— 对方暗子的威胁按其点位棋种算（它动之前只能那样动）。
XiangqiBoardState jieqiVirtualBoard(JieqiState state) {
  var changed = false;
  final cells = List<int?>.of(state.board.cells);
  for (final idx in state.hidden) {
    final slot = cells[idx];
    if (slot == null) continue; // 防御：hidden 只含占格
    final piece = XiangqiPiece.unpack(slot);
    final role = jieqiRoleTypeAt(idx);
    if (role == piece.type) continue;
    cells[idx] = XiangqiPiece(piece.color, role).pack();
    changed = true;
  }
  if (!changed) return state.board;
  return XiangqiBoardState(cells: cells, sideToMove: state.board.sideToMove);
}

/// 揭棋伪合法走法（不看走后自己将是否被攻击）。
///
///   · 暗子（含翻开后走法受限的士象）→ 点位棋种标准走法（虚拟棋盘给出）；
///   · 翻开的士 → 斜行一格全盘（可出九宫 / 过河）；
///   · 翻开的象 → 走田全盘（可过河，保留塞象眼）。
List<XiangqiMove> _jieqiPseudoLegalMoves(JieqiState state) {
  final board = jieqiVirtualBoard(state);
  final side = board.sideToMove;
  final out = <XiangqiMove>[];
  for (final move in xiangqiPseudoLegalMoves(board)) {
    final piece = board.pieceAt(move.from);
    if (piece == null) continue;
    // 翻开的士象走法已被标准生成器按「九宫内 / 半场内」裁剪，
    // 抛掉后用放宽版重新生成。
    if (!state.hidden.contains(move.from) &&
        (piece.type == XiangqiPieceType.advisor ||
            piece.type == XiangqiPieceType.elephant)) {
      continue;
    }
    out.add(move);
  }
  for (final (idx, piece) in board.occupied) {
    if (piece.color != side) continue;
    if (state.hidden.contains(idx)) continue; // 暗子走标准点位走法
    switch (piece.type) {
      case XiangqiPieceType.advisor:
        _collectRelaxedAdvisor(board, idx, piece, out);
      case XiangqiPieceType.elephant:
        _collectRelaxedElephant(board, idx, piece, out);
      default:
        break;
    }
  }
  return out;
}

/// 落点入集（不能吃己方子 / 不能吃将 —— 与 move_generator 的 add 同规）。
void _addRelaxedMove(
  XiangqiBoardState board,
  int from,
  int tr,
  int tc,
  XiangqiPiece piece,
  List<XiangqiMove> out,
) {
  if (!xiangqiOnBoard(tr, tc)) return;
  final to = xiangqiIndex(tr, tc);
  final target = board.pieceAt(to);
  if (target != null) {
    if (target.color == piece.color) return;
    if (target.isGeneral) return;
  }
  out.add(XiangqiMove(from: from, to: to, captured: target));
}

/// 翻开的士：斜行一格全盘（可出九宫、可过河）。
void _collectRelaxedAdvisor(
  XiangqiBoardState board,
  int idx,
  XiangqiPiece piece,
  List<XiangqiMove> out,
) {
  final r = xiangqiRowOf(idx);
  final c = xiangqiColOf(idx);
  for (final (dr, dc) in kXiangqiAdvisorMoves) {
    _addRelaxedMove(board, idx, r + dr, c + dc, piece, out);
  }
}

/// 翻开的象：走田全盘（可过河），保留塞象眼。
void _collectRelaxedElephant(
  XiangqiBoardState board,
  int idx,
  XiangqiPiece piece,
  List<XiangqiMove> out,
) {
  final r = xiangqiRowOf(idx);
  final c = xiangqiColOf(idx);
  for (final (dr, dc) in kXiangqiElephantMoves) {
    final tr = r + dr;
    final tc = c + dc;
    // 目标越界 → 跳过（同时保证象眼中点在界内）
    if (!xiangqiOnBoard(tr, tc)) continue;
    final midR = r + dr ~/ 2;
    final midC = c + dc ~/ 2;
    if (!board.isEmpty(xiangqiIndex(midR, midC))) continue; // 塞象眼
    _addRelaxedMove(board, idx, tr, tc, piece, out);
  }
}

/// 揭棋合法走法：伪合法 → 走后自己将不被攻击（基于走后虚拟棋盘）。
List<XiangqiMove> jieqiLegalMoves(JieqiState state) {
  final side = state.board.sideToMove;
  final out = <XiangqiMove>[];
  for (final move in _jieqiPseudoLegalMoves(state)) {
    final next = jieqiApplyMove(state, move);
    if (!jieqiIsInCheck(next, side)) out.add(move);
  }
  return out;
}

/// 某格棋子（若属于走子方）的揭棋合法走法。
List<XiangqiMove> jieqiLegalMovesFrom(JieqiState state, int from) {
  if (state.board.pieceAt(from) == null) return const [];
  final out = <XiangqiMove>[];
  for (final move in jieqiLegalMoves(state)) {
    if (move.from == from) out.add(move);
  }
  return out;
}

/// 应用揭棋走法：真实棋盘走子；**走的暗子翻开**（hidden 去掉起点 /
/// 终点 —— 起点的子已移走，终点的子（若有）是被吃掉的暗子）。
JieqiState jieqiApplyMove(JieqiState state, XiangqiMove move) {
  final board = applyXiangqiMoveSimple(state.board, move);
  final hidden = Set<int>.of(state.hidden)
    ..remove(move.from)
    ..remove(move.to);
  return JieqiState(board: board, hidden: hidden);
}

/// 揭棋将军判定：某方将 / 帅是否被攻击（基于虚拟棋盘，含将帅照面）。
bool jieqiIsInCheck(JieqiState state, XiangqiColor color) =>
    xiangqiIsInCheck(jieqiVirtualBoard(state), color);

/// 揭棋终局判定（与 XiangqiEngine.status 同构）。
XiangqiStatus jieqiStatus(JieqiState state) {
  final me = state.board.sideToMove;
  final opp = xiangqiOpposite(me);

  // 1) 缺将 —— 非法局面（走法生成禁止吃将，正常对局不会出现）。
  if (state.board.generalSquareOf(opp) < 0) {
    return XiangqiStatus(
      me == XiangqiColor.red
          ? XiangqiOutcome.redWins
          : XiangqiOutcome.blackWins,
      XiangqiEndReason.noGeneral,
    );
  }
  if (state.board.generalSquareOf(me) < 0) {
    return XiangqiStatus(
      me == XiangqiColor.red
          ? XiangqiOutcome.blackWins
          : XiangqiOutcome.redWins,
      XiangqiEndReason.noGeneral,
    );
  }

  // 2) 无着可走 → 判负（将死 / 困毙同为负 —— 象棋规则）。
  if (jieqiLegalMoves(state).isEmpty) {
    final inCheck = jieqiIsInCheck(state, me);
    return XiangqiStatus(
      me == XiangqiColor.red
          ? XiangqiOutcome.blackWins
          : XiangqiOutcome.redWins,
      inCheck ? XiangqiEndReason.checkmate : XiangqiEndReason.stalemate,
    );
  }

  return XiangqiStatus.playing;
}

/// 从揭棋开局状态按棋谱（`b0e2` 记号串）结构重放，返回**逐手**状态
/// 子序列：out[0] = 初始态，out[n] = 走完 n 手后的状态（暗子集合随之
/// 收缩 —— 每个走过的暗子当场翻开）。
///
/// 记号无法解析 / 起点无子 / 终点己方子 → 抛 [ArgumentError] /
/// [FormatException]，调用方按需降级（见 xiangqi_room_page 的
/// 降级口径：重放失败 → 暗子集合置空，全部按明子渲染）。
List<JieqiState> jieqiReplayStates(JieqiState initial, List<String> ucis) {
  final out = <JieqiState>[initial];
  var state = initial;
  for (final uci in ucis) {
    final move = XiangqiMove.fromUci(uci);
    if (move == null) {
      throw FormatException('bad jieqi uci: $uci');
    }
    if (state.board.pieceAt(move.from) == null) {
      throw ArgumentError('no piece at ${move.fromName} for $uci');
    }
    final target = state.board.pieceAt(move.to);
    if (target != null &&
        target.color == state.board.pieceAt(move.from)!.color) {
      throw ArgumentError('own piece at ${move.toName} for $uci');
    }
    state = jieqiApplyMove(state, move);
    out.add(state);
  }
  return out;
}
