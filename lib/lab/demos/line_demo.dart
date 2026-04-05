import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lab_container.dart';
import 'line_demo_models.dart';
import 'line_demo_painters.dart';
import 'line_demo_settings.dart';

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
        builder: (context) => SpeedSettingsPage(
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
                    painter: GamePainter(
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
                      painter: WaterExitPainter(
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

void registerLineDemo() {
  demoRegistry.register(LineDemo());
}
