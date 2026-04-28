import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../lab/lab_container.dart';
import '../models/line_models.dart';
import 'line_page.dart';
import '../models/game_result.dart';
import 'game_result_page.dart';
import 'song_select_page.dart';
import '../settings/line_settings.dart';

/// 音频与游戏同步器 — 定期校准 Stopwatch 消除漂移
class _AudioSyncGuard {
  final AudioPlayer player;
  final Stopwatch stopwatch;
  Timer? _timer;
  int _lastCorrectionTarget = -1;

  _AudioSyncGuard({required this.player, required this.stopwatch});

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _correct());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _correct() {
    // 获取音频当前位置（ms）
    final audioMs = player.position.inMilliseconds;
    final swMs = stopwatch.elapsedMilliseconds;
    final diff = audioMs - swMs;

    if (diff.abs() > 50 && _lastCorrectionTarget != swMs) {
      // 偏差超过 50ms，需要修正
      debugPrint(
        '[SYNC] 修正偏移 audio=${audioMs}ms stopwatch=${swMs}ms diff=${diff}ms',
      );
      player.seek(Duration(milliseconds: swMs));
      // 需要在外部重新 start stopwatch 并补偿
      _lastCorrectionTarget = swMs;
    }
  }

  void dispose() {
    stop();
  }
}

/// 线 Demo
class LineDemo extends DemoPage {
  final ChartData? chart;
  final String? audioPath;

  LineDemo({this.chart, this.audioPath});

  @override
  String get title => '线';

  @override
  String get description => '线';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return _LineDemoPage(chart: chart!, audioPath: audioPath);
  }
}

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

class _LineDemoPage extends StatefulWidget {
  final ChartData chart;
  final String? audioPath;

  const _LineDemoPage({required this.chart, this.audioPath});

  @override
  State<_LineDemoPage> createState() => _LineDemoPageState();
}

