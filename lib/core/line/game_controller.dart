import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domain/chart_data.dart';
import 'domain/constants.dart';
import 'domain/game_result.dart';
import 'domain/note_event.dart';
import 'domain/particle.dart';
import 'domain/song_medal.dart';
import 'engine/game_clock.dart';
import 'engine/game_engine.dart';
import 'engine/hit_feedback.dart';
import 'engine/judge_service.dart';
import 'engine/touch_state.dart';
import 'io/audio_service.dart';
import 'presentation/falling_note.dart';

/// 每根手指的触摸状态
class _PointerState {
  final int pointerId;
  int column;
  Offset startPosition;
  Offset lastPosition;
  int pressClockMs;
  bool tapHandled;
  bool slideHandled;

  _PointerState({
    required this.pointerId,
    required this.column,
    required this.startPosition,
    required this.lastPosition,
    required this.pressClockMs,
  })  : tapHandled = false,
        slideHandled = false;
}

/// 游戏引擎 — 纯逻辑，不依赖 BuildContext
class GameController {
  GameController({
    required this.chart,
    required this.audioPath,
    required this.vsync,
    required this.screenWidth,
    required this.screenHeight,
    required this.themeColor,
    required this.onGameOver,
    this.songId = '',
  });

  // ── 构造参数 ──
  final ChartData chart;
  final String? audioPath;
  final TickerProvider vsync;
  double screenWidth;
  double screenHeight;
  final Color themeColor;
  final void Function(GameResult) onGameOver;
  final String songId;
  VoidCallback? onStateChanged;

  bool get isLandscape => screenWidth > screenHeight;
  double get shortSide =>
      screenWidth < screenHeight ? screenWidth : screenHeight;
  double get radius => shortSide / columnCount * noteSizeRatio;
  double get judgeY =>
      screenHeight * (isLandscape ? 0.82 : judgeLineRatio);
  double get _judgeProgressRatio =>
      (judgeY + radius) / (screenHeight + 2 * radius);

  // ── 水动画状态 ──
  bool isWaterEntering = true;
  bool isExiting = false;
  bool isCountingDown = false;
  int countdownValue = 3;

  // ── 游戏状态 ──
  int nextNoteIndex = 0;
  final GameClock _clock = GameClock();
  int _clockMs = 0;
  bool isPaused = false;
  int get clockMs => _clockMs;
  final List<List<FallingNote>> notes = List.generate(columnCount, (_) => []);
  final List<ExplodeAnimation> explodes = [];
  final List<JudgeFeedback> judgeFeedbacks = [];

  /// 判定线闪白（0~1）
  double judgeLineFlash = 0.0;

  int highScore = 0;
  final GameEngine _engine = GameEngine();
  /// 由 [init] 里 [HitFeedback.ensureLoaded] 赋值（选曲页已预加载则秒就绪）
  late HitFeedback _hitFeedback;

  int get score => _engine.score;
  double get health => _engine.health;
  int get perfectCount => _engine.perfectCount;
  int get greatCount => _engine.greatCount;
  int get goodCount => _engine.goodCount;
  int get missCount => _engine.missCount;
  int get maxCombo => _engine.maxCombo;
  int get currentCombo => _engine.combo;

  // ── 音频 ──
  AudioService? _audioService;

  // ── 设置 ──
  BackgroundStyle backgroundStyle = BackgroundStyle.none;
  String highScoreKey = '';
  double timingScale = 1.0;
  double scrollSpeed = 1.0;
  int inputOffsetMs = 0;
  bool showEarlyLate = true;
  bool wasGameRunning = false;

  // ── 手势追踪 ──
  final Set<int> heldColumns = {};
  final Map<int, _PointerState> _pointers = {};
  final Set<int> holdCompletedColumns = {};

  // ── 生命周期 ──

  Future<void> init() async {
    await _loadSettings();
    if (audioPath != null) {
      _audioService = AudioService(audioPath: audioPath!);
      await _audioService!.init();
      _audioService!.onCompletion = () {
        if (!isExiting) _gameOver(cleared: true);
      };
    }
    clearAll();
  }

