import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lab_container.dart';
import 'line_demo_models.dart';

/// 线 Demo
class LineDemo extends DemoPage {
  @override
  String get title => '线';

  @override
  String get description => '线';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const _LineDemoPage();
  }
}

class _LineDemoPage extends StatefulWidget {
  const _LineDemoPage();

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

  // ── 游戏状态 ──
  static const int _columnCount = 3;
  List<List<FallingCircle>> _columns = [];
  List<Timer?> _spawnTimers = [];
  final List<ExplodeAnimation> _explodes = [];

  // 分数
  int _score = 0;
  int _missCount = 0;
  int _highScore = 0;
  bool _isGameOver = false;

  // 下落速度（毫秒）—— 从顶到屏幕底的总时间
  double _dropDurationMs = 2500.0;
  static const double _minDropMs = 800.0;
  static const double _maxDropMs = 4000.0;

  // 圆圈半径（rpx 基准值）
  static const double _circleRadiusRpx = 20.0;
  // 判定线位置：距底部 25%
  static const double _judgeLineRatio = 0.75; // 从顶部算 75%，即底部 25%
  // 判定线范围上下 100rpx（换算后）
  static const double _judgeRangeRpx = 100.0;

  double _rpx(double value) => value * MediaQuery.of(context).size.width / 750;

  // 暂停快照
  List<List<double>> _pausedSnapshots = [];
  bool _wasGameRunning = false;

  static const String _highScoreKey = 'line_demo_high_score';

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

    _columns = List.generate(_columnCount, (_) => []);
    _spawnTimers = List.generate(_columnCount, (_) => null);

    _loadHighScore();

