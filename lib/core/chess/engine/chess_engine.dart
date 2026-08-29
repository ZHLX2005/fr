// lib/core/chess/engine/chess_engine.dart
//
// 国际象棋引擎对外 facade：
//   - generateLegalMoves(state)
//   - applyMove(state, move)
//   - isInCheck(state)
//   - getStatus(state)  → GameStatus + 是否将军 + winning side
//
// 设计：
//   · generateLegalMoves 先调 move_generator 拿伪合法走法，再筛掉"送将"走法
//   · "送将"判定：applyMove 后看 sideToMove 的王是否被攻击（即轮到对方时我王被将）
//   · isInCheck 是"当前 sideToMove 是否被将" （即上一手方是否给出将军）
//
// 性能要点（未做，详见 §性能边界）：
//   - 伪合法 ~ 数十级别；送将筛选 ≤ 90 次 （一次性测试棋盘即可），完全可承受
//   - 当前 O(L×N) 暴力，可处理 8×8 标准对弈与打谱回放
//   - 长局面（>10k 节点）应升级到 magic bitboard / transposition table；本模块
//     不背这层复杂度，等真有需求再说

import '../models/board_state.dart';
import '../models/game_status.dart';
import '../models/move.dart';
import '../models/piece.dart';
import 'attack_map.dart';
import 'make_move.dart';
import 'move_generator.dart';

/// chess 引擎对外接口
class ChessEngine {
  const ChessEngine();

  /// 返回当前 [state.sideToMove] 在 [state] 中所有合法走法
  ///
  /// 合法走法 = 不会让自己的王在走完后被对方任何子攻击
  ///
  /// 性能：O(L^2) 量级（L ≈ 几十），可接受
  List<Move> generateLegalMoves(BoardState state) {
    final pseudo = generatePseudoLegalMoves(state);
    final legal = <Move>[];
    final myColor = state.sideToMove;

    for (final m in pseudo) {
      // 王车易位时额外校验：王经过的格子不能被攻击。
      // move_generator 已生成"无将军"判定，但每个格子的"非攻击"保证由王车易位自身评估，
      // 此处再额外校验：尝试 applyMove 后看王位是否被攻击。
      final result = applyMove(state, m);
      final newState = result.nextState;
      final kingSquare = newState.findKing(myColor);
      if (kingSquare == null) {
        // 王被吃是异常状态（不应合法），跳过
        continue;
      }
      final attacked = computeAttackedSquares(newState, opposite(myColor));
      if (attacked.contains(kingSquare)) {
        // 送将
        continue;
      }
      // 推断"是否造成对方被将"或"将杀"
      final oppKing = newState.findKing(opposite(myColor));
      bool givesCheck = false;
      bool isCheckmate = false;
      if (oppKing != null) {
        final oppAttacked = computeAttackedSquares(newState, myColor);
        if (oppAttacked.contains(oppKing)) {
          givesCheck = true;
          // 是否将杀 = 该方是否有合法走法（在原 sideToMove 切换后）
          final oppLegal = generatePseudoLegalMoves(newState)
              .where((mm) {
            final r = applyMove(newState, mm);
            final k = r.nextState.findKing(opposite(myColor)) ?? -1;
            if (k < 0) return false;
            final atk = computeAttackedSquares(r.nextState, myColor);
            return !atk.contains(k);
          }).toList();
          if (oppLegal.isEmpty) {
            isCheckmate = true;
          }
        }
      }
      legal.add(Move(
        from: m.from,
        to: m.to,
        promotion: m.promotion,
        flag: m.flag,
        capturedSquare: m.capturedSquare,
        givesCheck: givesCheck,
        isCheckmate: isCheckmate,
      ));
    }
    return legal;
  }

  /// 是否有当前 sideToMove 的合法走法（即非将杀 / 非僵局）
  bool hasLegalMoves(BoardState state) {
    return generateLegalMoves(state).isNotEmpty;
  }

  /// 当前 sideToMove 是否被将军
  ///
  /// 这里指"上一手方是否给出了将军"。意味着：state 中已将军我方王。
  bool isInCheck(BoardState state) {
    final myKing = state.findKing(state.sideToMove);
    if (myKing == null) return false;
    final attacked = computeAttackedSquares(state, opposite(state.sideToMove));
    return attacked.contains(myKing);
  }

  /// 计算终局状态
  ///
  /// 注意：此函数假定半回合 / 全回合不变（终止状态由调用方判定）
  GameStatus getStatus(BoardState state) {
    // 一律先判终局几何类型
    // 50 回合 / 三次重复 / 死局留给上层 protocol（P2P 协议层 / UI 计时器）
    final legal = generateLegalMoves(state);
    if (legal.isNotEmpty) {
      if (isInCheck(state)) {
        return GameStatus.check;
      }
      return GameStatus.playing;
    }

    if (isInCheck(state)) {
      return GameStatus.checkmate;
    }
    // 50 回合规则检测（halfmoveClock ≥ 100 = 50 全回合）
    if (state.halfmoveClock >= 100) {
      return GameStatus.fiftyMoveRule;
    }
    return GameStatus.stalemate;
  }

  /// 便利方法：applyMove + 检查终局
  BoardState applyAndAdvance(BoardState state, Move move) {
    return applyMove(state, move).nextState;
  }
}

/// 全局默认引擎
const ChessEngine kDefaultChessEngine = ChessEngine();