  void clearAll() {
    for (final col in notes) {
      for (final note in col) {
        note.controller.dispose();
      }
      col.clear();
    }
    for (final e in explodes) {
      e.controller.dispose();
    }
    explodes.clear();
    for (final fb in judgeFeedbacks) {
      fb.controller.dispose();
    }
    judgeFeedbacks.clear();
    _pointers.clear();
    heldColumns.clear();
    holdCompletedColumns.clear();
    judgeLineFlash = 0.0;
    _engine.reset();
  }

  void dispose() {
    _clock.stop();
    _audioService?.dispose();
    // 音效会话由选曲页 / HitFeedback.releaseSession 释放，此处不 dispose
    for (final col in notes) {
      for (final note in col) {
        note.controller.dispose();
      }
    }
    for (final e in explodes) {
      e.controller.dispose();
    }
    for (final fb in judgeFeedbacks) {
      fb.controller.dispose();
    }
    _pointers.clear();
    heldColumns.clear();
    holdCompletedColumns.clear();
    onStateChanged = null;
  }

  void updateScreenSize(double w, double h) {
    screenWidth = w;
    screenHeight = h;
  }

  /// 每帧由 game_page ticker 调用
  void tick() {
    if (judgeLineFlash > 0) {
      judgeLineFlash = (judgeLineFlash - 0.08).clamp(0.0, 1.0);
    }
    if (isExiting || isCountingDown || isPaused) return;
    _clockMs = _clock.sample(_audioService?.positionMs);
    spawnPendingNotes();
    _updateActiveHolds();
  }

