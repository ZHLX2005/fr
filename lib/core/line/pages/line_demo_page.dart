import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../lab/lab_container.dart';
import '../models/line_models.dart';
import 'line_page.dart';
import '../settings/line_settings.dart';

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

  // 分数 & 血条
  int _score = 0;
  double _health = 1.0;
  int _highScore = 0;
  bool _isGameOver = false;

  BackgroundStyle _backgroundStyle = BackgroundStyle.none;
  static const String _backgroundKey = lineBackgroundKey;
  static const String _highScoreKey = 'line_demo_high_score';

  double _timingScale = 1.0;
  static const String _timingScaleKey = lineTimingScaleKey;

  double _scrollSpeed = 1.0;
  static const String _scrollSpeedKey = lineScrollSpeedKey;

  static const double _circleRadiusRpx = 20.0;
  static const double _judgeLineRatio = 0.75;

// easeOut 曲线下，到达 judgeLineRatio 位置的动画进度：1-sqrt(0.25) ≈ 0.5
  static const double _easeInToJudgeRatio = 0.5;

  // 判定窗口（ms）
  static const int _perfectWindow = 50;
  static const int _greatWindow = 100;
  static const int _goodWindow = 150;
  static const int _missWindow = 200;

  // 手势追踪
  final Set<int> _heldColumns = {};
  Offset? _panStart;
  int? _panColumn;

  double _rpx(double value) => value * MediaQuery.of(context).size.width / 750;

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
      _audioPlayer!.setAsset(widget.audioPath!);
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
      ChartData? chartData;
      if (widget.chart != null) {
        chartData = widget.chart;
      } else {
        final chartJson = await rootBundle.loadString('assets/charts/test_chart.json');
        chartData = ChartData.fromJson(jsonDecode(chartJson));
      }
      if (mounted) {
        setState(() {
          _chart = chartData;
          _timingScale = prefs.getDouble(_timingScaleKey) ?? 1.0;
          _scrollSpeed = prefs.getDouble(_scrollSpeedKey) ?? 1.0;
          _highScore = prefs.getInt(_highScoreKey) ?? 0;
          final bgIndex = prefs.getInt(_backgroundKey) ?? 0;
          _backgroundStyle = BackgroundStyle.values[bgIndex.clamp(0, BackgroundStyle.values.length - 1)];
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
    if (_score > _highScore) {
      _highScore = _score;
      final prefs = await SharedPreferences.getInstance();
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
  }

  void _stopGame() {
    _gameStopwatch.stop();
    _audioPlayer?.pause();
    for (final noteList in _notes) {
      for (final note in noteList) {
        note.controller.stop();
      }
    }
  }

  void _spawnPendingNotes() {
    if (_chart == null || _isGameOver) return;
    final elapsed = _gameStopwatch.elapsedMilliseconds;
    final dropMs = _chart!.dropDuration;

    while (_nextNoteIndex < _chart!.notes.length) {
      final event = _chart!.notes[_nextNoteIndex];
      final actualDropMs = dropMs / _scrollSpeed;
      final spawnTime = event.time - (actualDropMs * _easeInToJudgeRatio).round();
      if (elapsed >= spawnTime) {
        _spawnNote(event);
        _nextNoteIndex++;
      } else {
        break;
      }
    }

    if (_nextNoteIndex < _chart!.notes.length && !_isGameOver) {
      final nextEvent = _chart!.notes[_nextNoteIndex];
      final nextActualDropMs = dropMs / _scrollSpeed;
      final nextSpawnTime = nextEvent.time - (nextActualDropMs * _easeInToJudgeRatio).round();
      final delayMs = (nextSpawnTime - elapsed).clamp(1, 100);
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (mounted && !_isGameOver) _spawnPendingNotes();
      });
    }
  }

  void _spawnNote(NoteEvent event) {
    final screenSize = MediaQuery.of(context).size;
    final radius = _rpx(_circleRadiusRpx);

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

    final spawnElapsed = _gameStopwatch.elapsedMilliseconds;
    debugPrint('[SPAWN] elapsed=$spawnElapsed event.time=${event.time} col=${event.column} type=${event.type}');

    controller.addListener(() {
      // 音符持续下落，不冻结
      final easedT = Curves.easeOut.transform(controller.value);
      final targetY = screenSize.height + radius;
      note.currentY = -radius + (targetY + radius) * easedT;

      if (!note.judged && event.type != NoteType.hold) {
        final elapsed = _gameStopwatch.elapsedMilliseconds;
        final missThreshold = event.time + (_missWindow * _timingScale).round();
        if (elapsed > missThreshold) {
          debugPrint('[AUTO_MISS] elapsed=$elapsed event.time=${event.time} col=${event.column}');
          _onNoteMissed(_notes.indexOf(_notes.firstWhere((col) => col.contains(note))), note);
        }
      }

      if (event.type == NoteType.hold && note.holding && !note.judged) {
        final elapsed = _gameStopwatch.elapsedMilliseconds;
        final heldTime = elapsed - note.holdPressTime;
        note.holdProgress = (heldTime / event.holdDuration!).clamp(0.0, 1.0);
        // 详细日志：每 50ms 输出一次 hold 状态
        if ((elapsed ~/ 50) != (note.holdPressTime ~/ 50)) {
          debugPrint('[HOLD_FRAME] elapsed=$elapsed col=${event.column} progress=${(note.holdProgress * 100).toStringAsFixed(0)}% heldTime=${heldTime}ms/${event.holdDuration}ms headY=${note.currentY.toStringAsFixed(0)}');
        }
        if (note.holdProgress >= 1.0) {
          debugPrint('[HOLD_COMPLETE] elapsed=$elapsed col=${event.column} totalHeldTime=${heldTime}ms');
          _judgeNote(event.column, note, note.holdJudgeDiff);
          note.holding = false;
        }
        return;
      }

      // 未按时 hold 音符的自动 miss
      if (!note.judged && event.type == NoteType.hold && !note.holding) {
        final elapsed = _gameStopwatch.elapsedMilliseconds;
        final holdTimeout = event.time + note.event.holdDuration!;
        if (elapsed > holdTimeout) {
          debugPrint('[HOLD_AUTO_MISS] elapsed=$elapsed col=${event.column} event.time=${event.time} holdDuration=${event.holdDuration} headY=${note.currentY.toStringAsFixed(0)} (never pressed)');
          _onNoteMissed(_notes.indexOf(_notes.firstWhere((col) => col.contains(note))), note);
        }
      }
    });

    setState(() {
      _notes[event.column].add(note);
    });

    controller.forward().then((_) {
      note.controller.dispose();
      if (!mounted) return;
      if (note.removeMe) return; // 已被判定移除，不再重复处理
      setState(() => _notes[event.column].remove(note));
    });
  }

  // ── 手势处理 ──

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

  void _handleTapUp(TapUpDetails details) {
    if (_isExiting || _isGameOver || _isCountingDown || _chart == null) return;
    final col = _getColumnFromX(details.localPosition.dx);
    if (col == null) return;
    final elapsed = _gameStopwatch.elapsedMilliseconds;
    debugPrint('[TAP] elapsed=$elapsed col=$col');
    _handleColumnTap(col);
  }

  void _handlePanStart(DragStartDetails details) {
    if (_isExiting || _isGameOver || _isCountingDown || _chart == null) return;
    final col = _getColumnFromX(details.localPosition.dx);
    if (col != null) {
      _panStart = details.globalPosition;
      _panColumn = col;
      final elapsed = _gameStopwatch.elapsedMilliseconds;
      debugPrint('[PRESS] elapsed=$elapsed col=$col');
      _handleColumnPress(col);
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_panColumn == null) return;
    final elapsed = _gameStopwatch.elapsedMilliseconds;
    debugPrint('[RELEASE] elapsed=$elapsed col=$_panColumn');
    _handleColumnRelease(_panColumn!);

    if (_panStart != null && details.velocity.pixelsPerSecond.distance > 50) {
      final dir = _getSwipeDirection(details.velocity.pixelsPerSecond);
      if (dir != null) {
        debugPrint('[SWIPE] elapsed=$elapsed col=$_panColumn dir=$dir');
        _handleSwipe(_panColumn!, dir);
      }
    }
    _panStart = null;
    _panColumn = null;
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
    final elapsed = _gameStopwatch.elapsedMilliseconds;
    final scaledMissWindow = (_missWindow * _timingScale).round();

    // 找到这一列中第一个未判定的 hold 音符
    FallingNote? foundNote;
    String skipReason = '';
    for (final note in _notes[col]) {
      if (note.event.type != NoteType.hold) continue;
      if (note.judged) { skipReason = 'alreadyJudged'; continue; }
      final missThreshold = note.event.time + scaledMissWindow;
      if (elapsed > missThreshold) { skipReason = 'pastMissThreshold'; continue; }
      foundNote = note;
      break;
    }

    if (foundNote != null) {
      final diff = (elapsed - foundNote.event.time).abs();
      debugPrint('[HOLD_PRESS] elapsed=$elapsed col=$col event.time=${foundNote.event.time} diff=${diff}ms holdDuration=${foundNote.event.holdDuration}ms found=YES');
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
      debugPrint('[HOLD_PRESS] elapsed=$elapsed col=$col found=NO reason=$skipReason columnState: hold=$holdCount tap=$tapCount judged=$judgedCount total=${_notes[col].length}');
    }
  }

  void _handleColumnRelease(int col) {
    if (!_heldColumns.contains(col)) {
      debugPrint('[HOLD_RELEASE] elapsed=${_gameStopwatch.elapsedMilliseconds} col=$col notInHeldColumns');
      return;
    }
    _heldColumns.remove(col);

    final elapsed = _gameStopwatch.elapsedMilliseconds;

    for (final note in _notes[col]) {
      if (!note.holding || note.judged) continue;
      if (note.event.type != NoteType.hold) continue;

      final heldTime = elapsed - note.holdPressTime;
      final requiredTime = (note.event.holdDuration! * 0.8).round();
      debugPrint('[HOLD_RELEASE] elapsed=$elapsed col=$col heldTime=${heldTime}ms required=${requiredTime}ms holdProgress=${(note.holdProgress * 100).toStringAsFixed(0)}%');
      if (heldTime >= note.event.holdDuration! * 0.8) {
        _judgeNote(col, note, note.holdJudgeDiff);
      } else {
        debugPrint('[HOLD_RELEASE_MISS] col=$col heldTime=${heldTime}ms < ${note.event.holdDuration}ms * 0.8');
        _onNoteMissed(col, note);
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
      if (diff <= (_goodWindow * _timingScale).round() && note.event.direction == direction) {
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
    final colWidth = w / _columnCount;
    final centerX = colWidth * col + colWidth / 2;
    final radius = _rpx(_circleRadiusRpx);

    final feedbackController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    final feedback = JudgeFeedback(
      text: judgeText,
      x: centerX,
      y: note.currentY - radius - 20,
      color: Theme.of(context).colorScheme.primary,
      baseAlpha: judgeAlpha,
      controller: feedbackController,
    );

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

    note.controller.stop();

    if (note.event.type == NoteType.hold) {
      // Hold 音符：启动 fade-out 动画（300ms 内透明度从 0.5 渐变到 0）
      note.removeMe = false;
      final fadeController = AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      );
      fadeController.addListener(() {
        note.holdFadeOut = fadeController.value;
        if (fadeController.value >= 1.0) {
          fadeController.dispose();
          if (!mounted) return;
          setState(() => _notes[col].remove(note));
        }
      });
      fadeController.forward();
    } else {
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
    final healthScale = 1.0 / _timingScale;
    setState(() {
      _health = (_health - 0.15 * healthScale).clamp(0.0, 1.0);
    });
    if (_health <= 0.0) {
      _gameOver();
    }

    if (note.event.type == NoteType.hold) {
      // Hold 音符：启动 fade-out 动画
      note.removeMe = false;
      final fadeController = AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      );
      fadeController.addListener(() {
        note.holdFadeOut = fadeController.value;
        if (fadeController.value >= 1.0) {
          fadeController.dispose();
          if (!mounted) return;
          setState(() => _notes[col].remove(note));
        }
      });
      fadeController.forward();
    } else {
      note.removeMe = true;
      note.controller.stop();
    }
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
      particles.add(Particle(
        angle: angle,
        distance: distances[i] + rng.nextDouble() * 5,
        initialAlpha: alphas[i],
      ));
    }
    return particles;
  }

  // ── 游戏控制 ──

  void _gameOver() {
    _stopGame();
    _audioPlayer?.stop();  // 游戏结束时完全停止音频
    for (final noteList in _notes) {
      for (final note in noteList) {
        note.controller.stop();
      }
    }
    setState(() => _isGameOver = true);
    _saveHighScore();
  }

  void _restartGame() {
    for (final noteList in _notes) {
      for (final note in noteList) {
        note.controller.dispose();
      }
      noteList.clear();
    }
    for (final e in _explodes) {
      e.controller.dispose();
    }
    _explodes.clear();

    setState(() {
      _isGameOver = false;
      _score = 0;
      _health = 1.0;
      _nextNoteIndex = 0;
    });

    _startCountdown();
  }

  Future<void> _handleExit() async {
    if (_isExiting) return;
    _stopGame();
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
      Navigator.of(context).pop();
    }
  }

  void _showSpeedSettings() {
    final wasCountingDown = _isCountingDown;
    _wasGameRunning = !_isGameOver && !wasCountingDown;
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
        if (wasCountingDown) {
          _resumeFromSnapshot();
        } else {
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
      Future.delayed(const Duration(milliseconds: 800), () => tick(remaining - 1));
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
    _audioPlayer?.seek(Duration(milliseconds: _gameStopwatch.elapsedMilliseconds));
    _audioPlayer?.play();
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
    final radius = _rpx(_circleRadiusRpx);
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

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTapUp,
        onPanStart: _handlePanStart,
        onPanEnd: _handlePanEnd,
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
                onPressed: _isExiting ? null : _showSpeedSettings,
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

            if (_isGameOver)
              Positioned.fill(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: theme.colorScheme.surface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_score',
                            style: TextStyle(
                              fontSize: 64 * w / 750,
                              fontWeight: FontWeight.w100,
                              color: theme.colorScheme.primary,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _score >= _highScore ? '新纪录!' : '最高分: $_highScore',
                            style: TextStyle(
                              fontSize: 14 * w / 750,
                              fontWeight: FontWeight.w300,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 32),
                          GestureDetector(
                            onTap: _restartGame,
                            child: Text(
                              '再来一次',
                              style: TextStyle(
                                fontSize: 16 * w / 750,
                                fontWeight: FontWeight.w300,
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                                decorationColor:
                                    theme.colorScheme.primary.withValues(alpha: 0.3),
                                decorationThickness: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: () {
                              _stopGame();
                              Navigator.of(context).pop();
                            },
                            child: Text(
                              '返回主页',
                              style: TextStyle(
                                fontSize: 14 * w / 750,
                                fontWeight: FontWeight.w300,
                                color: theme.colorScheme.onSurfaceVariant,
                                decoration: TextDecoration.underline,
                                decorationColor:
                                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                                decorationThickness: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
