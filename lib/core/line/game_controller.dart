import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'io/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain/chart_data.dart';
import 'domain/constants.dart';
import 'domain/note_event.dart';
import 'domain/particle.dart';
import 'domain/game_result.dart';
import 'presentation/falling_note.dart';
import 'settings/line_settings.dart';
import 'engine/judge_service.dart';
import 'engine/touch_state.dart';
import 'engine/game_engine.dart';

/// 每根手指的触摸状态
class _PointerState {
  final int pointerId;
  int column;
  Offset startPosition;
  Offset lastPosition;
  DateTime pressTime;

  _PointerState({
    required this.pointerId,
    required this.column,
    required this.startPosition,
    required this.lastPosition,
    required this.pressTime,
  });
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

  // ── 常量 ──
  static const int columnCount = 3;
  static const double noteSizeRatio = 0.168;
  static const double judgeLineRatio = 0.75;
  static const int perfectWindow = 50;
  static const int greatWindow = 100;
  static const int goodWindow = 150;
  static const int missWindow = 200;

  double get radius => screenWidth / columnCount * noteSizeRatio;
  double get judgeY => screenHeight * judgeLineRatio;
  double get _judgeProgressRatio => (screenHeight * judgeLineRatio + radius) / (screenHeight + 2 * radius);

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

  int highScore = 0;
  final GameEngine _engine = GameEngine();

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
  bool wasGameRunning = false;

  // ── 手势追踪 ──
  final Set<int> heldColumns = {};
  final Map<int, _PointerState> _pointers = {};
  final Set<int> holdCompletedColumns = {};

  // ── 生命周期 ──

