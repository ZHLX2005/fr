// lib/core/chess/widgets/chess_controller.dart
//
// 棋盘交互控制器 —— 拥有"选中 / 合法目标 / 完成走法"状态机。
//
// 责任：
//   · 持有当前 [BoardState]（默认 [BoardState.initial()]）
//   · 持有 [_selectedSquare]（当前选中的 1D index）
//   · 监听 [ChessBoard] 的 [onSquareTap] → 走 [ChessEngine] 判定 + 应用合法走法
//   · 走法完成时调 [onMove] 回调 + 推进 state
//
// 不负责：
//   · 走法生成（[ChessEngine.generateLegalMoves]）
//   · 网络同步 / 撤销 / 计时
//
// 状态机：
//   无选 → tap 己方棋子 → 选中（合法目标刷新）
//   无选 → tap 对方 / 空 → no-op
//   已选（己方棋子A）→ tap 己方棋子A → 重新选中（同上）
//   已选（己方棋子A）→ tap 己方棋子B → 切换到 B
//   已选（己方棋子A）→ tap A 的合法目标（非升变） → 应用走法 + emit + 清选
//   已选（己方棋子A）→ tap A 的合法目标（升变） → 弹升变面板，等玩家选 Q/R/B/N
//   已选 → tap 非法（空 / 对方不在合法目标） → 清选
//
// 升变（v2 新增）：兵到底线时暂停走法应用，弹 [PromotionPanel] 让玩家选
// 后/车/象/马；选完才应用走法 + emit，取消则回到未选状态。
//
// 不变量：
//   · 选中的格子必须是 [state.sideToMove] 一方的棋子
//   · [onMove] 只在合法走法完成时调用，调用方无需再校验

import 'package:flutter/material.dart';

import '../engine/chess_engine.dart';
import '../engine/make_move.dart';
import '../models/board_state.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../skins/chess_skin.dart';
import 'chess_board.dart';
import 'promotion_panel.dart';

/// 棋盘交互控制器 —— StatefulWidget。
///
/// 持有 [state] + [selectedSquare]，emit 合法走法到 [onMove]。
class ChessController extends StatefulWidget {
  /// 走法生成 / 应用引擎（注入方便测试 / 自定义）。
  final ChessEngine engine;

  /// 当前皮肤（决定棋子图像）。
  final ChessSkin skin;

  /// 合法走法完成时回调（含 captures / castling 等）。
  /// 升变走法：弹 [PromotionPanel] 等玩家选完 Q/R/B/N 后，再以所选升变
  /// 走法调用本回调（不再是 v1 的静默取 Q）。
  final void Function(Move move) onMove;

  /// 起始局面（null = 默认 [BoardState.initial()]）。
  final BoardState? initialState;

  const ChessController({
    super.key,
    required this.engine,
    required this.skin,
    required this.onMove,
    this.initialState,
  });

  @override
  State<ChessController> createState() => _ChessControllerState();
}

class _ChessControllerState extends State<ChessController> {
  late BoardState _state;
  int? _selectedSquare;
  Move? _lastMove;

  // 当玩家点到一个"升变目标格"（4 个 promotion 候选）时，暂停走法应用，
  // 弹出升变面板让玩家选 Q/R/B/N。选完才应用 + emit。
  ({int from, int to})? _pendingPromotion;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState ?? BoardState.initial();
  }

  /// 当前 [_selectedSquare] 的合法目标（落点 1D index）。
  /// 不选中 → 空集。
  Set<int> get _legalTargets {
    final sel = _selectedSquare;
    if (sel == null) return const <int>{};
    if (_state.pieceColorAt(sel) != _state.sideToMove) {
      return const <int>{};
    }
    final moves = widget.engine.generateLegalMoves(_state);
    return {for (final m in moves)
      if (m.from == sel) m.to};
  }

  void _handleTap(int square) {
    final pieceColor = _state.pieceColorAt(square);
    final sel = _selectedSquare;

    // 情况 1：未选中 → 点到己方棋子 → 选中
    if (sel == null) {
      if (pieceColor == _state.sideToMove) {
        setState(() {
          _selectedSquare = square;
        });
      }
      // 对方 / 空 → no-op
      return;
    }

    // 情况 2：已选中 → 点到同一格 → 清选
    if (square == sel) {
      setState(() {
        _selectedSquare = null;
      });
      return;
    }

    // 情况 3：已选中 → 点到另一颗己方棋子 → 切换选中
    if (pieceColor == _state.sideToMove) {
      setState(() {
        _selectedSquare = square;
      });
      return;
    }

    // 情况 4：已选中 → 点到合法目标（空格或对方）→ 应用走法
    final targets = _legalTargets;
    if (targets.contains(square)) {
      final moves = widget.engine.generateLegalMoves(_state)
          .where((m) => m.from == sel && m.to == square)
          .toList();
      if (moves.isNotEmpty) {
        // 升变候选存在 → 暂停，等玩家选 Q/R/B/N（面板由 build() 里的 Stack 弹出）
        final promotionMoves =
            moves.where((m) => m.promotion != null).toList();
        if (promotionMoves.isNotEmpty) {
          setState(() {
            _pendingPromotion = (from: sel, to: square);
          });
          return;
        }
        final chosen = moves.first;
        final newState = applyMove(_state, chosen).nextState;
        setState(() {
          _state = newState;
          _selectedSquare = null;
          _lastMove = chosen;
        });
        widget.onMove(chosen);
        return;
      }
    }

    // 情况 5：其它（非法目标）→ 清选
    setState(() {
      _selectedSquare = null;
    });
  }

  /// 玩家在升变面板选了具体类型 → 应用对应升变走法 + emit。
  void _resolvePromotion(PieceType type) {
    final pending = _pendingPromotion;
    if (pending == null) return;
    final moves = widget.engine
        .generateLegalMoves(_state)
        .where((m) =>
            m.from == pending.from &&
            m.to == pending.to &&
            m.promotion == type)
        .toList();
    if (moves.isEmpty) {
      // 状态异常（不应发生）：清 pending
      setState(() => _pendingPromotion = null);
      return;
    }
    final chosen = moves.first;
    final newState = applyMove(_state, chosen).nextState;
    setState(() {
      _state = newState;
      _selectedSquare = null;
      _lastMove = chosen;
      _pendingPromotion = null;
    });
    widget.onMove(chosen);
  }

  /// 取消升变 → 面板消失，回到未选状态。
  void _cancelPromotion() {
    setState(() => _pendingPromotion = null);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingPromotion;
    return Stack(
      children: [
        ChessBoard(
          state: _state,
          skin: widget.skin,
          sideToMove: _state.sideToMove,
          // 本地对弈视角整局稳定（白方在底）——不随 sideToMove 翻转，
          // 否则每走一步棋盘 180° 掉头（真机反馈"走子后棋盘变样"）。
          flipped: false,
          selectedSquare: _selectedSquare,
          legalTargets: _legalTargets,
          lastMove: _lastMove,
          onSquareTap: _handleTap,
        ),
        if (pending != null)
          Positioned.fill(
            child: PromotionPanel(
              skin: widget.skin,
              promotingColor: _state.sideToMove,
              onSelected: _resolvePromotion,
              onCancel: _cancelPromotion,
            ),
          ),
      ],
    );
  }
}