class _LineDemoPageState extends State<_LineDemoPage>
    with TickerProviderStateMixin {
  // ── 水动画 ──
  bool _isWaterEntering = true;
  bool _isExiting = false;
  bool _isCountingDown = false;
  int _countdownValue = 3;

  late AnimationController _exitController;
  late AnimationController _enterController;
  late AnimationController _healthController;
  late AnimationController _renderTicker; // 强制每帧重绘

  // ── 谱面 ──
  ChartData? _chart;
  int _nextNoteIndex = 0;
  final Stopwatch _gameStopwatch = Stopwatch();

  // ── 游戏状态 ──
  static const int _columnCount = 3;
  List<List<FallingNote>> _notes = [];
  final List<ExplodeAnimation> _explodes = [];
  final List<JudgeFeedback> _judgeFeedbacks = [];

  // ── 音频 ──
  AudioPlayer? _audioPlayer;
  StreamSubscription? _audioCompletionSub;
  _AudioSyncGuard? _syncGuard;

  // 分数 & 血条
  int _score = 0;
  double _health = 1.0;
  int _highScore = 0;

  // 判定 & 连击计数
  int _perfectCount = 0;
  int _greatCount = 0;
  int _goodCount = 0;
  int _missCount = 0;
  int _maxCombo = 0;
  int _currentCombo = 0;

  BackgroundStyle _backgroundStyle = BackgroundStyle.none;
  static const String _backgroundKey = lineBackgroundKey;
  String _highScoreKey = 'line_demo_high_score'; // 会在 _loadSettings 中按歌曲覆盖

  double _timingScale = 1.0;
  static const String _timingScaleKey = lineTimingScaleKey;

  double _scrollSpeed = 1.0;
  static const String _scrollSpeedKey = lineScrollSpeedKey;

  static const double _noteSizeRatio = 0.168; // 音符大小占列宽的比例（扩大20%）
  static const double _judgeLineRatio = 0.75;

  /// 线性下落时，音符到达判定线的动画进度比例
  double get _judgeProgressRatio {
    final h = MediaQuery.of(context).size.height;
    final r = _radius;
    return (h * _judgeLineRatio + r) / (h + 2 * r);
  }

  // 判定窗口（ms）
  static const int _perfectWindow = 50;
  static const int _greatWindow = 100;
  static const int _goodWindow = 150;
  static const int _missWindow = 200;

  // 手势追踪 — 多指触摸
  final Set<int> _heldColumns = {};
  final Map<int, _PointerState> _pointers = {}; // pointerId → 状态

  // hold 音符完成后需要松手才能激活下一个 hold（防止长按穿透）
  final Set<int> _holdCompletedColumns = {};

  /// 根据列宽计算音符半径，确保音符在不同屏幕上都清晰可见
  double get _radius {
    final w = MediaQuery.of(context).size.width;
    final colWidth = w / _columnCount;
    return colWidth * _noteSizeRatio;
  }

  // 暂停
  bool _wasGameRunning = false;

  @override
  void initState() {
    super.initState();

    _exitController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _enterController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _healthController = AnimationController(
      duration: const Duration(days: 365),
      vsync: this,
    )..repeat();
    _renderTicker = AnimationController(
      duration: const Duration(milliseconds: 16),
      vsync: this,
    )..repeat();

    _notes = List.generate(_columnCount, (_) => []);

    _loadSettings();

    // 初始化音频播放
    if (widget.audioPath != null) {
      _audioPlayer = AudioPlayer();
      final path = widget.audioPath!;
      if (path.startsWith('http://') || path.startsWith('https://')) {
        _audioPlayer!.setUrl(path);
      } else {
        _audioPlayer!.setAsset(path);
      }
    }

    _enterController.value = 1.0;
    _enterController.reverse().then((_) {
      if (!mounted) return;
      setState(() => _isWaterEntering = false);
      _startCountdown();
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final chartData = widget.chart;
      // 使用歌曲名作为 per-song 高分 key
      _highScoreKey = 'line_high_score_${chartData.name.hashCode}';
      if (mounted) {
        setState(() {
          _chart = chartData;
          _timingScale = prefs.getDouble(_timingScaleKey) ?? 1.0;
          _scrollSpeed = prefs.getDouble(_scrollSpeedKey) ?? 1.0;
          _highScore = prefs.getInt(_highScoreKey) ?? 0;
          final bgIndex = prefs.getInt(_backgroundKey) ?? 0;
          _backgroundStyle = BackgroundStyle
              .values[bgIndex.clamp(0, BackgroundStyle.values.length - 1)];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _highScore = prefs.getInt(_highScoreKey) ?? 0;
          _timingScale = prefs.getDouble(_timingScaleKey) ?? 1.0;
          _scrollSpeed = prefs.getDouble(_scrollSpeedKey) ?? 1.0;
        });
      }
    }
  }

  Future<void> _saveHighScore() async {
    final prefs = await SharedPreferences.getInstance();

    // 保存最佳准确率（独立于分数记录）
    final total = _chart?.notes.length ?? 0;
    if (total > 0) {
      final accuracyKey = _highScoreKey.replaceFirst(
        'line_high_score_',
        'line_high_accuracy_',
      );
      final accuracy =
          (_perfectCount * 3 + _greatCount * 2 + _goodCount) /
          (total * 3) *
          100;
      final storedAccuracy = prefs.getDouble(accuracyKey) ?? 0;
      if (accuracy > storedAccuracy) {
        await prefs.setDouble(accuracyKey, accuracy);
      }
    }

    // 保存最高分
    if (_score > _highScore) {
      _highScore = _score;
      await prefs.setInt(_highScoreKey, _highScore);
    }
  }

  @override
  void dispose() {
    _exitController.dispose();
    _enterController.dispose();
    _healthController.dispose();
    _renderTicker.dispose();
    _gameStopwatch.stop();
    _audioCompletionSub?.cancel();
    _syncGuard?.dispose();
    for (final noteList in _notes) {
      for (final note in noteList) {
        note.controller.dispose();
      }
    }
    for (final e in _explodes) {
      e.controller.dispose();
    }
    for (final fb in _judgeFeedbacks) {
      fb.controller.dispose();
    }
    _audioPlayer?.dispose();
    _pointers.clear();
    _heldColumns.clear();
    _holdCompletedColumns.clear();
    super.dispose();
  }

  // ── 游戏开始 ──

  void _startGame() {
    _nextNoteIndex = 0;
    _gameStopwatch.reset();
    _gameStopwatch.start();
    _spawnPendingNotes();
    // 播放音乐
    _audioPlayer?.play();

    // 监听音频播放完成 → 自动进入评分
    _audioCompletionSub?.cancel();
    _audioCompletionSub = _audioPlayer?.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_isExiting && mounted) {
        debugPrint('[AUDIO_COMPLETE] 音乐播放结束，自动进入评分');
        _gameOver();
      }
    });

    // 启动音画同步校准
    if (_audioPlayer != null) {
      _syncGuard?.stop();
      _syncGuard = _AudioSyncGuard(
        player: _audioPlayer!,
        stopwatch: _gameStopwatch,
      );
      _syncGuard!.start();
    }
  }

  void _stopGame() {
    _gameStopwatch.stop();
    _syncGuard?.stop();
    _audioPlayer?.pause();
    for (final noteList in _notes) {
      for (final note in noteList) {
        note.controller.stop();
      }
    }
  }

  void _spawnPendingNotes() {
    if (_chart == null || _isExiting) return;
    final elapsed = _gameStopwatch.elapsedMilliseconds;
    final dropMs = _chart!.dropDuration;

    while (_nextNoteIndex < _chart!.notes.length) {
      final event = _chart!.notes[_nextNoteIndex];
      final actualDropMs = dropMs / _scrollSpeed;
      final spawnTime =
          event.time - (actualDropMs * _judgeProgressRatio).round();
      if (elapsed >= spawnTime) {
        _spawnNote(event);
        _nextNoteIndex++;
      } else {
        break;
      }
    }

    if (_nextNoteIndex < _chart!.notes.length && !_isExiting) {
      final nextEvent = _chart!.notes[_nextNoteIndex];
      final nextActualDropMs = dropMs / _scrollSpeed;
      final nextSpawnTime =
          nextEvent.time - (nextActualDropMs * _judgeProgressRatio).round();
      final delayMs = (nextSpawnTime - elapsed).clamp(1, 100);
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (mounted && !_isExiting) _spawnPendingNotes();
      });
    }
  }

  void _spawnNote(NoteEvent event) {
    final screenSize = MediaQuery.of(context).size;
    final radius = _radius;

    final actualDropMs = (_chart!.dropDuration / _scrollSpeed).round();
    final controller = AnimationController(
      duration: Duration(milliseconds: actualDropMs),
      vsync: this,
    );

    final note = FallingNote(
      event: event,
      controller: controller,
      currentY: -radius,
    );

    note.spawnElapsed = _gameStopwatch.elapsedMilliseconds;
    debugPrint(
      '[SPAWN] elapsed=${note.spawnElapsed} event.time=${event.time} col=${event.column} type=${event.type}',
    );

    controller.addListener(() {
      // 音符持续下落（线性匀速）
      final targetY = screenSize.height + radius;
      note.currentY = -radius + (targetY + radius) * controller.value;

      if (!note.judged && event.type != NoteType.hold) {
        final elapsed = _gameStopwatch.elapsedMilliseconds;
        final missThreshold = event.time + (_missWindow * _timingScale).round();
        if (elapsed > missThreshold) {
          debugPrint(
            '[AUTO_MISS] elapsed=$elapsed event.time=${event.time} col=${event.column}',
          );
          _onNoteMissed(
            _notes.indexOf(_notes.firstWhere((col) => col.contains(note))),
            note,
          );
        }
      }

      if (event.type == NoteType.hold && note.holding && !note.judged) {
        final elapsed = _gameStopwatch.elapsedMilliseconds;
        final heldTime = elapsed - note.holdPressTime;
        note.holdProgress = (heldTime / event.holdDuration!).clamp(0.0, 1.0);
        // 详细日志：每 50ms 输出一次 hold 状态
        if ((elapsed ~/ 50) != (note.holdPressTime ~/ 50)) {
          debugPrint(
            '[HOLD_FRAME] elapsed=$elapsed col=${event.column} progress=${(note.holdProgress * 100).toStringAsFixed(0)}% heldTime=${heldTime}ms/${event.holdDuration}ms headY=${note.currentY.toStringAsFixed(0)}',
          );
        }
        if (note.holdProgress >= 1.0) {
          debugPrint(
            '[HOLD_COMPLETE] elapsed=$elapsed col=${event.column} totalHeldTime=${heldTime}ms',
          );
          _judgeNote(event.column, note, note.holdJudgeDiff);
          note.holding = false;
          // 标记该列需要松手后才能激活下一个 hold 音符
          _holdCompletedColumns.add(event.column);
        }
        return;
      }

      // 未按时 hold 音符的静默移除（不判 miss、不扣血）
      if (!note.judged && event.type == NoteType.hold && !note.holding) {
        final elapsed = _gameStopwatch.elapsedMilliseconds;
        final missThreshold = event.time + (_missWindow * _timingScale).round();
        if (elapsed > missThreshold) {
          debugPrint(
            '[HOLD_AUTO_SILENT] elapsed=$elapsed col=${event.column} event.time=${event.time} (never pressed)',
          );
          _silentFadeOutHold(
            _notes.indexOf(_notes.firstWhere((col) => col.contains(note))),
            note,
          );
        }
      }
    });

    setState(() {
      _notes[event.column].add(note);
    });

    controller.forward().then((_) {
      if (!mounted) return;
      if (note.removeMe) return; // 已被判定移除，不再重复处理
      // hold 音符未判定时不能 dispose 或移除，由 auto-miss 或 hold 完成回调处理
      if (event.type == NoteType.hold) {
        Future.delayed(Duration(milliseconds: event.holdDuration ?? 0), () {
          if (!mounted) return;
          if (!_notes[event.column].contains(note)) return;
          note.controller.dispose();
          setState(() => _notes[event.column].remove(note));
        });
        return;
      }
      note.controller.dispose();
      setState(() => _notes[event.column].remove(note));
    });
  }

  // ── 手势处理（多指触摸） ──

  int? _getColumnFromX(double x) {
    final w = MediaQuery.of(context).size.width;
    final colWidth = w / _columnCount;
    for (int i = 0; i < _columnCount; i++) {
      if (x >= colWidth * i && x < colWidth * (i + 1)) return i;
    }
    return null;
  }

  SlideDirection? _getSwipeDirection(Offset velocity) {
    const threshold = 100.0;
    final dx = velocity.dx.abs();
    final dy = velocity.dy.abs();
    if (dx < threshold && dy < threshold) return null;
    if (dx > dy) {
      return velocity.dx > 0 ? SlideDirection.right : SlideDirection.left;
    } else {
      return velocity.dy > 0 ? SlideDirection.down : SlideDirection.up;
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_isExiting || _isCountingDown || _chart == null) return;
    final col = _getColumnFromX(event.localPosition.dx);
    if (col == null) return;

    final now = DateTime.now();
    _pointers[event.pointer] = _PointerState(
      pointerId: event.pointer,
      column: col,
      startPosition: event.position,
      lastPosition: event.position,
      pressTime: now,
    );

    final elapsed = _gameStopwatch.elapsedMilliseconds;
    debugPrint('[PRESS] elapsed=$elapsed col=$col pointer=${event.pointer}');
    _handleColumnPress(col);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final state = _pointers[event.pointer];
    if (state == null) return;
    state.lastPosition = event.position;
  }

  void _handlePointerUp(PointerUpEvent event) {
    final state = _pointers.remove(event.pointer);
    if (state == null) return;

    final elapsed = _gameStopwatch.elapsedMilliseconds;
    final col = state.column;
    final pressDuration = DateTime.now()
        .difference(state.pressTime)
        .inMilliseconds;
    final displacement = (event.position - state.startPosition).distance;

    debugPrint(
      '[RELEASE] elapsed=$elapsed col=$col pointer=${event.pointer} duration=${pressDuration}ms disp=${displacement.toStringAsFixed(0)}',
    );

    // 短按 + 位移小 → 视为 Tap
    if (pressDuration < 300 && displacement < 20) {
      debugPrint('[TAP] elapsed=$elapsed col=$col');
      _handleColumnTap(col);
      // tap 后也释放 hold（如果之前 press 触发了 hold）
      _handleColumnRelease(col);
      return;
    }

    // 长按 → 释放 hold
    _handleColumnRelease(col);

    // 滑动检测
    final velocity =
        (event.position - state.startPosition) / (pressDuration / 1000.0);
    if (velocity.distance > 50) {
      final dir = _getSwipeDirection(velocity);
      if (dir != null) {
        debugPrint('[SWIPE] elapsed=$elapsed col=$col dir=$dir');
        _handleSwipe(col, dir);
      }
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    final state = _pointers.remove(event.pointer);
    if (state == null) return;
    _handleColumnRelease(state.column);
  }

  // ── 判定 ──

  void _handleColumnTap(int col) {
    if (_chart == null) return;
    final elapsed = _gameStopwatch.elapsedMilliseconds;
    FallingNote? best;
    final scaledMissWindow = (_missWindow * _timingScale).round();
    int bestDiff = scaledMissWindow + 1;

    for (final note in _notes[col]) {
      if (note.judged) continue;
      if (note.event.type != NoteType.tap) continue;
      final diff = (elapsed - note.event.time).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = note;
      }
    }

    if (best != null && bestDiff <= scaledMissWindow) {
      _judgeNote(col, best, bestDiff);
    }
  }

  void _handleColumnPress(int col) {
    if (_chart == null) return;
    // 上一个 hold 完成后必须松手再按，防止长按穿透到下一个 hold
    if (_holdCompletedColumns.contains(col)) return;
    final elapsed = _gameStopwatch.elapsedMilliseconds;
    final scaledMissWindow = (_missWindow * _timingScale).round();

    // 如果该列有当前应按的 tap/slide 音符（在判定窗口内），先处理它们，不激活 hold
    // 注意：只阻塞"当前时刻应该按的"音符，不阻塞已 spawn 但还没到的未来音符
    for (final note in _notes[col]) {
      if (!note.judged && note.event.type != NoteType.hold) {
        final diff = (elapsed - note.event.time).abs();
        if (diff <= scaledMissWindow) return; // 在 ±missWindow 内，不激活 hold
      }
    }

    // 找到这一列中第一个未判定的 hold 音符
    FallingNote? foundNote;
    String skipReason = '';
    for (final note in _notes[col]) {
      if (note.event.type != NoteType.hold) continue;
      if (note.judged) {
        skipReason = 'alreadyJudged';
        continue;
      }
      final missThreshold = note.event.time + scaledMissWindow;
      if (elapsed > missThreshold) {
        skipReason = 'pastMissThreshold';
        continue;
      }
      foundNote = note;
      break;
    }

    if (foundNote != null) {
      final diff = (elapsed - foundNote.event.time).abs();
      debugPrint(
        '[HOLD_PRESS] elapsed=$elapsed col=$col event.time=${foundNote.event.time} diff=${diff}ms holdDuration=${foundNote.event.holdDuration}ms found=YES',
      );
      foundNote.holding = true;
      foundNote.holdJudgeDiff = diff;
      foundNote.holdPressTime = elapsed;
      _heldColumns.add(col);
    } else {
      // 未找到音符，打印列状态
      int holdCount = 0, tapCount = 0, judgedCount = 0;
      for (final n in _notes[col]) {
        if (n.event.type == NoteType.hold && !n.judged) holdCount++;
        if (n.event.type == NoteType.tap) tapCount++;
        if (n.judged) judgedCount++;
      }
      debugPrint(
        '[HOLD_PRESS] elapsed=$elapsed col=$col found=NO reason=$skipReason columnState: hold=$holdCount tap=$tapCount judged=$judgedCount total=${_notes[col].length}',
      );
    }
  }

  void _handleColumnRelease(int col) {
    if (!_heldColumns.contains(col)) {
      debugPrint(
        '[HOLD_RELEASE] elapsed=${_gameStopwatch.elapsedMilliseconds} col=$col notInHeldColumns',
      );
      // 即使不在 _heldColumns 中，也清除 holdCompleted 标记
      // 这样松手后再次按下可以正常激活
      _holdCompletedColumns.remove(col);
      return;
    }
    _heldColumns.remove(col);
    _holdCompletedColumns.remove(col);

    final elapsed = _gameStopwatch.elapsedMilliseconds;

    for (final note in _notes[col]) {
      if (!note.holding || note.judged) continue;
      if (note.event.type != NoteType.hold) continue;

      final heldTime = elapsed - note.holdPressTime;
      final requiredTime = (note.event.holdDuration! * 0.8).round();
      debugPrint(
        '[HOLD_RELEASE] elapsed=$elapsed col=$col heldTime=${heldTime}ms required=${requiredTime}ms holdProgress=${(note.holdProgress * 100).toStringAsFixed(0)}%',
      );
      if (heldTime >= note.event.holdDuration! * 0.8) {
        _judgeNote(col, note, note.holdJudgeDiff);
      } else {
        debugPrint(
          '[HOLD_RELEASE_SILENT] col=$col heldTime=${heldTime}ms < ${note.event.holdDuration}ms * 0.8',
        );
        _silentFadeOutHold(col, note);
      }
      note.holding = false;
      return;
    }
  }

  void _handleSwipe(int col, SlideDirection direction) {
    if (_chart == null) return;
    final elapsed = _gameStopwatch.elapsedMilliseconds;

    for (final note in _notes[col]) {
      if (note.judged || note.event.type != NoteType.slide) continue;
      final diff = (elapsed - note.event.time).abs();
      if (diff <= (_goodWindow * _timingScale).round() &&
          note.event.direction == direction) {
        _judgeNote(col, note, diff);
        return;
      }
    }
  }

  void _judgeNote(int col, FallingNote note, int timeDiffMs) {
    note.judged = true;
    note.removeMe = true;

    String judgeText;
    double judgeAlpha;
    int points;
    double healthChange;

    final scaledPerfect = (_perfectWindow * _timingScale).round();
    final scaledGreat = (_greatWindow * _timingScale).round();
    final scaledGood = (_goodWindow * _timingScale).round();
    // 奖励/惩罚与 timingScale 成反比：越严格（scale 小），奖励越多/惩罚越重
    final healthScale = 1.0 / _timingScale;

    if (timeDiffMs <= scaledPerfect) {
      judgeText = 'Perfect';
      judgeAlpha = 0.6;
      points = 3;
      healthChange = 0.05 * healthScale;
    } else if (timeDiffMs <= scaledGreat) {
      judgeText = 'Great';
      judgeAlpha = 0.4;
      points = 2;
      healthChange = 0.02 * healthScale;
    } else if (timeDiffMs <= scaledGood) {
      judgeText = 'Good';
      judgeAlpha = 0.25;
      points = 1;
      healthChange = 0.0;
    } else {
      // Fallback (shouldn't reach here since caller already checked Good window)
      judgeText = 'Good';
      judgeAlpha = 0.25;
      points = 1;
      healthChange = 0.0;
    }

    final screenSize = MediaQuery.of(context).size;
    final w = screenSize.width;
    final h = screenSize.height;
    final colWidth = w / _columnCount;
    final centerX = colWidth * col + colWidth / 2;
    final radius = _radius;
    final judgeY = h * _judgeLineRatio;

    final feedbackController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    final feedback = JudgeFeedback(
      text: judgeText,
      x: centerX,
      y: judgeY - radius * 3, // 判定线上方固定位置
      color: Theme.of(context).colorScheme.primary,
      baseAlpha: judgeAlpha,
      controller: feedbackController,
    );

    // 更新判定计数和连击
    if (judgeText == 'Perfect') {
      _perfectCount++;
      _currentCombo++;
    } else if (judgeText == 'Great') {
      _greatCount++;
      _currentCombo++;
    } else {
      _goodCount++;
      _currentCombo++;
    }
    _maxCombo = math.max(_maxCombo, _currentCombo);

    setState(() {
      _score += points;
      _health = (_health + healthChange).clamp(0.0, 1.0);
      _judgeFeedbacks.add(feedback);
    });

    feedbackController.forward().then((_) {
      feedbackController.dispose();
      if (!mounted) return;
      setState(() => _judgeFeedbacks.remove(feedback));
    });

    _createExplode(col, centerX, note.currentY, radius);

    if (note.event.type == NoteType.hold) {
      // Hold 音符：不停止控制器，继续自然下落离开屏幕，由 .then() 回收
      note.removeMe = false;
    } else {
      note.controller.stop();
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() => _notes[col].remove(note));
        note.controller.dispose();
      });
    }
  }

  void _onNoteMissed(int col, FallingNote note) {
    if (note.judged) return;
    note.judged = true;
    _missCount++;
    _currentCombo = 0;
    final healthScale = 1.0 / _timingScale;
    setState(() {
      _health = (_health - 0.15 * healthScale).clamp(0.0, 1.0);
    });
    if (_health <= 0.0) {
      _gameOver();
    }

    if (note.event.type == NoteType.hold) {
      _silentFadeOutHold(col, note);
    } else {
      note.removeMe = true;
      note.controller.stop();
    }
  }

  /// Hold 音符静默处理：不判 miss、不扣血、不断 combo，继续自然下落
  void _silentFadeOutHold(int col, FallingNote note) {
    if (note.holdFadeOut > 0) return;
    note.judged = true;
    note.removeMe = false;
    note.holding = false;
    if (note.holdPressTime > 0) {
      final heldTime = (_gameStopwatch.elapsedMilliseconds - note.holdPressTime)
          .clamp(0, note.event.holdDuration!);
      note.holdProgress = (heldTime / note.event.holdDuration!).clamp(0.0, 1.0);
    }
    note.holdFadeOut = 1.0;
    // 不停止控制器，让音符保持当前填充状态继续下落离开屏幕，由 .then() 回收
  }

  void _createExplode(int col, double x, double y, double radius) {
    final explodeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    final explode = ExplodeAnimation(
      controller: explodeController,
      x: x,
      y: y,
      particles: _generateParticles(),
      radius: radius,
    );
    setState(() => _explodes.add(explode));
    explodeController.forward().then((_) {
      explodeController.dispose();
      if (!mounted) return;
      setState(() => _explodes.remove(explode));
    });
  }

  List<Particle> _generateParticles() {
    final rng = math.Random();
    final count = 4 + rng.nextInt(2);
    final particles = <Particle>[];
    final baseAngles = List.generate(count, (i) => (2 * math.pi * i / count));
    final distances = List.generate(count, (i) => 15.0 + i * 5.0);
    final alphas = List.generate(count, (i) => 0.5 - i * 0.1);

    for (int i = 0; i < count; i++) {
      final angle = baseAngles[i] + (rng.nextDouble() - 0.5) * 0.6;
      particles.add(
        Particle(
          angle: angle,
          distance: distances[i] + rng.nextDouble() * 5,
          initialAlpha: alphas[i],
        ),
      );
    }
    return particles;
  }

  // ── 游戏控制 ──

  void _gameOver() {
    if (_isExiting) return;
    _stopGame();
    _audioCompletionSub?.cancel();
    _syncGuard?.dispose();
    _audioPlayer?.stop();
    for (final noteList in _notes) {
      for (final note in noteList) {
        note.controller.stop();
      }
    }
    _saveHighScore();

    // 构建结果数据
    final result = GameResult(
      songName: _chart?.name ?? 'Unknown',
      score: _score,
      highScore: _highScore,
      perfectCount: _perfectCount,
      greatCount: _greatCount,
      goodCount: _goodCount,
      missCount: _missCount,
      maxCombo: _maxCombo,
      totalNotes: _chart?.notes.length ?? 0,
    );

    // 播放水退场动画，然后导航到评分页
    setState(() => _isExiting = true);
    _exitController.reset();
    _exitController.forward().then((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GameResultPage(
            result: result,
            chart: widget.chart,
            audioPath: widget.audioPath,
          ),
        ),
      );
    });
  }

  Future<void> _handleExit() async {
    if (_isExiting) return;
    _stopGame();
    _audioCompletionSub?.cancel();
    _syncGuard?.dispose();
    _audioPlayer?.stop();
    await _saveHighScore();
    for (final noteList in _notes) {
      for (final note in noteList) {
        note.controller.stop();
      }
    }
    setState(() => _isExiting = true);
    await _exitController.forward();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SongSelectPage()),
      );
    }
  }

  void _showSpeedSettings() {
    _wasGameRunning = !(_isExiting) && !_isCountingDown;
    _isCountingDown = false;

    _stopGame();
    for (final noteList in _notes) {
      for (final note in noteList) {
        note.controller.stop();
      }
    }
    for (final e in _explodes) {
      e.controller.stop();
    }

    Navigator.of(context)
        .push<void>(
          MaterialPageRoute(
            builder: (context) => SpeedSettingsPage(
              primaryColor: Theme.of(context).colorScheme.primary,
            ),
          ),
        )
        .then((_) {
          if (!mounted || _isExiting) return;
          _loadSettings().then((_) {
            if (_isExiting) {
              // 游戏结束时，点击设置返回应该保持游戏结束状态
              return;
            } else {
              // 倒计时时或游戏进行中返回，都重新开始倒计时
              _startCountdown();
            }
          });
        });
  }

  void _startCountdown() {
    setState(() {
      _isCountingDown = true;
      _countdownValue = 3;
    });

    void tick(int remaining) {
      if (!mounted) return;
      setState(() => _countdownValue = remaining);
      if (remaining <= 0) {
        setState(() => _isCountingDown = false);
        _resumeFromSnapshot();
        return;
      }
      Future.delayed(
        const Duration(milliseconds: 800),
        () => tick(remaining - 1),
      );
    }

    tick(3);
  }

  void _resumeFromSnapshot() {
    if (!_wasGameRunning) {
      _startGame();
      return;
    }

    _gameStopwatch.start();
    // 同步音频位置
    _audioPlayer?.seek(
      Duration(milliseconds: _gameStopwatch.elapsedMilliseconds),
    );
    _audioPlayer?.play();
    _syncGuard?.start();
    for (final noteList in _notes) {
      for (final note in noteList) {
        if (!note.judged) {
          note.controller.forward();
        }
      }
    }
    for (final e in _explodes) {
      e.controller.forward();
    }
    _spawnPendingNotes();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final w = screenSize.width;
    final h = screenSize.height;
    final radius = _radius;
    final judgeY = h * _judgeLineRatio;

    final allControllers = <AnimationController>[];
    for (final col in _notes) {
      for (final note in col) {
        allControllers.add(note.controller);
      }
    }
    for (final e in _explodes) {
      allControllers.add(e.controller);
    }
    for (final fb in _judgeFeedbacks) {
      allControllers.add(fb.controller);
    }
    allControllers.add(_healthController);
    allControllers.add(_renderTicker);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleExit();
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: Listenable.merge(allControllers),
                  builder: (context, _) {
                    return CustomPaint(
                      painter: GamePainter(
                        columns: _notes,
                        explodes: _explodes,
                        color: theme.colorScheme.primary,
                        radius: radius,
                        screenWidth: w,
                        screenHeight: h,
                        columnCount: _columnCount,
                        judgeY: judgeY,
                        judgeFeedbacks: _judgeFeedbacks,
                        backgroundStyle: _backgroundStyle,
                        health: _health,
                        dropDuration: _chart!.dropDuration.toDouble(),
                        scrollSpeed: _scrollSpeed,
                        gameElapsed: _gameStopwatch.elapsedMilliseconds,
                      ),
                    );
                  },
                ),
              ),

              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                child: IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  onPressed: _handleExit,
                ),
              ),

              Positioned(
                top: MediaQuery.of(context).padding.top + 18,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '$_score/$_highScore',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w200,
                      color: theme.colorScheme.primary.withValues(alpha: 0.6),
                      fontFeatures: [const FontFeature.tabularFigures()],
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),

              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                right: 16,
                child: IconButton(
                  icon: Icon(
                    Icons.settings_outlined,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  onPressed: _isExiting || _isCountingDown
                      ? null
                      : _showSpeedSettings,
                ),
              ),

              if (_isCountingDown)
                Positioned.fill(
                  child: Center(
                    child: Text(
                      '$_countdownValue',
                      style: TextStyle(
                        fontSize: 120 * w / 750,
                        fontWeight: FontWeight.w100,
                        color: theme.colorScheme.primary.withValues(alpha: 0.4),
                        height: 1,
                        letterSpacing: -2,
                      ),
                    ),
                  ),
                ),

              if (_isWaterEntering)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _enterController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: WaterExitPainter(
                          progress: _enterController.value,
                          color: theme.colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ),

              if (_isExiting)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _exitController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: WaterExitPainter(
                          progress: _exitController.value,
                          color: theme.colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Public-facing widget that accepts ChartData parameter
class LineDemoPage extends StatelessWidget {
  final ChartData chart;

  const LineDemoPage({super.key, required this.chart});

  @override
  Widget build(BuildContext context) {
    return _LineDemoPage(chart: chart);
  }
}

void registerLineDemo() {
  demoRegistry.register(LineDemo());
}
