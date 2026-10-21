// lib/core/xiangqi/engine/xiangqi_engine.dart
//
// 中国象棋引擎对外 facade：
//   · legalMoves(state)      → 合法着法（含「将军后必须应将」过滤）
//   · applyMove(state, move) → 新状态
//   · status(state)          → 终局判定
//
// 设计（对齐 lib/core/draughts/engine/draughts_engine.dart）：
//   · 走法没有"送将"约束 → 生成了就是合法（比国际象棋简单）。
//   · 终局几何：将死 / 困毙（判负，不是和棋）。
//   · 性能：走法生成 O(子数 × 棋种分支)，9×10 全局足够；不追求搜索性能。
//
// ## 与国际跳棋 / 国际象棋的终局差异
//
//   · 国际象棋：被将军且无解 = 将死（负）；未被将军且无解 = 僵局（和）。
//   · 国际跳棋：无着可走 = 直接判负（没有将军概念）。
//   · 中国象棋：无着可走 **无论是否被将军都判负** —— 被将军且无解 = 将死，
//     未被将军且无解 = 困毙，同为负。这是象棋最容易被误解的一条。

import '../models/board_state.dart';
import '../models/game_status.dart';
import '../models/move.dart';
import '../models/piece.dart';
import 'make_move.dart';
import 'move_generator.dart';

/// 中国象棋引擎对外接口
class XiangqiEngine {
  const XiangqiEngine();

  /// [state.sideToMove] 的全部合法着法。
  ///
  /// 合法 = 走后自己将不被攻击（含将帅照面）。
  List<XiangqiMove> legalMoves(XiangqiBoardState state) =>
      xiangqiLegalMoves(state);

  /// 某格棋子的合法着法（棋盘交互用）。
  List<XiangqiMove> legalMovesFrom(XiangqiBoardState state, int from) =>
      xiangqiLegalMovesFrom(state, from);

  /// 应用走法
  XiangqiApplyResult apply(XiangqiBoardState state, XiangqiMove move) =>
      applyXiangqiMove(state, move);

  /// 是否还有合法着法
  bool hasLegalMoves(XiangqiBoardState state) =>
      xiangqiLegalMoves(state).isNotEmpty;

  /// 该方是否被将军（含将帅照面）
  bool isInCheck(XiangqiBoardState state, XiangqiColor color) =>
      xiangqiIsInCheck(state, color);

  /// 终局判定。
  ///
  /// [positionHistory] 传该局**自开局**所有局面键的 `positionKey`（含当前），
  /// 用于重复局面检测；不传则跳过重复检测。
  ///
  /// 中国象棋一般比赛不强制「三次重复判和」，因此重复局面**不作为终局条件**；
  /// 保留参数是为了与 chess / draughts 的 facade 形状保持平行（协议层同一套代码路径）。
  XiangqiStatus status(
    XiangqiBoardState state, {
    List<String> positionHistory = const [],
  }) {
    final me = state.sideToMove;
    final opp = xiangqiOpposite(me);

    // 1) 缺将 —— 非法局面（走法生成禁止吃将，正常对局不会出现）。
    //    对方缺将 → 我方胜；我方缺将 → 我方负。
    if (state.generalSquareOf(opp) < 0) {
      return XiangqiStatus(
        me == XiangqiColor.red
            ? XiangqiOutcome.redWins
            : XiangqiOutcome.blackWins,
        XiangqiEndReason.noGeneral,
      );
    }
    if (state.generalSquareOf(me) < 0) {
      return XiangqiStatus(
        me == XiangqiColor.red
            ? XiangqiOutcome.blackWins
            : XiangqiOutcome.redWins,
        XiangqiEndReason.noGeneral,
      );
    }

    // 2) 无着可走 → 判负。
    //    被将军 = 将死；未被将军 = 困毙（象棋规则同为负）。
    if (xiangqiLegalMoves(state).isEmpty) {
      final inCheck = xiangqiIsInCheck(state, me);
      return XiangqiStatus(
        me == XiangqiColor.red
            ? XiangqiOutcome.blackWins
            : XiangqiOutcome.redWins,
        inCheck ? XiangqiEndReason.checkmate : XiangqiEndReason.stalemate,
      );
    }

    return XiangqiStatus.playing;
  }

  /// 便利：apply + 检查终局（返回新状态与终局状态）。
  (XiangqiBoardState, XiangqiStatus) applyAndCheck(
    XiangqiBoardState state,
    XiangqiMove move, {
    List<String> positionHistory = const [],
  }) {
    final next = applyXiangqiMove(state, move).nextState;
    return (next, status(next, positionHistory: positionHistory));
  }
}

/// 全局默认引擎
const XiangqiEngine kDefaultXiangqiEngine = XiangqiEngine();
