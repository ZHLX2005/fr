import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../lab_container.dart';

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
  bool _isWaterEntering = true;
  bool _isFalling = false;
  bool _isExploding = false;
  bool _isExiting = false;
  bool _isCountingDown = false;
  int _countdownValue = 3;

  late AnimationController _exitController;
  late AnimationController _enterController;
  late AnimationController _dropController;
  late AnimationController _explodeController;

  // 下落中圆圈的实时 Y 坐标（用于点击判定）
  double _currentCircleY = 0;

  // 粒子数据（每次炸开前随机生成）
  List<_Particle> _particles = [];

  // 下落速度（毫秒）
  double _dropDurationMs = 2500.0;
  static const double _minDropMs = 800.0;
  static const double _maxDropMs = 4000.0;

  // 暂停时的动画快照
  double _pausedDropValue = 0;
  bool _wasPausedWhileFalling = false;

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
    // 下落动画：从顶部到屏幕底部以下（超出屏幕）
    _dropController = AnimationController(
      duration: Duration(milliseconds: _dropDurationMs.round()),
      vsync: this,
    );
    // 炸开动画
    _explodeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // 监听下落动画值，实时更新圆圈 Y 坐标
    _dropController.addListener(() {
      final screenSize = MediaQuery.of(context).size;
      final radius = 15.0 * screenSize.width / 750;
      final targetY = screenSize.height + radius; // 落到屏幕外
      final easedT = Curves.easeIn.transform(_dropController.value);
      _currentCircleY = -radius + (targetY + radius) * easedT;
    });

    // 入场水动画
    _enterController.value = 1.0;
    _enterController.reverse().then((_) {
      if (!mounted) return;
      setState(() => _isWaterEntering = false);
      debugPrint('[LineDemo] Water enter completed, auto drop in 1s');
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (!mounted || _isExiting) return;
        _startDrop();
      });
    });
  }

  @override
  void dispose() {
    _exitController.dispose();
    _enterController.dispose();
    _dropController.dispose();
    _explodeController.dispose();
    super.dispose();
  }

  /// 开始下落动画
  void _startDrop() {
    setState(() {
      _isFalling = true;
      _isExploding = false;
    });
    _dropController.reset();
    _dropController.forward().then((_) {
      if (!mounted || _isExiting) return;
      // 未被点击，圆圈落到屏幕外，1 秒后重新下落
      setState(() => _isFalling = false);
      debugPrint('[LineDemo] Drop completed (missed), restart in 1s');
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (!mounted || _isExiting) return;
        _startDrop();
      });
    });
  }

  /// 开始炸开动画
  void _startExplode(double explodeY) {
    // 停止下落动画
    _dropController.stop();
    _particles = _generateParticles();
    setState(() {
      _isFalling = false;
      _isExploding = true;
    });
    _explodeController.reset();
    _explodeController.forward().then((_) {
      if (!mounted || _isExiting) return;
      setState(() => _isExploding = false);
      debugPrint('[LineDemo] Explode completed, restart drop in 1s');
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (!mounted || _isExiting) return;
        _startDrop();
      });
    });
  }

  /// 处理屏幕点击
  void _handleTap(TapUpDetails details) {
    if (_isExiting || _isExploding) return;

    // 下落过程中才能触发炸开
    if (!_isFalling) return;

    final screenSize = MediaQuery.of(context).size;
    final centerX = screenSize.width / 2;
    final hitRange = 60.0 * screenSize.width / 750; // 60rpx
    final tapX = details.localPosition.dx;

    // 判定：X 在竖线范围内即可，任意 Y 位置
    final inXRange = (tapX - centerX).abs() <= hitRange;

    debugPrint('[LineDemo] Tap at x=${tapX.toStringAsFixed(1)}, '
        'circleY=${_currentCircleY.toStringAsFixed(1)}, '
        'hitRange=${hitRange.toStringAsFixed(1)}, '
        'inX=$inXRange');

    if (inXRange) {
      _startExplode(_currentCircleY);
    }
  }

  List<_Particle> _generateParticles() {
    final rng = math.Random();
    final count = 4 + rng.nextInt(2); // 4 或 5
    final particles = <_Particle>[];

    final baseAngles = List.generate(count, (i) => (2 * math.pi * i / count));
    final distances = [15.0, 20.0, 25.0, 30.0, 35.0];
    final alphas = [0.5, 0.4, 0.35, 0.25, 0.15];

    for (int i = 0; i < count; i++) {
      final angle = baseAngles[i] + (rng.nextDouble() - 0.5) * 0.6;
      particles.add(_Particle(
        angle: angle,
        distance: distances[i] + rng.nextDouble() * 5,
        initialAlpha: alphas[i],
      ));
    }
    return particles;
  }

  Future<void> _handleExit() async {
    if (_isExiting) return;
    _dropController.stop();
    setState(() {
      _isExiting = true;
      _isFalling = false;
      _isExploding = false;
    });

    await _exitController.forward();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showSpeedSettings() {
    // 保存暂停快照
    if (_isFalling) {
      _pausedDropValue = _dropController.value;
      _wasPausedWhileFalling = true;
    } else {
      _wasPausedWhileFalling = false;
    }

    // 暂停所有动画
    _dropController.stop();
    _explodeController.stop();

    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                20,
                24,
                MediaQuery.of(context).padding.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题行
                  Row(
                    children: [
                      Text(
                        '下落速度',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_dropDurationMs.round()}ms',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFeatures: [const FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Slider
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 1.5,
                      thumbShape: const _LineThumbShape(thumbRadius: 4),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: theme.colorScheme.primary,
                      inactiveTrackColor: theme.colorScheme.outlineVariant,
                      thumbColor: theme.colorScheme.primary,
                    ),
                    child: Slider(
                      value: _dropDurationMs,
                      min: _minDropMs,
                      max: _maxDropMs,
                      onChanged: (v) {
                        setState(() {
                          _dropDurationMs = v;
                          _dropController.duration =
                              Duration(milliseconds: v.round());
                        });
                        setSheetState(() {});
                      },
                    ),
                  ),
                  // 两端标签
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '慢',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '快',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      // 面板关闭后开始倒计时
      if (!mounted || _isExiting) return;
      _startCountdown();
    });
  }

  /// 3-2-1 倒计时，结束后从暂停快照恢复下落动画
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
        _resumeDrop();
        return;
      }
      Future.delayed(const Duration(milliseconds: 800), () => tick(remaining - 1));
    }

    tick(3);
  }

  /// 从暂停快照恢复下落动画
  void _resumeDrop() {
    if (_wasPausedWhileFalling) {
      setState(() {
        _isFalling = true;
        _isExploding = false;
      });
      _dropController.forward(from: _pausedDropValue).then((_) {
        if (!mounted || _isExiting) return;
        setState(() => _isFalling = false);
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (!mounted || _isExiting) return;
          _startDrop();
        });
      });
    } else {
      _startDrop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final radius = 15.0 * screenSize.width / 750;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTap,
        child: Stack(
          children: [
            // 下落中的圆圈
            if (_isFalling)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _dropController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _CircleFallingPainter(
                        progress: _dropController.value,
                        color: theme.colorScheme.primary,
                        radius: radius,
                        screenHeight: screenSize.height,
                      ),
                    );
                  },
                ),
              ),

            // 炸开动画
            if (_isExploding)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _explodeController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _CircleExplodePainter(
                        progress: _explodeController.value,
                        color: theme.colorScheme.primary,
                        radius: radius,
                        particles: _particles,
                        explodeY: _currentCircleY,
                      ),
                    );
                  },
                ),
              ),

            // 返回 icon 按钮
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                onPressed: _handleExit,
              ),
            ),

            // 设置 icon 按钮
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: IconButton(
                icon: Icon(
                  Icons.settings_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                onPressed: _isExiting ? null : _showSpeedSettings,
              ),
            ),

            // 倒计时层
            if (_isCountingDown)
              Positioned.fill(
                child: Center(
                  child: Text(
                    '$_countdownValue',
                    style: TextStyle(
                      fontSize: 120 * screenSize.width / 750,
                      fontWeight: FontWeight.w100,
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                      height: 1,
                      letterSpacing: -2,
                    ),
                  ),
                ),
              ),

            // 入场水动画层
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

            // 退出水动画层
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

