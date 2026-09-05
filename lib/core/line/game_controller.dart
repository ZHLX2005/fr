import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domain/chart_data.dart';
import 'domain/constants.dart';
import 'domain/game_result.dart';
import 'domain/note_event.dart';
import 'domain/particle.dart';
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
  });

  // ── 构造参数 ──
  final ChartData chart;
  final String? audioPath;
  final TickerProvider vsync;
  final double screenWidth;
  final double screenHeight;
  final Color themeColor;
  final void Function(GameResult) onGameOver;
  VoidCallback? onStateChanged;

  double get radius => screenWidth / columnCount * noteSizeRatio;
  double get judgeY => screenHeight * judgeLineRatio;
  double get _judgeProgressRatio =>
      (screenHeight * judgeLineRatio + radius) / (screenHeight + 2 * radius);

  // ── 水动画状态 ──
  bool isWaterEntering = true;
  bool isExiting = false;
  bool isCountingDown = false;
  int countdownValue = 3;

  // ── 游戏状态 ──
  int nextNoteIndex = 0;
  final Stopwatch gameStopwatch = Stopwatch();
  final List<List<FallingNote>> notes = List.generate(columnCount, (_) => []);
  final List<ExplodeAnimation> explodes = [];
  final List<JudgeFeedback> judgeFeedbacks = [];

  /// 判定线闪白（0~1）
  double judgeLineFlash = 0.0;

  int highScore = 0;
  final GameEngine _engine = GameEngine();
  final HitFeedback _hitFeedback = HitFeedback();

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

  /// 权威游戏时钟（ms）：优先音频进度 + 输入偏移；无音频则 Stopwatch。
  int get clockMs {
    final audio = _audioService?.positionMs;
    final base = audio ?? gameStopwatch.elapsedMilliseconds;
    return base + inputOffsetMs;
  }

  // ── 生命周期 ──

  Future<void> init() async {
    await _loadSettings();
    await _hitFeedback.init();
    if (audioPath != null) {
      _audioService = AudioService(audioPath: audioPath!);
      await _audioService!.init();
      _audioService!.onCompletion = () {
        if (!isExiting) _gameOver();
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
    gameStopwatch.stop();
    _audioService?.dispose();
    unawaited(_hitFeedback.dispose());
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

  // ── 设置持久化 ──

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    highScoreKey = 'line_high_score_${chart.name.hashCode}';
    timingScale = prefs.getDouble(lineTimingScaleKey) ?? 1.0;
    scrollSpeed = prefs.getDouble(lineScrollSpeedKey) ?? 1.0;
    inputOffsetMs = prefs.getInt(lineInputOffsetKey) ?? 0;
    _hitFeedback.hapticsEnabled = prefs.getBool(lineHapticsKey) ?? true;
    _hitFeedback.sfxEnabled = prefs.getBool(lineHitSfxKey) ?? true;
    showEarlyLate = prefs.getBool(lineShowEarlyLateKey) ?? true;
    highScore = prefs.getInt(highScoreKey) ?? 0;
    final bgIndex = prefs.getInt(lineBackgroundKey) ?? 0;
    backgroundStyle = BackgroundStyle
        .values[bgIndex.clamp(0, BackgroundStyle.values.length - 1)];
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
    nextNoteIndex = 0;
    gameStopwatch.reset();
    gameStopwatch.start();
    spawnPendingNotes();
    _audioService?.play();
  }

  void stopGame() {
    gameStopwatch.stop();
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
      _resumeFromSnapshot();
      return;
    }
    Future.delayed(
      const Duration(milliseconds: 800),
      () => _tickCountdown(remaining - 1),
    );
  }

  void _resumeFromSnapshot() {
    if (!wasGameRunning) {
      startGame();
      return;
    }
    gameStopwatch.start();
    _audioService?.seek(Duration(milliseconds: gameStopwatch.elapsedMilliseconds));
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

    if (nextNoteIndex < chart.notes.length && !isExiting) {
      final nextEvent = chart.notes[nextNoteIndex];
      final nextActualDropMs = dropMs / scrollSpeed;
      final nextSpawnTime =
          nextEvent.time - (nextActualDropMs * _judgeProgressRatio).round();
      final delayMs = (nextSpawnTime - elapsed).clamp(1, 100);
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (!isExiting) spawnPendingNotes();
      });
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

      if (event.type == NoteType.hold && note.holding && !note.judged) {
        final heldTime = elapsed - note.holdPressTime;
        note.holdProgress =
            (heldTime / event.holdDuration!).clamp(0.0, 1.0);
        if (note.holdProgress >= 1.0) {
          judgeNote(event.column, note, note.holdJudgeDiff);
          note.holding = false;
          holdCompletedColumns.add(event.column);
        }
        return;
      }

      if (!note.judged && event.type == NoteType.hold && !note.holding) {
        final missThreshold = event.time + (missWindow * timingScale).round();
        if (elapsed > missThreshold) {
          final col = notes.indexWhere((col) => col.contains(note));
          if (col >= 0) {
            onNoteMissed(col, note);
          }
        }
      }

      if (judgeLineFlash > 0) {
        judgeLineFlash = (judgeLineFlash - 0.08).clamp(0.0, 1.0);
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

  // ── 手势处理 ──

  void handlePointerDown(PointerDownEvent event) {
    if (isExiting || isCountingDown) return;
    final col = columnFromX(event.localPosition.dx, screenWidth, columnCount);
    if (col == null) return;

    final state = _PointerState(
      pointerId: event.pointer,
      column: col,
      startPosition: event.position,
      lastPosition: event.position,
      pressClockMs: clockMs,
    );
    _pointers[event.pointer] = state;

    // Tap：按下即判（手感关键）
    if (_tryJudgeTap(col)) {
      state.tapHandled = true;
      return;
    }

    // Hold：按下起按
    _handleColumnPress(col);
  }

  void handlePointerMove(PointerMoveEvent event) {
    final state = _pointers[event.pointer];
    if (state == null) return;
    state.lastPosition = event.position;

    if (state.tapHandled || state.slideHandled) return;
    if (heldColumns.contains(state.column)) return;

    final delta = event.position - state.startPosition;
    final dir = swipeDirection(delta.dx, delta.dy);
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
    final dir = swipeDirection(delta.dx, delta.dy);
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
      foundNote.holding = true;
      foundNote.holdJudgeDiff = elapsed - foundNote.event.time;
      foundNote.holdPressTime = elapsed;
      heldColumns.add(col);
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
    for (final note in notes[col]) {
      if (!note.holding || note.judged) continue;
      if (note.event.type != NoteType.hold) continue;

      final heldTime = elapsed - note.holdPressTime;
      if (heldTime >= note.event.holdDuration! * 0.8) {
        judgeNote(col, note, note.holdJudgeDiff);
      } else {
        // 提前松手 → 明确 Miss
        onNoteMissed(col, note, showFeedback: true);
      }
      note.holding = false;
      return;
    }
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

  /// [signedDiffMs] = clock - note.time
  void judgeNote(int col, FallingNote note, int signedDiffMs) {
    if (note.judged) return;
    note.judged = true;
    note.removeMe = true;

    final result = judge(signedDiffMs, timingScale);
    if (result.label == JudgeResultLabel.miss) {
      // 窗口内太偏：走 miss 语义
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
    }

    if (_engine.isGameOver) {
      _gameOver();
      return;
    }
    onStateChanged?.call();

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

  void onNoteMissed(
    int col,
    FallingNote note, {
    bool showFeedback = true,
  }) {
    if (note.judged) return;
    note.judged = true;
    _engine.applyMiss(timingScale);
    if (showFeedback) {
      _showMissFeedback(col, note);
      _hitFeedback.playMiss();
    }
    onStateChanged?.call();
    if (_engine.isGameOver) {
      _gameOver();
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
    createExplode(col, centerX, note.currentY, weak: true);
  }

  void createExplode(
    int col,
    double x,
    double y, {
    bool weak = false,
  }) {
    final explodeController = AnimationController(
      duration: Duration(milliseconds: weak ? 220 : 320),
      vsync: vsync,
    );
    final explode = ExplodeAnimation(
      controller: explodeController,
      x: x,
      y: y,
      particles: _generateParticles(weak: weak),
      radius: radius,
      weak: weak,
    );
    explodes.add(explode);
    explodeController.forward().then((_) {
      explodeController.dispose();
      explodes.remove(explode);
    });
  }

  List<Particle> _generateParticles({bool weak = false}) {
    final rng = math.Random();
    final count = weak ? 3 + rng.nextInt(2) : 6 + rng.nextInt(3);
    return List.generate(count, (i) {
      final angle =
          (2 * math.pi * i / count) + (rng.nextDouble() - 0.5) * 0.6;
      return Particle(
        angle: angle,
        distance: (weak ? 10.0 : 18.0) + i * (weak ? 3.0 : 5.0) + rng.nextDouble() * 5,
        initialAlpha: (weak ? 0.35 : 0.65) - i * 0.05,
      );
    });
  }

  // ── 游戏结束 ──

  void _gameOver() {
    if (isExiting) return;
    stopGame();
    saveHighScore();

    final result = GameResult(
      songName: chart.name,
      score: score,
      highScore: highScore,
      perfectCount: perfectCount,
      greatCount: greatCount,
      goodCount: goodCount,
      missCount: missCount,
      maxCombo: maxCombo,
      totalNotes: chart.notes.length,
    );

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