    // 入场水动画
    _enterController.value = 1.0;
    _enterController.reverse().then((_) {
      if (!mounted) return;
      setState(() => _isWaterEntering = false);
      _startCountdown();
    });
  }

  Future<void> _loadHighScore() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _highScore  = prefs.getInt(_highScoreKey) ?? 0);
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
    for (final timer in _spawnTimers) {
      timer?.cancel();
    }
    for (final col in _columns) {
      for (final c in col) {
        c.controller.dispose();
      }
    }
    for (final e in _explodes) {
      e.controller.dispose();
    }
    super.dispose();
  }

  // ── 游戏控制 ──

  void _startSpawnTimers() {
    _scheduleSpawn(0);
    _scheduleSpawn(1);
    _scheduleSpawn(2);
  }

  void _stopSpawnTimers() {
    for (int i = 0; i < _columnCount; i++) {
      _spawnTimers[i]?.cancel();
      _spawnTimers[i] = null;
    }
  }

  void _scheduleSpawn(int colIndex) {
    _spawnTimers[colIndex]?.cancel();
    final rng = math.Random();
    final delayMs = 300 + rng.nextInt(2700); // 0.3s ~ 3s
    _spawnTimers[colIndex] = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || _isExiting || _isGameOver) return;
      _spawnCircle(colIndex);
      _scheduleSpawn(colIndex);
    });
  }

  void _spawnCircle(int colIndex) {
    final screenSize = MediaQuery.of(context).size;
    final radius = _rpx(_circleRadiusRpx);

    final controller = AnimationController(
      duration: Duration(milliseconds: _dropDurationMs.round()),
      vsync: this,
    );

    final circle = FallingCircle(controller: controller, currentY: -radius);

    // 监听 Y 坐标 + 判定 miss
    controller.addListener(() {
      final easedT = Curves.easeIn.transform(controller.value);
      final targetY = screenSize.height + radius;
      circle.currentY = -radius + (targetY + radius) * easedT;

      // 检查是否穿过判定线
      final judgeY = screenSize.height * _judgeLineRatio;
      if (!circle.missed && !circle.exploded && circle.currentY > judgeY) {
        circle.missed = true;
        _onMiss(colIndex, circle);
      }
    });

    setState(() {
      _columns[colIndex].add(circle);
    });

    controller.forward().then((_) {
      circle.controller.dispose();
      if (!mounted) return;
      // 动画结束，移除
      setState(() {
        _columns[colIndex].remove(circle);
      });
    });
  }

  void _onMiss(int colIndex, FallingCircle circle) {
    if (_isGameOver) return;
    setState(() {
      _missCount++;
    });
    if (_missCount >= 3) {
      _gameOver();
    }
  }

  void _gameOver() {
    _stopSpawnTimers();
    // 停止所有圆圈
    for (final col in _columns) {
      for (final c in col) {
        c.controller.stop();
      }
    }
    setState(() => _isGameOver = true);
    _saveHighScore();
  }

  // ── 点击处理 ──

  void _handleTap(TapUpDetails details) {
    if (_isExiting || _isGameOver || _isCountingDown) return;

    final screenSize = MediaQuery.of(context).size;
    final w = screenSize.width;
    final colWidth = w / _columnCount;
    final tapX = details.localPosition.dx;

    // 判定哪一列
    int? colIndex;
    for (int i = 0; i < _columnCount; i++) {
      if (tapX >= colWidth * i && tapX < colWidth * (i + 1)) {
        colIndex = i;
        break;
      }
    }
    if (colIndex == null) return;

    // 找该列中未被消除、已接近判定线的最底部圆圈
    // 筛选已到达判定范围内的圆圈，取 currentY 最大的（最接近判定线的）
    final judgeY = screenSize.height * _judgeLineRatio;
    final judgeRange = _rpx(_judgeRangeRpx);

    FallingCircle? target;
    double targetY = -double.infinity;

    for (final circle in _columns[colIndex]) {
      if (circle.exploded || circle.missed) continue;
      final dist = (circle.currentY - judgeY).abs();
      if (dist <= judgeRange && circle.currentY > targetY) {
        target = circle;
        targetY = circle.currentY;
      }
    }

    // 如果判定范围内没有，取该列最底部的活圆圈
    if (target == null) {
      for (final circle in _columns[colIndex]) {
        if (circle.exploded || circle.missed) continue;
        if (circle.currentY > targetY) {
          target = circle;
          targetY = circle.currentY;
        }
      }
    }

    if (target == null) return;

    _hitCircle(colIndex, target);
  }

  void _hitCircle(int colIndex, FallingCircle circle) {
    circle.controller.stop();
    circle.exploded = true;

    final screenSize = MediaQuery.of(context).size;
    final w = screenSize.width;
    final colWidth = w / _columnCount;
    final centerX = colWidth * colIndex + colWidth / 2;
    final radius = _rpx(_circleRadiusRpx);

    // 计算得分：距离判定线越近越高分
    final judgeY = screenSize.height * _judgeLineRatio;
    final dist = (circle.currentY - judgeY).abs();
    final judgeRange = _rpx(_judgeRangeRpx);

    int points;
    if (dist <= judgeRange * 0.2) {
      points = 3; // Perfect
    } else if (dist <= judgeRange * 0.5) {
      points = 2; // Great
    } else {
      points = 1; // Good
    }

    setState(() {
      _score += points;
    });

    // 创建炸开动画
    final explodeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    final explode = ExplodeAnimation(
      controller: explodeController,
      x: centerX,
      y: circle.currentY,
      particles: _generateParticles(),
      radius: radius,
    );

    setState(() {
      _explodes.add(explode);
    });

    explodeController.forward().then((_) {
      explodeController.dispose();
      circle.controller.dispose();
      if (!mounted) return;
      setState(() {
        _explodes.remove(explode);
        _columns[colIndex].remove(circle);
      });
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

  // ── 退出 ──

  Future<void> _handleExit() async {
    if (_isExiting) return;
    _stopSpawnTimers();
    for (final col in _columns) {
      for (final c in col) {
        c.controller.stop();
      }
    }
    setState(() => _isExiting = true);
    await _exitController.forward();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // ── 暂停/恢复 ──

  void _showSpeedSettings() {
    _wasGameRunning = !_isGameOver && !_isCountingDown;

    // 保存快照 + 暂停所有
    _pausedSnapshots = [];
    for (final col in _columns) {
      final snapshots = <double>[];
      for (final c in col) {
        snapshots.add(c.controller.value);
        c.controller.stop();
      }
      _pausedSnapshots.add(snapshots);
    }
    _stopSpawnTimers();
    for (final e in _explodes) {
      e.controller.stop();
    }

    Navigator.of(context)
        .push<double>(
      MaterialPageRoute(
        builder: (context) => _SpeedSettingsPage(
          dropDurationMs: _dropDurationMs,
          primaryColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    )
        .then((newSpeed) {
      if (!mounted || _isExiting) return;
      if (newSpeed != null) {
        setState(() => _dropDurationMs = newSpeed);
      }
      _startCountdown();
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
      // 首次启动：开始生成圆圈
      _startSpawnTimers();
      return;
    }

    // 恢复所有圆圈动画
    for (int i = 0; i < _columns.length; i++) {
      final col = _columns[i];
      final snapshots = i < _pausedSnapshots.length ? _pausedSnapshots[i] : [];
      for (int j = 0; j < col.length; j++) {
        final circle = col[j];
        if (!circle.exploded && !circle.missed) {
          final from = j < snapshots.length ? snapshots[j] : 0.0;
          circle.controller.duration =
              Duration(milliseconds: _dropDurationMs.round());
          circle.controller.forward(from: from);
        }
      }
    }

    // 恢复炸开动画
    for (final e in _explodes) {
      e.controller.forward();
    }

    _startSpawnTimers();
    _pausedSnapshots = [];
  }

  // ── 重新开始 ──

  void _restartGame() {
    // 清理所有圆圈
    for (final col in _columns) {
      for (final c in col) {
        c.controller.dispose();
      }
      col.clear();
    }
    for (final e in _explodes) {
      e.controller.dispose();
    }
    _explodes.clear();

    setState(() {
      _isGameOver = false;
      _score = 0;
      _missCount = 0;
    });

    _startCountdown();
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

    // 收集所有活跃的动画 controller 用于 AnimatedBuilder
    final allControllers = <AnimationController>[];
    for (final col in _columns) {
      for (final c in col) {
        allControllers.add(c.controller);
      }
    }
    for (final e in _explodes) {
      allControllers.add(e.controller);
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTap,
        child: Stack(
          children: [
            // ── 三列竖线 + 圆圈 + 判定线 ──
            Positioned.fill(
              child: AnimatedBuilder(
                animation: Listenable.merge(allControllers),
                builder: (context, _) {
                  return CustomPaint(
                    painter: _GamePainter(
                      columns: _columns,
                      explodes: _explodes,
                      color: theme.colorScheme.primary,
                      radius: radius,
                      screenWidth: w,
                      screenHeight: h,
                      columnCount: _columnCount,
                      judgeY: judgeY,
                    ),
                  );
                },
              ),
            ),

            // ── 导航栏 ──
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

            // 分数显示：当前分/最高分
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

            // 设置按钮
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
            ),            if (_missCount > 0)
              Positioned(
                top: MediaQuery.of(context).padding.top + 44,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'miss: $_missCount/3',
                    style: TextStyle(
                      fontSize: 10 * w / 750,
                      fontWeight: FontWeight.w300,
                      color: theme.colorScheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),

            // ── 倒计时层 ──
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

            // ── 游戏结束层（背景穿透点击，仅中心内容可交互） ──
            if (_isGameOver)
              Positioned.fill(
                child: Stack(
                  children: [
                    // 半透明背景（穿透点击到导航栏）
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: theme.colorScheme.surface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    // 中心内容（可交互）
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // ── 入场水动画层 ──
            if (_isWaterEntering)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _enterController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _WaterExitPainter(
                        progress: _enterController.value,
                        color: theme.colorScheme.primary,
                      ),
                    );
                  },
                ),
              ),

            // ── 退出水动画层 ──
            if (_isExiting)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _exitController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _WaterExitPainter(
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

// ═══════════════════════════════════════════════════════════════
// 绘制器
// ═══════════════════════════════════════════════════════════════

/// 游戏主绘制器：竖线 + 圆圈 + 判定线 + 炸开动画
class _GamePainter extends CustomPainter {
  final List<List<FallingCircle>> columns;
  final List<ExplodeAnimation> explodes;
  final Color color;
  final double radius;
  final double screenWidth;
  final double screenHeight;
  final int columnCount;
  final double judgeY;

  _GamePainter({
    required this.columns,
    required this.explodes,
    required this.color,
    required this.radius,
    required this.screenWidth,
    required this.screenHeight,
    required this.columnCount,
    required this.judgeY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final colWidth = w / columnCount;

    // ── 判定线 ──
    final judgePaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, judgeY), Offset(w, judgeY), judgePaint);

    // ── 圆圈 ──
    final circlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (int i = 0; i < columns.length; i++) {
      final cx = colWidth * i + colWidth / 2;
      for (final circle in columns[i]) {
        if (circle.exploded) continue;

        double alpha = 0.3;
        // 穿过判定线后渐退
        if (circle.missed) {
          final dist = circle.currentY - judgeY;
          final fadeRange = screenHeight * 0.25;
          alpha = 0.3 * (1.0 - (dist / fadeRange).clamp(0.0, 1.0));
          if (alpha <= 0.01) continue;
        }

        circlePaint.color = color.withValues(alpha: alpha);

        if (circle.currentY >= -radius &&
            circle.currentY <= screenHeight + radius) {
          canvas.drawCircle(
              Offset(cx, circle.currentY), radius, circlePaint);
        }
      }
    }

    // ── 炸开动画 ──
    for (final explode in explodes) {
      _paintExplode(canvas, explode, w);
    }
  }

  void _paintExplode(Canvas canvas, ExplodeAnimation explode, double w) {
    final progress = explode.controller.value;
    final paint = Paint()..style = PaintingStyle.stroke;

    // Phase 1: 内爆缩小 (0.0 - 0.08)
    if (progress <= 0.08) {
      final t = progress / 0.08;
      final easedT = Curves.easeIn.transform(t);
      final currentRadius = explode.radius * (1.0 - easedT);

      if (currentRadius > 0.1) {
        paint.color = color.withValues(alpha: 0.3);
        paint.strokeWidth = 1.5;
        canvas.drawCircle(
            Offset(explode.x, explode.y), currentRadius, paint);
      }
    }

    // Phase 2: 粒子飞溅 (0.08 - 1.0)
    if (progress > 0.08) {
      final t = (progress - 0.08) / 0.92;
      final splashProgress = Curves.easeOut.transform(t);
      final fadeProgress = Curves.easeIn.transform(t);
      final particleSize = 10.0 * w / 750;

      for (final p in explode.particles) {
        final startX = explode.x + explode.radius * math.cos(p.angle);
        final startY = explode.y + explode.radius * math.sin(p.angle);
        final dx = math.cos(p.angle) * p.distance * splashProgress;
        final dy = math.sin(p.angle) * p.distance * splashProgress;
        final currentAlpha = p.initialAlpha * (1.0 - fadeProgress);

        if (currentAlpha > 0.01) {
          final particlePaint = Paint()
            ..color = color.withValues(alpha: currentAlpha)
            ..style = PaintingStyle.fill;
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(startX + dx, startY + dy),
              width: particleSize,
              height: particleSize,
            ),
            particlePaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GamePainter oldDelegate) => true;
}

/// 演示动画绘制器：只绘制中间列单个圆圈 + 判定线 + 炸开粒子
class _DemoPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double judgeYRatio; // ratio from top (e.g. 0.75)
  final double circleYRatio; // 当前圆圈 Y 坐标比例（相对画布高度）
  final bool showExplode; // 是否显示炸开
  final double explodeProgress; // 炸开进度 0~1
  final List<Particle> explodeParticles;

  _DemoPainter({
    required this.color,
    required this.radius,
    required this.judgeYRatio,
    required this.circleYRatio,
    this.showExplode = false,
    this.explodeProgress = 0.0,
    this.explodeParticles = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final actualJudgeY = h * judgeYRatio;
    final actualCircleY = h * circleYRatio;

    // 判定线
    final judgePaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, actualJudgeY), Offset(w, actualJudgeY), judgePaint);

    // 圆圈
    if (!showExplode) {
      final circlePaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(cx, actualCircleY), radius, circlePaint);
    }

    // 炸开动画
    if (showExplode) {
      // 炸开位置：判定线上方 70% 处（演示用固定位置）
      _paintExplode(canvas, cx, actualJudgeY * 0.7, w);
    }
  }

  void _paintExplode(Canvas canvas, double cx, double explodeY, double w) {
    // Phase 1: 内爆缩小 (0.0 - 0.08)
    if (explodeProgress <= 0.08) {
      final t = explodeProgress / 0.08;
      final easedT = Curves.easeIn.transform(t);
      final currentRadius = radius * (1.0 - easedT);
      if (currentRadius > 0.1) {
        final paint = Paint()
          ..color = color.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(Offset(cx, explodeY), currentRadius, paint);
      }
    }

    // Phase 2: 粒子飞溅 (0.08 - 1.0)
    if (explodeProgress > 0.08) {
      final t = (explodeProgress - 0.08) / 0.92;
      final splashProgress = Curves.easeOut.transform(t);
      final fadeProgress = Curves.easeIn.transform(t);
      final particleSize = 8.0 * w / 200;

      for (final p in explodeParticles) {
        final startX = cx + radius * math.cos(p.angle);
        final startY = explodeY + radius * math.sin(p.angle);
        final dx = math.cos(p.angle) * p.distance * splashProgress;
        final dy = math.sin(p.angle) * p.distance * splashProgress;
        final currentAlpha = p.initialAlpha * (1.0 - fadeProgress);

        if (currentAlpha > 0.01) {
          final particlePaint = Paint()
            ..color = color.withValues(alpha: currentAlpha)
            ..style = PaintingStyle.fill;
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(startX + dx, startY + dy),
              width: particleSize,
              height: particleSize,
            ),
            particlePaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DemoPainter oldDelegate) =>
      oldDelegate.circleYRatio != circleYRatio ||
      oldDelegate.showExplode != showExplode ||
      oldDelegate.explodeProgress != explodeProgress;
}

// ═══════════════════════════════════════════════════════════════
// 速度设置页
// ═══════════════════════════════════════════════════════════════

class _SpeedSettingsPage extends StatefulWidget {
  final double dropDurationMs;
  final Color primaryColor;

  const _SpeedSettingsPage({
    required this.dropDurationMs,
    required this.primaryColor,
  });

  @override
  State<_SpeedSettingsPage> createState() => _SpeedSettingsPageState();
}

class _SpeedSettingsPageState extends State<_SpeedSettingsPage>
    with TickerProviderStateMixin {
  late double _dropDurationMs;
  double _circleYRatio = -0.05;
  bool _showExplode = false;
  List<Particle> _explodeParticles = [];

  late AnimationController _fallController;
  late AnimationController _explodeController;

  static const double _targetYRatio = 0.525; // judgeYRatio * 0.7 = 0.75 * 0.7

  @override
  void initState() {
    super.initState();
    _dropDurationMs = widget.dropDurationMs;

    _fallController = AnimationController(
      duration: Duration(milliseconds: _dropDurationMs.round()),
      vsync: this,
    );

    _explodeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fallController.addListener(_onFallTick);
    _explodeController.addListener(_onExplodeTick);

    _startFall();
  }

  void _startFall() {
    _showExplode = false;
    _explodeParticles = [];
    _circleYRatio = -0.05;
    _fallController.duration = Duration(milliseconds: _dropDurationMs.round());
    _fallController.forward(from: 0.0);
  }

  void _onFallTick() {
    if (_showExplode) return;
    final easedT = Curves.easeIn.transform(_fallController.value);
    setState(() {
      _circleYRatio = -0.05 + (_targetYRatio + 0.05) * easedT;
    });

    if (_fallController.value >= 1.0) {
      _triggerExplode();
    }
  }

  void _triggerExplode() {
    setState(() {
      _showExplode = true;
      _explodeParticles = _generateDemoParticles();
    });
    _explodeController.forward(from: 0.0);
  }

  void _onExplodeTick() {
    setState(() {});
    if (_explodeController.value >= 1.0) {
      _startFall();
    }
  }

  List<Particle> _generateDemoParticles() {
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

  @override
  void dispose() {
    _fallController.dispose();
    _explodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = MediaQuery.of(context).size.width;
    double rpx(double v) => v * w / 750;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // 返回按钮
            Positioned(
              top: 16,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(_dropDurationMs),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 20,
                  color: widget.primaryColor,
                ),
              ),
            ),

            // 主内容：左右布局
            Center(
              child: Row(
                children: [
                  // 左侧：速度控制
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '下落速度',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${_dropDurationMs.round()}ms',
                          style: TextStyle(
                            fontSize: rpx(32),
                            fontWeight: FontWeight.w100,
                            color: widget.primaryColor.withValues(alpha: 0.4),
                            fontFeatures: [const FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 16),
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 1.5,
                            thumbShape: const _LineThumbShape(thumbRadius: 4),
                            overlayShape: SliderComponentShape.noOverlay,
                            activeTrackColor: widget.primaryColor,
                            inactiveTrackColor: theme.colorScheme.outlineVariant,
                            thumbColor: widget.primaryColor,
                          ),
                          child: Slider(
                            value: _dropDurationMs,
                            min: _LineDemoPageState._minDropMs,
                            max: _LineDemoPageState._maxDropMs,
                            onChanged: (v) {
                              setState(() {
                                _dropDurationMs = v;
                                _fallController.duration =
                                    Duration(milliseconds: v.round());
                              });
                            },
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '快',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '慢',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 24),

                  // 右侧：预览动画
                  Expanded(
                    flex: 6,
                    child: AspectRatio(
                      aspectRatio: 0.6,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([_fallController, _explodeController]),
                        builder: (context, _) {
                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(rpx(16)),
                              border: Border.all(
                                color: widget.primaryColor.withValues(alpha: 0.2),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(rpx(16)),
                              child: CustomPaint(
                                painter: _DemoPainter(
                                  color: widget.primaryColor,
                                  radius: rpx(20),
                                  judgeYRatio: 0.75,
                                  circleYRatio: _circleYRatio,
                                  showExplode: _showExplode,
                                  explodeProgress: _explodeController.value,
                                  explodeParticles: _explodeParticles,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 水退出动画绘制器
class _WaterExitPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WaterExitPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final w = size.width;
    final h = size.height;
    final midY = h / 2;
    final midX = w / 2;
    final paint = Paint()..style = PaintingStyle.fill;
    const waveDepth = 8.0;

    // Phase 1: 上下涌入 (0.0 - 0.40)
    if (progress <= 0.40) {
      final t = progress / 0.40;
      final easedT = Curves.easeOutCubic.transform(t);

      final topFrontY = midY * easedT;
      final pathTop = Path();
      pathTop.moveTo(0, topFrontY);
      for (double x = 0; x <= w; x += 1) {
        final y = topFrontY +
            math.sin((x * 3 + progress * 1200) * math.pi / 180) * waveDepth;
        pathTop.lineTo(x, y);
      }
      pathTop.lineTo(w, 0);
      pathTop.lineTo(0, 0);
      pathTop.close();
      paint.color = color;
      canvas.drawPath(pathTop, paint);

      final bottomFrontY = h - midY * easedT;
      final pathBottom = Path();
      pathBottom.moveTo(0, bottomFrontY);
      for (double x = 0; x <= w; x += 1) {
        final y = bottomFrontY -
            math.sin((x * 3 + progress * 1200 + 60) * math.pi / 180) *
                waveDepth;
        pathBottom.lineTo(x, y);
      }
      pathBottom.lineTo(w, h);
      pathBottom.lineTo(0, h);
      pathBottom.close();
      paint.color = color;
      canvas.drawPath(pathBottom, paint);
    }

    // Phase 2: 两侧合拢 (0.40 - 0.80)
    if (progress > 0.40 && progress <= 0.80) {
      final t = (progress - 0.40) / 0.40;
      final easedT = Curves.easeInOutCubic.transform(t);

      paint.color = color;
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);

      final gapWidth = w * (1 - easedT);
      final gapLeft = midX - gapWidth / 2;
      const sideWaveDepth = 6.0;

      final pathLeft = Path();
      final leftEdge = gapLeft;
      pathLeft.moveTo(leftEdge, 0);
      for (double y = 0; y <= h; y += 1) {
        final x = leftEdge +
            math.sin((y * 3 + progress * 1500) * math.pi / 180) *
                sideWaveDepth;
        pathLeft.lineTo(x, y);
      }
      pathLeft.lineTo(0, h);
      pathLeft.lineTo(0, 0);
      pathLeft.close();
      paint.color = color;
      canvas.drawPath(pathLeft, paint);

      final pathRight = Path();
      final rightEdge = gapLeft + gapWidth;
      pathRight.moveTo(rightEdge, 0);
      for (double y = 0; y <= h; y += 1) {
        final x = rightEdge +
            math.sin((y * 3 + progress * 1500 + 60) * math.pi / 180) *
                sideWaveDepth;
        pathRight.lineTo(x, y);
      }
      pathRight.lineTo(w, h);
      pathRight.lineTo(w, 0);
      pathRight.close();
      paint.color = color;
      canvas.drawPath(pathRight, paint);
    }

    // Phase 3: 填满 (0.80 - 1.0)
    if (progress > 0.80) {
      paint.color = color;
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
    }
  }

  @override
  bool shouldRepaint(_WaterExitPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// 线条风格 Slider 滑块 —— 极小实心圆点
class _LineThumbShape extends SliderComponentShape {
  final double thumbRadius;

  const _LineThumbShape({required this.thumbRadius});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(thumbRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final paint = Paint()
      ..color = sliderTheme.thumbColor!
      ..style = PaintingStyle.fill;
    context.canvas.drawCircle(center, thumbRadius, paint);
  }
}

void registerLineDemo() {
  demoRegistry.register(LineDemo());
}
