import 'package:flutter/material.dart';
import '../engine/game_engine.dart';
import '../models/game_state.dart';
import '../surround_game_constants.dart';
import 'local_match_state.dart';
import 'local_match_event.dart';

/// 单机热座 ViewModel — ValueNotifier&lt;LocalMatchState&gt; 基干
///
/// 接收 [LocalMatchEvent] 事件，驱动引擎并产生新的 [LocalMatchState]。
final class LocalViewModel extends ValueNotifier<LocalMatchState> {
  LocalViewModel() : super(const LocalIdle());

  /// 分发事件
  void dispatch(LocalMatchEvent event) {
    final next = reduce(value, event);
    if (!identical(next, value)) {
      value = next;
    }
  }

  /// 纯函数 reducer
  LocalMatchState reduce(LocalMatchState s, LocalMatchEvent e) {
    return switch (e) {
      LocalStartPressed() when s is LocalIdle =>
        LocalInGame(QuoridorEngine.initialize()),

      LocalMoveCommitted() when s is LocalInGame =>
        _applyAndCheck(s, e),

      LocalUndoRequested() when s is LocalInGame =>
        _undo(s),

      LocalResetRequested() when s is LocalInGame =>
        LocalInGame(QuoridorEngine.initialize()),

      LocalResetRequested() when s is LocalFinished =>
        LocalInGame(QuoridorEngine.initialize()),

      LocalExitRequested() =>
        const LocalIdle(),

      _ => s,
    };
  }

  /// 执行操作（走棋或放墙），换手，检查胜负
  LocalMatchState _applyAndCheck(LocalInGame s, LocalMoveCommitted e) {
    final GameState? afterAction;
    if (e.isWall) {
      afterAction = QuoridorEngine.placeWall(
        s.gameState, e.wallX!, e.wallY!, e.wallOrientation!,
      );
    } else {
      afterAction = QuoridorEngine.movePiece(s.gameState, e.targetCellId);
    }

    if (afterAction == null) return s; // 非法操作，状态不变

    final afterSwitch = QuoridorEngine.switchTurn(afterAction);

    if (afterSwitch.status != GameStatus.running) {
      return LocalFinished(
        afterSwitch,
        _resultFromStatus(afterSwitch.status),
      );
    }

    return LocalInGame(afterSwitch);
  }

  /// 悔棋 — 回退一步棋谱
  LocalMatchState _undo(LocalInGame s) {
    final history = s.gameState.history;
    if (history.isEmpty) return s;

    final undone = QuoridorEngine.replayHistory(
      history,
      upTo: history.length - 1,
    );
    return LocalInGame(undone);
  }

  /// 从 [GameStatus] 映射为 [GameResult]
  static GameResult _resultFromStatus(GameStatus status) => switch (status) {
    GameStatus.topWin => GameResult.topWin,
    GameStatus.bottomWin => GameResult.bottomWin,
    GameStatus.draw => GameResult.draw,
    GameStatus.running => GameResult.abandoned, // 不应发生
  };
}