  Future<void> init() async {
    await _loadSettings();
    if (audioPath != null) {
      _audioService = AudioService(gameStopwatch: gameStopwatch, audioPath: audioPath!);
      _audioService!.init();
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
    _engine.reset();
  }

  void dispose() {
    gameStopwatch.stop();
    _audioService?.dispose();
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
    highScore = prefs.getInt(highScoreKey) ?? 0;
    final bgIndex = prefs.getInt(lineBackgroundKey) ?? 0;
    backgroundStyle = BackgroundStyle.values[bgIndex.clamp(0, BackgroundStyle.values.length - 1)];
    onStateChanged?.call();
  }

  Future<void> saveHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    final total = chart.notes.length;
    if (total > 0) {
      final accuracyKey = highScoreKey.replaceFirst('line_high_score_', 'line_high_accuracy_');
      final accuracy = (perfectCount * 3 + greatCount * 2 + goodCount) / (total * 3) * 100;
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
    Future.delayed(const Duration(milliseconds: 800), () => _tickCountdown(remaining - 1));
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
    final elapsed = gameStopwatch.elapsedMilliseconds;
    final dropMs = chart.dropDuration;

    while (nextNoteIndex < chart.notes.length) {
      final event = chart.notes[nextNoteIndex];
      final actualDropMs = dropMs / scrollSpeed;
      final spawnTime = event.time - (actualDropMs * _judgeProgressRatio).round();
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
      final nextSpawnTime = nextEvent.time - (nextActualDropMs * _judgeProgressRatio).round();
      final delayMs = (nextSpawnTime - elapsed).clamp(1, 100);
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (!isExiting) spawnPendingNotes();
      });
    }
  }

  void spawnNote(NoteEvent event) {
    final actualDropMs = (chart.dropDuration / scrollSpeed).round();
    final controller = AnimationController(duration: Duration(milliseconds: actualDropMs), vsync: vsync);

    final note = FallingNote(event: event, controller: controller, currentY: -radius);
    note.spawnElapsed = gameStopwatch.elapsedMilliseconds;

    controller.addListener(() {
      final targetY = screenHeight + radius;
      note.currentY = -radius + (targetY + radius) * controller.value;

      if (!note.judged && event.type != NoteType.hold) {
        final elapsed = gameStopwatch.elapsedMilliseconds;
        final missThreshold = event.time + (missWindow * timingScale).round();
        if (elapsed > missThreshold) {
          final col = notes.indexWhere((col) => col.contains(note));
          if (col >= 0) onNoteMissed(col, note);
        }
      }

      if (event.type == NoteType.hold && note.holding && !note.judged) {
        final elapsed = gameStopwatch.elapsedMilliseconds;
        final heldTime = elapsed - note.holdPressTime;
        note.holdProgress = (heldTime / event.holdDuration!).clamp(0.0, 1.0);
        if (note.holdProgress >= 1.0) {
          judgeNote(event.column, note, note.holdJudgeDiff);
          note.holding = false;
          holdCompletedColumns.add(event.column);
        }
        return;
      }

      if (!note.judged && event.type == NoteType.hold && !note.holding) {
        final elapsed = gameStopwatch.elapsedMilliseconds;
        final missThreshold = event.time + (missWindow * timingScale).round();
        if (elapsed > missThreshold) {
          final col = notes.indexWhere((col) => col.contains(note));
          if (col >= 0) silentFadeOutHold(col, note);
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

  // ── 手势处理 ──

  int? _getColumnFromX(double x) =>
      columnFromX(x, screenWidth, columnCount);

  SlideDirection? _getSwipeDirection(Offset velocity) =>
      swipeDirection(velocity.dx, velocity.dy);

  void handlePointerDown(PointerDownEvent event) {
    if (isExiting || isCountingDown) return;
    final col = _getColumnFromX(event.localPosition.dx);
    if (col == null) return;

    _pointers[event.pointer] = _PointerState(
      pointerId: event.pointer,
      column: col,
      startPosition: event.position,
      lastPosition: event.position,
      pressTime: DateTime.now(),
    );

    _handleColumnPress(col);
  }

  void handlePointerMove(PointerMoveEvent event) {
    final state = _pointers[event.pointer];
    if (state == null) return;
    state.lastPosition = event.position;
  }

  void handlePointerUp(PointerUpEvent event) {
    final state = _pointers.remove(event.pointer);
    if (state == null) return;

    final col = state.column;
    final pressDuration = DateTime.now().difference(state.pressTime).inMilliseconds;
    final displacement = (event.position - state.startPosition).distance;

    if (pressDuration < 300 && displacement < 20) {
      _handleColumnTap(col);
      _handleColumnRelease(col);
      return;
    }

    _handleColumnRelease(col);

    final velocity = (event.position - state.startPosition) / (pressDuration / 1000.0);
    if (velocity.distance > 50) {
      final dir = _getSwipeDirection(velocity);
      if (dir != null) _handleSwipe(col, dir);
    }
  }

  void handlePointerCancel(PointerCancelEvent event) {
    final state = _pointers.remove(event.pointer);
    if (state == null) return;
    _handleColumnRelease(state.column);
  }

  // ── 判定 ──

  void _handleColumnTap(int col) {
    final elapsed = gameStopwatch.elapsedMilliseconds;
    FallingNote? best;
    final scaledMissWindow = (missWindow * timingScale).round();
    int bestDiff = scaledMissWindow + 1;

    for (final note in notes[col]) {
      if (note.judged) continue;
      if (note.event.type != NoteType.tap) continue;
      final diff = (elapsed - note.event.time).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = note;
      }
    }

    if (best != null && bestDiff <= scaledMissWindow) {
      judgeNote(col, best, bestDiff);
    }
  }

  void _handleColumnPress(int col) {
    if (holdCompletedColumns.contains(col)) return;
    final elapsed = gameStopwatch.elapsedMilliseconds;
    final scaledMissWindow = (missWindow * timingScale).round();

    for (final note in notes[col]) {
      if (!note.judged && note.event.type != NoteType.hold) {
        final diff = (elapsed - note.event.time).abs();
        if (diff <= scaledMissWindow) return;
      }
    }

    FallingNote? foundNote;
    for (final note in notes[col]) {
      if (note.event.type != NoteType.hold) continue;
      if (note.judged) continue;
      final signedDiff = elapsed - note.event.time;
      if (signedDiff < -scaledMissWindow) break;
      if (signedDiff > scaledMissWindow) continue;
      foundNote = note;
      break;
    }

    if (foundNote != null) {
      foundNote.holding = true;
      foundNote.holdJudgeDiff = (elapsed - foundNote.event.time).abs();
      foundNote.holdPressTime = elapsed;
      heldColumns.add(col);
    }
  }

  void _handleColumnRelease(int col) {
    if (!heldColumns.contains(col)) {
      holdCompletedColumns.remove(col);
      return;
    }
    heldColumns.remove(col);
    holdCompletedColumns.remove(col);

    final elapsed = gameStopwatch.elapsedMilliseconds;
    for (final note in notes[col]) {
      if (!note.holding || note.judged) continue;
      if (note.event.type != NoteType.hold) continue;

      final heldTime = elapsed - note.holdPressTime;
      if (heldTime >= note.event.holdDuration! * 0.8) {
        judgeNote(col, note, note.holdJudgeDiff);
      } else {
        silentFadeOutHold(col, note);
      }
      note.holding = false;
      return;
    }
  }

  void _handleSwipe(int col, SlideDirection direction) {
    final elapsed = gameStopwatch.elapsedMilliseconds;
    for (final note in notes[col]) {
      if (note.judged || note.event.type != NoteType.slide) continue;
      final diff = (elapsed - note.event.time).abs();
      if (diff <= (goodWindow * timingScale).round() && note.event.direction == direction) {
        judgeNote(col, note, diff);
        return;
      }
    }
  }

  void judgeNote(int col, FallingNote note, int timeDiffMs) {
    note.judged = true;
    note.removeMe = true;

    final result = judge(timeDiffMs, timingScale);
    _engine.applyJudge(result);

    final colWidth = screenWidth / columnCount;
    final centerX = colWidth * col + colWidth / 2;

    final feedbackController = AnimationController(duration: const Duration(milliseconds: 600), vsync: vsync);
    final feedback = JudgeFeedback(
      text: result.text,
      x: centerX,
      y: judgeY - radius * 3,
      color: themeColor,
      baseAlpha: result.alpha,
      controller: feedbackController,
    );
    judgeFeedbacks.add(feedback);

    feedbackController.forward().then((_) {
      feedbackController.dispose();
      judgeFeedbacks.remove(feedback);
    });

    createExplode(col, centerX, note.currentY);
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

  void onNoteMissed(int col, FallingNote note) {
    if (note.judged) return;
    note.judged = true;
    _engine.applyMiss(timingScale);
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
      final heldTime = (gameStopwatch.elapsedMilliseconds - note.holdPressTime).clamp(0, note.event.holdDuration!);
      note.holdProgress = (heldTime / note.event.holdDuration!).clamp(0.0, 1.0);
    }
    note.holdFadeOut = 1.0;
  }

  // ── 视觉 ──

  void createExplode(int col, double x, double y) {
    final explodeController = AnimationController(duration: const Duration(milliseconds: 300), vsync: vsync);
    final explode = ExplodeAnimation(
      controller: explodeController,
      x: x,
      y: y,
      particles: _generateParticles(),
      radius: radius,
    );
    explodes.add(explode);
    explodeController.forward().then((_) {
      explodeController.dispose();
      explodes.remove(explode);
    });
  }

  List<Particle> _generateParticles() {
    final rng = math.Random();
    final count = 4 + rng.nextInt(2);
    return List.generate(count, (i) {
      final angle = (2 * math.pi * i / count) + (rng.nextDouble() - 0.5) * 0.6;
      return Particle(angle: angle, distance: 15.0 + i * 5.0 + rng.nextDouble() * 5, initialAlpha: 0.5 - i * 0.1);
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
