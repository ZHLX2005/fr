// Reversi (Othello) 黑白翻转棋 - 状态管理通知器
//
// 遵循项目 word_drag 范式：extends ChangeNotifier，方法内更新 _state 后 notifyListeners()。
// 消费方通过 provider 的 ChangeNotifierProvider + context.watch<ReversiNotifier>() 读取。

import 'package:flutter/material.dart';
import '../models/reversi_board.dart';
import 'reversi_state.dart';

class ReversiNotifier extends ChangeNotifier {
  ReversiState _state = ReversiState.initial();
  ReversiState get state => _state;

  // ==================== 玩家操作 ====================

  /// 在 [pos] 落当前方棋子
  ///
  /// 非法落子或游戏已结束时静默忽略。
  void placeStone(Position pos) {
    if (_state.isOver) return;
    if (!_state.board.isLegalMove(pos, _state.currentPlayer)) return;

    final mover = _state.currentPlayer;

    // 1. 压栈：记录"落子前"的完整状态，供悔棋回溯
    final newHistory = List<ReversiSnapshot>.from(_state.history)
      ..add(
        ReversiSnapshot(
          board: _state.board,
          currentPlayer: mover,
          lastMove: _state.lastMove,
        ),
      );

    // 2. 落子翻转
    final newBoard = _state.board.placeStone(pos, mover);

    // 3. 推演下一状态（切换玩家 / pass / 结束判定）
    _state = _resolveNext(
      board: newBoard,
      mover: mover,
      lastMove: pos,
      history: newHistory,
    );
    notifyListeners();
  }

  /// 悔棋：回到当前方上一次面临决策的状态
  ///
  /// 在历史栈中向前查找最近的「对手曾落子前」的快照，恢复到该状态。
  /// 例如黑方悔棋 → 搜索 history 中 currentPlayer==白方 的快照（那是黑方刚落子前的状态）。
  /// 这等价于撤销黑方上一次落子（连同白方随后的应招一并回退）。
  void undo() {
    final cur = _state.currentPlayer;
    // 当前方想撤销，需要找到对手上一次落子前的快照
    final targetMover = cur.opponent;
    int? target;
    for (var i = _state.history.length - 1; i >= 0; i--) {
      if (_state.history[i].currentPlayer == targetMover) {
        target = i;
        break;
      }
    }
    if (target == null) return; // 对手从未落子，无可悔

    final snap = _state.history[target];
    _state = ReversiState(
      board: snap.board,
      currentPlayer: snap.currentPlayer, // = targetMover = 当前方的对手 → 重新轮到当前方决策
      status: ReversiStatus.playing,
      history: _state.history.sublist(0, target),
      lastMove: snap.lastMove,
      message: '${_playerName(cur)}方悔棋',
    );
    notifyListeners();
  }

  /// 重新开始
  void restart() {
    _state = ReversiState.initial();
    notifyListeners();
  }

  // ==================== 内部推演 ====================

  /// 计算落子后的下一状态：切换玩家，处理 pass 与结束判定
  ReversiState _resolveNext({
    required ReversiBoard board,
    required PieceType mover,
    required Position lastMove,
    required List<ReversiSnapshot> history,
  }) {
    final opponent = mover.opponent;
    final opponentCanMove = board.legalMovesFor(opponent).isNotEmpty;
    final moverCanMove = board.legalMovesFor(mover).isNotEmpty;

    // 双方都无合法步 → 游戏结束
    if (!opponentCanMove && !moverCanMove) {
      return _finishedState(board, history, lastMove);
    }

    // 对方有步 → 轮到对方（正常切换，无提示）
    if (opponentCanMove) {
      return ReversiState(
        board: board,
        currentPlayer: opponent,
        status: ReversiStatus.playing,
        history: history,
        lastMove: lastMove,
        message: null,
      );
    }

    // 对方无步但本方有步 → 对方跳过，本方继续
    return ReversiState(
      board: board,
      currentPlayer: mover,
      status: ReversiStatus.playing,
      history: history,
      lastMove: lastMove,
      message: '${_playerName(opponent)}方无合法步，跳过',
    );
  }

  /// 构造游戏结束状态
  ReversiState _finishedState(
    ReversiBoard board,
    List<ReversiSnapshot> history,
    Position lastMove,
  ) {
    final b = board.count(PieceType.black);
    final w = board.count(PieceType.white);
    final status = b > w
        ? ReversiStatus.blackWon
        : w > b
            ? ReversiStatus.whiteWon
            : ReversiStatus.draw;
    return ReversiState(
      board: board,
      currentPlayer: PieceType.black,
      status: status,
      history: history,
      lastMove: lastMove,
      message: _resultMessage(status, b, w),
    );
  }

  String _playerName(PieceType p) => p == PieceType.black ? '黑' : '白';

  String _resultMessage(ReversiStatus s, int b, int w) {
    switch (s) {
      case ReversiStatus.blackWon:
        return '黑方胜利 $b : $w';
      case ReversiStatus.whiteWon:
        return '白方胜利 $w : $b';
      case ReversiStatus.draw:
        return '平局 $b : $w';
      case ReversiStatus.playing:
        return '';
    }
  }
}
