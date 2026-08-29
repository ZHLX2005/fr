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
//   · 网络同步 / 撤销 / 计时 / 升变面板（v2）
//
// 状态机：
//   无选 → tap 己方棋子 → 选中（合法目标刷新）
//   无选 → tap 对方 / 空 → no-op
//   已选（己方棋子A）→ tap 己方棋子A → 重新选中（同上）
//   已选（己方棋子A）→ tap 己方棋子B → 切换到 B
//   已选（己方棋子A）→ tap A 的合法目标 → 应用走法 + emit + 清选
//   已选 → tap 非法（空 / 对方不在合法目标） → 清选
//
// 不变量：
//   · 选中的格子必须是 [state.sideToMove] 一方的棋子
//   · [onMove] 只在合法走法完成时调用，调用方无需再校验

import 'package:flutter/material.dart';

import '../engine/chess_engine.dart';
import '../engine/make_move.dart';
import '../models/board_state.dart';
import '../models/move.dart';
import '../skins/chess_skin.dart';
import 'chess_board.dart';

/// 棋盘交互控制器 —— StatefulWidget。
///
/// 持有 [state] + [selectedSquare]，emit 合法走法到 [onMove]。
class ChessController extends StatefulWidget {
  /// 走法生成 / 应用引擎（注入方便测试 / 自定义）。
  final ChessEngine engine;

  /// 当前皮肤（决定棋子图像）。
  final ChessSkin skin;

  /// 合法走法完成时回调（含 captures / castling 等）。
  /// v1 不做升变面板，遇到升变走法时默认取第一个（Q 升变）作为走法发出。
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
        // v1 无升变面板：如有升变候选（4 个），取非空 promotion 走法做默认；
        // 若没有升变分支，则取普通走法
        final chosen = moves.firstWhere(
          (m) => m.promotion == null,
          orElse: () => moves.first,
        );
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

  @override
  Widget build(BuildContext context) {
    return ChessBoard(
      state: _state,
      skin: widget.skin,
      sideToMove: _state.sideToMove,
      selectedSquare: _selectedSquare,
      legalTargets: _legalTargets,
      lastMove: _lastMove,
      onSquareTap: _handleTap,
    );
  }
}