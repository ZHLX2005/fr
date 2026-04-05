import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'line_demo_models.dart';
import 'line_demo_painters.dart';

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

class SpeedSettingsPage extends StatefulWidget {
  final double dropDurationMs;
  final Color primaryColor;

  const SpeedSettingsPage({
    required this.dropDurationMs,
    required this.primaryColor,
  });

  @override
  State<SpeedSettingsPage> createState() => _SpeedSettingsPageState();
}

class _SpeedSettingsPageState extends State<SpeedSettingsPage>
    with TickerProviderStateMixin {
  late double _dropDurationMs;
  double _circleYRatio = -0.05;
  bool _showExplode = false;
  List<Particle> _explodeParticles = [];

  late AnimationController _fallController;
  late AnimationController _explodeController;

  static const double _targetYRatio = 0.525; // judgeYRatio * 0.7 = 0.75 * 0.7

  static const double _minDropMs = 800.0;
  static const double _maxDropMs = 4000.0;

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

            // 主内容：上下布局
            Padding(
              padding: EdgeInsets.only(
                top: 56,
                left: 32,
                right: 32,
                bottom: MediaQuery.of(context).padding.bottom + 32,
              ),
              child: Column(
                children: [
                  // 上方：预览动画区 (60%)
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 0.6,
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_fallController, _explodeController]),
                          builder: (context, _) {
                            return Container(
                              decoration: BoxDecoration(
                                color: widget.primaryColor.withValues(alpha: 0.05),
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
                  ),

                  const SizedBox(height: 32),

                  // 下方：速度控制区 (40%)
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
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
                            thumbShape: const LineThumbShape(thumbRadius: 4),
                            overlayShape: SliderComponentShape.noOverlay,
                            activeTrackColor: widget.primaryColor,
                            inactiveTrackColor: theme.colorScheme.outlineVariant,
                            thumbColor: widget.primaryColor,
                          ),
                          child: Slider(
                            value: _dropDurationMs,
                            min: _minDropMs,
                            max: _maxDropMs,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