  // ── 设置持久化 ──

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    highScoreKey = 'line_high_score_${chart.name.hashCode}';
    timingScale = prefs.getDouble(lineTimingScaleKey) ?? 1.0;
    scrollSpeed = prefs.getDouble(lineScrollSpeedKey) ?? 1.0;
    inputOffsetMs = prefs.getInt(lineInputOffsetKey) ?? 0;
    _clock.inputOffsetMs = inputOffsetMs;
    showEarlyLate = prefs.getBool(lineShowEarlyLateKey) ?? true;
    highScore = prefs.getInt(highScoreKey) ?? 0;
    final bgIndex = prefs.getInt(lineBackgroundKey) ?? 0;
    backgroundStyle = BackgroundStyle
        .values[bgIndex.clamp(0, BackgroundStyle.values.length - 1)];
    // 进局前须已预加载；此处复用会话并同步开关
    _hitFeedback = await HitFeedback.ensureLoaded(
      hapticsEnabled: prefs.getBool(lineHapticsKey) ?? true,
      sfxEnabled: prefs.getBool(lineHitSfxKey) ?? true,
      strict: true,
    );
    onStateChanged?.call();
  }

  Future<void> saveHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    final total = chart.notes.length;
    if (total > 0) {
      final accuracyKey =
          highScoreKey.replaceFirst('line_high_score_', 'line_high_accuracy_');
      final accuracy =
          (perfectCount * 3 + greatCount * 2 + goodCount) / (total * 3) * 100;
      final stored = prefs.getDouble(accuracyKey) ?? 0;
      if (accuracy > stored) {
        await prefs.setDouble(accuracyKey, accuracy);
      }
    }
    if (score > highScore) {
      highScore = score;
      await prefs.setInt(highScoreKey, highScore);
    }
  }

  // ── 游戏流程 ──

  void startGame() {
    _clock.inputOffsetMs = inputOffsetMs;
    _clock.start();
    nextNoteIndex = 0;
    _clockMs = _clock.sample(_audioService?.positionMs);
    spawnPendingNotes();
    _audioService?.play();
  }

  void stopGame() {
    _clock.stop();
    _audioService?.pause();
    for (final col in notes) {
      for (final note in col) {
        note.controller.stop();
      }
    }
  }

  void startCountdown() {
    isCountingDown = true;
    countdownValue = 3;
    onStateChanged?.call();
    _tickCountdown(3);
  }

  void _tickCountdown(int remaining) {
    countdownValue = remaining;
    onStateChanged?.call();
    if (remaining <= 0) {
      isCountingDown = false;
      isPaused = false;
      _resumeFromSnapshot();
      return;
    }
    Future.delayed(
      const Duration(milliseconds: 800),
      () => _tickCountdown(remaining - 1),
    );
  }

  void _resumeFromSnapshot() {
    isPaused = false;
    if (!wasGameRunning) {
      startGame();
      return;
    }
    final seekMs = (_clockMs - inputOffsetMs).clamp(0, 1 << 30);
    _audioService?.seek(Duration(milliseconds: seekMs));
    _clock.inputOffsetMs = inputOffsetMs;
    _clock.start();
    _audioService?.play();
    for (final col in notes) {
      for (final note in col) {
        if (!note.judged) note.controller.forward();
      }
    }
    for (final e in explodes) {
      e.controller.forward();
    }
    spawnPendingNotes();
  }

  // ── 音符生成 ──

  void spawnPendingNotes() {
    if (isExiting) return;
    final elapsed = clockMs;
    final dropMs = chart.dropDuration;

    while (nextNoteIndex < chart.notes.length) {
      final event = chart.notes[nextNoteIndex];
      final actualDropMs = dropMs / scrollSpeed;
      final spawnTime =
          event.time - (actualDropMs * _judgeProgressRatio).round();
      if (elapsed >= spawnTime) {
        spawnNote(event);
        nextNoteIndex++;
      } else {
        break;
      }
    }
  }

  void spawnNote(NoteEvent event) {
    final actualDropMs = (chart.dropDuration / scrollSpeed).round();
    final controller = AnimationController(
      duration: Duration(milliseconds: actualDropMs),
      vsync: vsync,
    );

    final note = FallingNote(
      event: event,
      controller: controller,
      currentY: -radius,
    );
    // 理论生成时刻，供绘制用 clockMs - spawnElapsed
    note.spawnElapsed =
        event.time - (actualDropMs * _judgeProgressRatio).round();

    controller.addListener(() {
      final elapsed = clockMs;
      final progress = ((elapsed - note.spawnElapsed) / actualDropMs)
          .clamp(0.0, 1.5);
      final targetY = screenHeight + radius;
      note.currentY = -radius + (targetY + radius) * progress;

      if (!note.judged && event.type != NoteType.hold) {
        final missThreshold = event.time + (missWindow * timingScale).round();
        if (elapsed > missThreshold) {
          final col = notes.indexWhere((col) => col.contains(note));
          if (col >= 0) onNoteMissed(col, note);
        }
      }
    });

    notes[event.column].add(note);

    controller.forward().then((_) {
      if (note.removeMe) return;
      if (event.type == NoteType.hold) {
        Future.delayed(Duration(milliseconds: event.holdDuration ?? 0), () {
          if (!notes[event.column].contains(note)) return;
          note.controller.dispose();
          notes[event.column].remove(note);
        });
        return;
      }
      note.controller.dispose();
      notes[event.column].remove(note);
    });
  }

  void _updateActiveHolds() {
    final elapsed = _clockMs;
    final scaledMiss = (missWindow * timingScale).round();
    for (var col = 0; col < notes.length; col++) {
      for (final note in List<FallingNote>.from(notes[col])) {
        if (note.event.type != NoteType.hold || note.judged) continue;
        final duration = note.event.holdDuration ?? 0;
        if (duration <= 0) continue;

        if (note.holding) {
          final endTime = note.event.time + duration;
          // 进度按谱面时间填，与尾判时刻对齐
          note.holdProgress =
              ((elapsed - note.event.time) / duration).clamp(0.0, 1.0);

          // 身段 tick：仅在尾点之前累计
          while (elapsed >= note.holdNextTickAt &&
              note.holding &&
              note.holdNextTickAt <= endTime) {
            note.holdTicksHit++;
            note.holdNextTickAt += holdTickIntervalMs;
          }

          // 超过尾窗仍未抬手 → 尾 Miss（必须有尾判，禁止假 Perfect）
          if (elapsed > endTime + scaledMiss) {
            _finalizeHoldWithTail(col, note, elapsed - endTime);
          }
          continue;
        }

        if (!note.holdHeadLocked) {
          final missThreshold = note.event.time + scaledMiss;
          if (elapsed > missThreshold) {
            onNoteMissed(col, note);
          }
        }
      }
    }
  }

  // ── 手势处理 ──

  void handlePointerDown(PointerDownEvent event) {
    handlePressAt(event.pointer, event.localPosition, event.position);
  }

  void handlePressAt(int pointer, Offset localPosition, Offset globalPosition) {
    if (isExiting || isCountingDown || isPaused) return;
    final col = columnFromX(localPosition.dx, screenWidth, columnCount);
    if (col == null) return;

    final state = _PointerState(
      pointerId: pointer,
      column: col,
      startPosition: globalPosition,
      lastPosition: globalPosition,
      pressClockMs: clockMs,
    );
    _pointers[pointer] = state;

    if (_tryJudgeTap(col)) {
      state.tapHandled = true;
      return;
    }

    _handleColumnPress(col);
  }

  void handlePointerMove(PointerMoveEvent event) {
    handleMoveAt(event.pointer, event.position);
  }

  void handleMoveAt(int pointer, Offset globalPosition) {
    final state = _pointers[pointer];
    if (state == null) return;
    state.lastPosition = globalPosition;

    if (state.tapHandled || state.slideHandled) return;
    if (heldColumns.contains(state.column)) return;

    final delta = globalPosition - state.startPosition;
    final dtSec = (clockMs - state.pressClockMs) / 1000.0;
    final velocity = delta.distance / math.max(0.001, dtSec);
    final dir = swipeDirection(
      delta.dx,
      delta.dy,
      velocityPxPerSec: velocity,
    );
    if (dir == null) return;

    if (_tryJudgeSlide(state.column, dir)) {
      state.slideHandled = true;
    }
  }

  void handlePointerUp(PointerUpEvent event) {
    final state = _pointers.remove(event.pointer);
    if (state == null) return;

    final col = state.column;

    // 抬手：只处理 hold 释放；不再二次 tap
    _handleColumnRelease(col);

    if (state.tapHandled || state.slideHandled) return;

    // 兜底：若 move 未触发 swipe，抬手时用总位移再试一次
    final delta = event.position - state.startPosition;
    final dtSec = (clockMs - state.pressClockMs) / 1000.0;
    final velocity = delta.distance / math.max(0.001, dtSec);
    final dir = swipeDirection(
      delta.dx,
      delta.dy,
      velocityPxPerSec: velocity,
    );
    if (dir != null) {
      _tryJudgeSlide(col, dir);
    }
  }

  void handlePointerCancel(PointerCancelEvent event) {
    final state = _pointers.remove(event.pointer);
    if (state == null) return;
    _handleColumnRelease(state.column);
  }

  // ── 判定 ──

  bool _tryJudgeTap(int col) {
    final elapsed = clockMs;
    FallingNote? best;
    final scaledMissWindow = (missWindow * timingScale).round();
    var bestAbs = scaledMissWindow + 1;
    var bestSigned = 0;

    for (final note in notes[col]) {
      if (note.judged) continue;
      if (note.event.type != NoteType.tap) continue;
      final signed = elapsed - note.event.time;
      final abs = signed.abs();
      if (abs < bestAbs) {
        bestAbs = abs;
        bestSigned = signed;
        best = note;
      }
    }

    if (best != null && bestAbs <= scaledMissWindow) {
      judgeNote(col, best, bestSigned);
      return true;
    }
    return false;
  }

  void _handleColumnPress(int col) {
    if (holdCompletedColumns.contains(col)) return;
    final elapsed = clockMs;
    final scaledMissWindow = (missWindow * timingScale).round();

    FallingNote? foundNote;
    for (final note in notes[col]) {
      if (note.event.type != NoteType.hold) continue;
      if (note.judged) continue;
      final signedDiff = elapsed - note.event.time;
      if (signedDiff < -scaledMissWindow) continue;
      if (signedDiff > scaledMissWindow) continue;
      foundNote = note;
      break;
    }

    if (foundNote != null) {
      final signed = elapsed - foundNote.event.time;
      final head = judge(signed, timingScale);
      foundNote.holding = true;
      foundNote.holdHeadResult = head;
      foundNote.holdHeadLocked = true;
      foundNote.holdJudgeDiff = signed;
      foundNote.holdPressTime = elapsed;
      foundNote.holdTicksExpected =
          expectedHoldTicks(foundNote.event.holdDuration ?? 0);
      foundNote.holdTicksHit = 0;
      foundNote.holdNextTickAt = elapsed + holdTickIntervalMs;
      heldColumns.add(col);
      if (head.label == JudgeResultLabel.perfect &&
          _hitFeedback.hapticsEnabled) {
        HapticFeedback.lightImpact();
      }
      onStateChanged?.call();
    }
  }

  void _handleColumnRelease(int col) {
    if (!heldColumns.contains(col)) {
      holdCompletedColumns.remove(col);
      return;
    }
    heldColumns.remove(col);
    holdCompletedColumns.remove(col);

    final elapsed = clockMs;
    final scaledMiss = (missWindow * timingScale).round();
    for (final note in notes[col]) {
      if (!note.holding || note.judged) continue;
      if (note.event.type != NoteType.hold) continue;

      final duration = note.event.holdDuration ?? 0;
      final endTime = note.event.time + duration;
      note.holding = false;

      // 过早抬手（尾点前超出 miss 窗，或未到 earlyRelease 比例）→ Miss
      final tooEarlyByWindow = elapsed < endTime - scaledMiss;
      final heldTime = elapsed - note.holdPressTime;
      final tooEarlyByRatio = heldTime < duration * holdEarlyReleaseRatio;
      if (tooEarlyByWindow || tooEarlyByRatio) {
        onNoteMissed(col, note, showFeedback: true);
        return;
      }

      // 尾判：相对谱面结束时刻的抬手误差
      _finalizeHoldWithTail(col, note, elapsed - endTime);
      return;
    }
  }

  /// 用尾点误差合成最终 Hold 判定并结算
  void _finalizeHoldWithTail(int col, FallingNote note, int tailSignedDiffMs) {
    if (note.judged) return;
    final head =
        note.holdHeadResult ?? judge(note.holdJudgeDiff, timingScale);
    final tail = judge(tailSignedDiffMs, timingScale);
    final composed = composeHoldResult(
      head: head,
      ticksHit: note.holdTicksHit,
      ticksExpected: note.holdTicksExpected,
      tail: tail,
      timingScale: timingScale,
    );
    heldColumns.remove(col);
    holdCompletedColumns.add(col);
    note.holding = false;
    finalizeHold(col, note, composed);
  }

  bool _tryJudgeSlide(int col, SlideDirection direction) {
    final elapsed = clockMs;
    final scaledMissWindow = (missWindow * timingScale).round();
    FallingNote? best;
    var bestAbs = scaledMissWindow + 1;
    var bestSigned = 0;

    for (final note in notes[col]) {
      if (note.judged || note.event.type != NoteType.slide) continue;
      if (note.event.direction != direction) continue;
      final signed = elapsed - note.event.time;
      final abs = signed.abs();
      if (abs < bestAbs) {
        bestAbs = abs;
        bestSigned = signed;
        best = note;
      }
    }

    if (best != null && bestAbs <= scaledMissWindow) {
      judgeNote(col, best, bestSigned);
      return true;
    }
    return false;
  }

  /// Hold 最终结算（头/身/尾已合成）
  void finalizeHold(int col, FallingNote note, JudgeResult composed) {
    if (note.judged) return;
    note.judged = true;
    note.holding = false;
    note.removeMe = false;
    _applyJudgeResult(col, note, composed);
  }

  /// [signedDiffMs] = clock - note.time
  void judgeNote(int col, FallingNote note, int signedDiffMs) {
    if (note.judged) return;
    note.judged = true;
    note.removeMe = true;

    final result = judge(signedDiffMs, timingScale);
    _applyJudgeResult(col, note, result);
    if (isExiting) return;

    if (note.event.type == NoteType.hold) {
      note.removeMe = false;
    } else {
      note.controller.stop();
      Future.delayed(const Duration(milliseconds: 300), () {
        notes[col].remove(note);
        note.controller.dispose();
      });
    }
  }

  void _applyJudgeResult(int col, FallingNote note, JudgeResult result) {
    if (result.label == JudgeResultLabel.miss) {
      _engine.applyJudge(result);
      _showMissFeedback(col, note);
      _hitFeedback.play(
        label: JudgeResultLabel.miss,
        noteType: note.event.type,
      );
    } else {
      _engine.applyJudge(result);
      _showHitFeedback(col, note, result);
      _hitFeedback.play(
        label: result.label,
        noteType: note.event.type,
      );
      judgeLineFlash = 1.0;
      _maybeComboMilestone();
    }

    if (_engine.isGameOver) {
      _gameOver(cleared: false);
      return;
    }
    onStateChanged?.call();
  }

  void _maybeComboMilestone() {
    final combo = currentCombo;
    if (combo != 50 && combo != 100) return;
    final cx = screenWidth / 2;
    final cy = screenHeight / 2;
    createExplode(
      0,
      cx,
      cy,
      label: JudgeResultLabel.perfect,
    );
    final feedbackController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: vsync,
    );
    final feedback = JudgeFeedback(
      text: '$combo',
      x: cx,
      y: cy - radius * 2,
      color: const Color(0xFFFFD54F),
      baseAlpha: 0.95,
      fontScale: 1.5,
      controller: feedbackController,
      label: JudgeResultLabel.perfect,
    );
    judgeFeedbacks.add(feedback);
    feedbackController.forward().then((_) {
      feedbackController.dispose();
      judgeFeedbacks.remove(feedback);
    });
  }

  void onNoteMissed(
    int col,
    FallingNote note, {
    bool showFeedback = true,
  }) {
    if (note.judged) return;
    note.judged = true;
    note.holding = false;
    _engine.applyMiss(timingScale);
    if (showFeedback) {
      _showMissFeedback(col, note);
      _hitFeedback.playMiss();
    }
    onStateChanged?.call();
    if (_engine.isGameOver) {
      _gameOver(cleared: false);
      return;
    }
    if (note.event.type == NoteType.hold) {
      silentFadeOutHold(col, note);
    } else {
      note.removeMe = true;
      note.controller.stop();
    }
  }

  void silentFadeOutHold(int col, FallingNote note) {
    if (note.holdFadeOut > 0) return;
    note.judged = true;
    note.removeMe = false;
    note.holding = false;
    if (note.holdPressTime > 0) {
      final heldTime = (clockMs - note.holdPressTime)
          .clamp(0, note.event.holdDuration!);
      note.holdProgress =
          (heldTime / note.event.holdDuration!).clamp(0.0, 1.0);
    }
    note.holdFadeOut = 1.0;
  }

  // ── 视觉 ──

  Color _colorFor(JudgeResultLabel label) {
    switch (label) {
      case JudgeResultLabel.perfect:
        return const Color(0xFFFFD54F);
      case JudgeResultLabel.great:
        return const Color(0xFF81D4FA);
      case JudgeResultLabel.good:
        return themeColor;
      case JudgeResultLabel.miss:
        return const Color(0xFFEF9A9A);
    }
  }

  double _fontScaleFor(JudgeResultLabel label) {
    switch (label) {
      case JudgeResultLabel.perfect:
        return 1.35;
      case JudgeResultLabel.great:
        return 1.15;
      case JudgeResultLabel.good:
        return 1.0;
      case JudgeResultLabel.miss:
        return 1.1;
    }
  }

  String? _hintText(JudgeResult result) {
    if (!showEarlyLate) return null;
    switch (result.hint) {
      case TimingHint.early:
        return 'EARLY';
      case TimingHint.late:
        return 'LATE';
      case TimingHint.none:
        return null;
    }
  }

  void _showHitFeedback(int col, FallingNote note, JudgeResult result) {
    final colWidth = screenWidth / columnCount;
    final centerX = colWidth * col + colWidth / 2;

    final feedbackController = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: vsync,
    );
    final feedback = JudgeFeedback(
      text: result.text,
      hintText: _hintText(result),
      x: centerX,
      y: judgeY - radius * 3,
      color: _colorFor(result.label),
      baseAlpha: result.alpha,
      fontScale: _fontScaleFor(result.label),
      controller: feedbackController,
      label: result.label,
    );
    judgeFeedbacks.add(feedback);
    feedbackController.forward().then((_) {
      feedbackController.dispose();
      judgeFeedbacks.remove(feedback);
    });

    createExplode(
      col,
      centerX,
      note.currentY,
      weak: result.label == JudgeResultLabel.good,
      label: result.label,
    );
  }

  void _showMissFeedback(int col, FallingNote note) {
    final colWidth = screenWidth / columnCount;
    final centerX = colWidth * col + colWidth / 2;
    final feedbackController = AnimationController(
      duration: const Duration(milliseconds: 480),
      vsync: vsync,
    );
    final feedback = JudgeFeedback(
      text: 'Miss',
      x: centerX,
      y: judgeY - radius * 3,
      color: _colorFor(JudgeResultLabel.miss),
      baseAlpha: 0.8,
      fontScale: _fontScaleFor(JudgeResultLabel.miss),
      controller: feedbackController,
      label: JudgeResultLabel.miss,
    );
    judgeFeedbacks.add(feedback);
    feedbackController.forward().then((_) {
      feedbackController.dispose();
      judgeFeedbacks.remove(feedback);
    });
    createExplode(
      col,
      centerX,
      note.currentY,
      weak: true,
      label: JudgeResultLabel.miss,
    );
  }

  void createExplode(
    int col,
    double x,
    double y, {
    bool weak = false,
    JudgeResultLabel? label,
  }) {
    final explodeController = AnimationController(
      duration: Duration(milliseconds: weak ? 220 : 320),
      vsync: vsync,
    );
    final explode = ExplodeAnimation(
      controller: explodeController,
      x: x,
      y: y,
      particles: _generateParticles(
        weak: weak,
        perfect: label == JudgeResultLabel.perfect,
      ),
      radius: radius,
      weak: weak,
      label: label,
    );
    explodes.add(explode);
    explodeController.forward().then((_) {
      explodeController.dispose();
      explodes.remove(explode);
    });
  }

  List<Particle> _generateParticles({
    bool weak = false,
    bool perfect = false,
  }) {
    final rng = math.Random();
    final count = weak
        ? 3 + rng.nextInt(2)
        : perfect
            ? 10 + rng.nextInt(4)
            : 6 + rng.nextInt(3);
    final baseDist = perfect ? 22.0 : (weak ? 10.0 : 18.0);
    final step = perfect ? 6.0 : (weak ? 3.0 : 5.0);
    final baseAlpha = perfect ? 0.8 : (weak ? 0.35 : 0.65);
    return List.generate(count, (i) {
      final angle =
          (2 * math.pi * i / count) + (rng.nextDouble() - 0.5) * 0.6;
      return Particle(
        angle: angle,
        distance: baseDist + i * step + rng.nextDouble() * 5,
        initialAlpha: baseAlpha - i * 0.04,
      );
    });
  }

  // ── 游戏结束 ──

  void _gameOver({required bool cleared}) {
    if (isExiting) return;
    stopGame();
    saveHighScore();

    final result = GameResult(
      songName: chart.name,
      songId: songId,
      score: score,
      highScore: highScore,
      perfectCount: perfectCount,
      greatCount: greatCount,
      goodCount: goodCount,
      missCount: missCount,
      maxCombo: maxCombo,
      totalNotes: chart.notes.length,
      cleared: cleared,
    );

    unawaited(SongMedalStore.record(songId, result));

    isExiting = true;
    onGameOver(result);
    onStateChanged?.call();
  }

  Future<void> handleExit() async {
    if (isExiting) return;
    stopGame();
    await saveHighScore();
    isExiting = true;
    onStateChanged?.call();
  }

  void showSpeedSettings() {
    wasGameRunning = !isExiting && !isCountingDown;
    isCountingDown = false;
    isPaused = true;
    stopGame();
    for (final col in notes) {
      for (final note in col) {
        note.controller.stop();
      }
    }
    for (final e in explodes) {
      e.controller.stop();
    }
  }

  Future<void> reloadSettings() async {
    await _loadSettings();
  }
}