/// 粒子数据
class _Particle {
  final double angle;
  final double distance;
  final double initialAlpha;

  const _Particle({
    required this.angle,
    required this.distance,
    required this.initialAlpha,
  });
}

/// 圆圈下落绘制器
///
/// progress 0.0 → 1.0: 圆圈从屏幕顶部加速下落，穿过屏幕底部消失
class _CircleFallingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double radius;
  final double screenHeight;

  _CircleFallingPainter({
    required this.progress,
    required this.color,
    required this.radius,
    required this.screenHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final w = size.width;
    final centerX = w / 2;
    final easedT = Curves.easeIn.transform(progress);

    // 圆圈 y: 从 -radius 到 screenHeight + radius（穿过整个屏幕）
    final targetY = screenHeight + radius;
    final circleY = -radius + (targetY + radius) * easedT;

    // 只在屏幕可见范围内绘制圆圈
    if (circleY >= -radius && circleY <= screenHeight + radius) {
      final paint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(Offset(centerX, circleY), radius, paint);
    }

    debugPrint('[CircleFall] progress=${progress.toStringAsFixed(3)} '
        'circleY=${circleY.toStringAsFixed(1)}');
  }

  @override
  bool shouldRepaint(_CircleFallingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// 圆圈炸开绘制器
///
/// Phase 1 (0.0 - 0.08): 内爆缩小（圆圈 radius → 0）
/// Phase 2 (0.08 - 1.0): 粒子从圆的边缘向外飞散并渐隐
class _CircleExplodePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double radius;
  final List<_Particle> particles;
  final double explodeY;

  _CircleExplodePainter({
    required this.progress,
    required this.color,
    required this.radius,
    required this.particles,
    required this.explodeY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final centerX = w / 2;
    final paint = Paint()..style = PaintingStyle.stroke;

    // ── Phase 1: 内爆缩小 (0.0 - 0.08) ──
    if (progress <= 0.08) {
      final t = progress / 0.08;
      final easedT = Curves.easeIn.transform(t);
      final currentRadius = radius * (1.0 - easedT);

      if (currentRadius > 0.1) {
        paint.color = color.withValues(alpha: 0.3);
        paint.strokeWidth = 3;
        canvas.drawCircle(Offset(centerX, explodeY), currentRadius, paint);
      }

      debugPrint('[CircleExplode] Phase1 implode: r=${currentRadius.toStringAsFixed(1)}');
    }

    // ── Phase 2: 粒子飞溅 (0.08 - 1.0) ──
    if (progress > 0.08) {
      final t = (progress - 0.08) / 0.92;
      final splashProgress = Curves.easeOut.transform(t);
      final fadeProgress = Curves.easeIn.transform(t);
      final particleSize = 10.0 * w / 750;

      for (int i = 0; i < particles.length; i++) {
        final p = particles[i];
        final startX = centerX + radius * math.cos(p.angle);
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

      debugPrint('[CircleExplode] Phase2 splash: t=${t.toStringAsFixed(3)}');
    }
  }

  @override
  bool shouldRepaint(_CircleExplodePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// 水退出动画绘制器
///
/// Phase 1 (0.0 - 0.40): 上下两侧波浪涌入
/// Phase 2 (0.40 - 0.80): 左右两侧波浪合拢
/// Phase 3 (0.80 - 1.0): 填满全屏
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

    // ── Phase 1: 上下涌入 (0.0 - 0.40) ──
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

    // ── Phase 2: 两侧合拢 (0.40 - 0.80) ──
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

    // ── Phase 3: 填满 (0.80 - 1.0) ──
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
