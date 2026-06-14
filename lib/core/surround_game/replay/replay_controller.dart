import 'dart:async';
import 'dart:math' show min, max;

import 'package:flutter/foundation.dart';

import '../engine/game_engine.dart';
import '../models/game_state.dart';

/// 自动播放基准间隔（@1x）。@2x/@4x 按倍率缩短。
const Duration kReplayBaseInterval = Duration(milliseconds: 800);

/// 回放速度倍率。
enum ReplaySpeed { x1, x2, x4 }

Duration _intervalFor(ReplaySpeed s) {
  switch (s) {
    case ReplaySpeed.x1:
      return kReplayBaseInterval;
    case ReplaySpeed.x2:
      return kReplayBaseInterval ~/ 2;
    case ReplaySpeed.x4:
      return kReplayBaseInterval ~/ 4;
  }
}

/// 回放视图状态（不可变）。[board] 为光标处的完整棋盘快照。
class ReplayState {
  final List<MoveRecord> history;
  final int cursor; // 0..history.length
  final ReplaySpeed speed;
  final bool isPlaying;
  final GameState board;

  const ReplayState({
    required this.history,
    required this.cursor,
    required this.speed,
    required this.isPlaying,
    required this.board,
  });

  int get totalMoves => history.length;
  bool get atStart => cursor == 0;
  bool get atEnd => cursor >= history.length;

  factory ReplayState.initial(List<MoveRecord> history) => ReplayState(
        history: List.unmodifiable(List.of(history)),
        cursor: 0,
        speed: ReplaySpeed.x1,
        isPlaying: false,
        board: QuoridorEngine.replayHistory(history, upTo: 0),
      );
}

/// 回放控制器 —— 驱动 [ValueNotifier<ReplayState>]，提供传输控件。
class ReplayController {
  final ValueNotifier<ReplayState> stateNotifier;
  Timer? _timer;

  ReplayController({required List<MoveRecord> history})
      : stateNotifier = ValueNotifier(ReplayState.initial(history));

  ReplayState get state => stateNotifier.value;

  void stepForward() {
    if (state.atEnd) {
      pause();
      return;
    }
    final next = state.cursor + 1;
    final reachedEnd = next >= state.totalMoves;
    _emit(cursor: next, playing: reachedEnd ? false : state.isPlaying);
    if (reachedEnd) _cancelTimer();
  }

  void stepBackward() {
    if (state.atStart) return;
    _emit(cursor: state.cursor - 1, playing: false);
    _cancelTimer();
  }

  void seek(int index) {
    final clamped = min(state.totalMoves, max(0, index));
    _emit(cursor: clamped, playing: false);
    _cancelTimer();
  }

  void jumpToStart() => seek(0);
  void jumpToEnd() => seek(state.totalMoves);

  void cycleSpeed() {
    final order = ReplaySpeed.values;
    final next = order[(order.indexOf(state.speed) + 1) % order.length];
    final wasPlaying = state.isPlaying;
    _emit(cursor: state.cursor, playing: wasPlaying, speed: next);
    if (wasPlaying) _startTimer(); // 按新间隔重建
  }

  /// 暂停自动播放（Task 5 实现；stepForward 到尾时也会调用）。
  void pause() {
    _cancelTimer();
    _emit(cursor: state.cursor, playing: false);
  }

  void togglePlay() {
    if (state.isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void play() {
    if (state.atEnd) return; // 到尾不播放
    _emit(cursor: state.cursor, playing: true);
    _startTimer();
  }

  // —— 内部 ——

  void _emit({required int cursor, bool? playing, ReplaySpeed? speed}) {
    final s = state;
    stateNotifier.value = ReplayState(
      history: s.history,
      cursor: cursor,
      speed: speed ?? s.speed,
      isPlaying: playing ?? s.isPlaying,
      board: QuoridorEngine.replayHistory(s.history, upTo: cursor),
    );
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _startTimer() {
    _cancelTimer();
    _timer = Timer.periodic(_intervalFor(state.speed), (_) => stepForward());
  }

  void dispose() {
    _cancelTimer();
    stateNotifier.dispose();
  }
}
