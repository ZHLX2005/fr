import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'line_demo_models.dart';
import 'line_demo_painters.dart';

// ═══════════════════════════════════════════════════════════════
// 持久化 key
// ═══════════════════════════════════════════════════════════════

const String _speedKey = 'line_demo_speed';
const String _backgroundKey = 'line_demo_background';

// ═══════════════════════════════════════════════════════════════
// 演示动画绘制器：只绘制中间列单个圆圈 + 判定线 + 炸开粒子
// ═══════════════════════════════════════════════════════════════

class _DemoPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double judgeYRatio;
  final double circleYRatio;
  final bool showExplode;
  final double explodeProgress;
  final List<Particle> explodeParticles;
  final BackgroundStyle backgroundStyle;

  _DemoPainter({
    required this.color,
    required this.radius,
    required this.judgeYRatio,
    required this.circleYRatio,
    this.showExplode = false,
    this.explodeProgress = 0.0,
    this.explodeParticles = const [],
    this.backgroundStyle = BackgroundStyle.none,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final actualJudgeY = h * judgeYRatio;
    final actualCircleY = h * circleYRatio;

    // ── 背景 ──
    if (backgroundStyle == BackgroundStyle.grid) {
      final gridPaint = Paint()
        ..color = color.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      final spacing = radius * 1.2;
      for (double x = spacing; x < w; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
      }
      for (double y = spacing; y < h; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
      }
    } else if (backgroundStyle == BackgroundStyle.lines) {
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      canvas.drawLine(Offset(cx, 0), Offset(cx, h), linePaint);
    }

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
      _paintExplode(canvas, cx, actualJudgeY * 0.7, w);
    }
  }

  void _paintExplode(Canvas canvas, double cx, double explodeY, double w) {
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
      oldDelegate.explodeProgress != explodeProgress ||
      oldDelegate.backgroundStyle != backgroundStyle;
}

// ═══════════════════════════════════════════════════════════════
// 设置页面（Tab 式：速度 | 背景样式）
// ═══════════════════════════════════════════════════════════════

class SpeedSettingsPage extends StatefulWidget {
  final Color primaryColor;

  const SpeedSettingsPage({
    required this.primaryColor,
  });

  @override
  State<SpeedSettingsPage> createState() => _SpeedSettingsPageState();
}

class _SpeedSettingsPageState extends State<SpeedSettingsPage>
    with TickerProviderStateMixin {
  // Tab 状态
  int _currentTab = 0; // 0: 速度, 1: 背景样式

  // 速度
  double _dropDurationMs = 2500.0;
  static const double _minDropMs = 800.0;
  static const double _maxDropMs = 4000.0;

  // 背景
  BackgroundStyle _backgroundStyle = BackgroundStyle.none;

  // 落体动画
  double _circleYRatio = -0.05;
  bool _showExplode = false;
  List<Particle> _explodeParticles = [];

  late AnimationController _fallController;
  late AnimationController _explodeController;

  static const double _targetYRatio = 0.525;

  @override
  void initState() {
    super.initState();
    _loadSettings();

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

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _dropDurationMs = prefs.getDouble(_speedKey) ?? 2500.0;
        final bgIndex = prefs.getInt(_backgroundKey) ?? 0;
        _backgroundStyle = BackgroundStyle.values[bgIndex.clamp(0, BackgroundStyle.values.length - 1)];
        _fallController.duration = Duration(milliseconds: _dropDurationMs.round());
      });
    }
  }

  Future<void> _saveSpeed(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_speedKey, value);
  }

  Future<void> _saveBackground(BackgroundStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_backgroundKey, style.index);
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
                onTap: () => Navigator.of(context).pop(),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 20,
                  color: widget.primaryColor,
                ),
              ),
            ),

            // 主内容
            Padding(
              padding: EdgeInsets.only(
                top: 80,
                left: 32,
                right: 32,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              child: Column(
                children: [
                  // ── Tab 按钮 ──
                  _buildTabs(theme, rpx),

                  const SizedBox(height: 16),

                  // ── 预览动画区 (60%) ──
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
                                    backgroundStyle: _backgroundStyle,
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

                  // ── 控制区 (40%) ──
                  Expanded(
                    flex: 4,
                    child: _currentTab == 0
                        ? _buildSpeedControls(theme, rpx)
                        : _buildBackgroundControls(theme, rpx),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs(ThemeData theme, double Function(double) rpx) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTabItem('速度', 0, theme),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '|',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w200,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        _buildTabItem('背景样式', 1, theme),
      ],
    );
  }

  Widget _buildTabItem(String label, int index, ThemeData theme) {
    final isSelected = _currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w400 : FontWeight.w200,
              color: isSelected
                  ? widget.primaryColor
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 1,
            width: 40,
            color: isSelected
                ? widget.primaryColor
                : Colors.transparent,
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedControls(ThemeData theme, double Function(double) rpx) {
    return Column(
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
              _saveSpeed(v);
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
    );
  }

  Widget _buildBackgroundControls(ThemeData theme, double Function(double) rpx) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildBgButton(
              icon: _buildGridIcon(),
              style: BackgroundStyle.grid,
              theme: theme,
            ),
            const SizedBox(width: 16),
            _buildBgButton(
              icon: _buildLinesIcon(),
              style: BackgroundStyle.lines,
              theme: theme,
            ),
            const SizedBox(width: 16),
            _buildBgButton(
              icon: _buildNoneIcon(),
              style: BackgroundStyle.none,
              theme: theme,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBgButton({
    required Widget icon,
    required BackgroundStyle style,
    required ThemeData theme,
  }) {
    final isSelected = _backgroundStyle == style;
    return GestureDetector(
      onTap: () {
        setState(() => _backgroundStyle = style);
        _saveBackground(style);
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? widget.primaryColor
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
          color: isSelected
              ? widget.primaryColor.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Center(child: icon),
      ),
    );
  }

  Widget _buildGridIcon() {
    return CustomPaint(
      size: const Size(28, 28),
      painter: _GridIconPainter(
        color: widget.primaryColor.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _buildLinesIcon() {
    return CustomPaint(
      size: const Size(28, 28),
      painter: _LinesIconPainter(
        color: widget.primaryColor.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _buildNoneIcon() {
    return CustomPaint(
      size: const Size(28, 28),
      painter: _NoneIconPainter(
        color: widget.primaryColor.withValues(alpha: 0.6),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 背景图标绘制器
// ═══════════════════════════════════════════════════════════════

class _GridIconPainter extends CustomPainter {
  final Color color;
  _GridIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (int i = 1; i <= 2; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int i = 1; i <= 2; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridIconPainter old) => old.color != color;
}

class _LinesIconPainter extends CustomPainter {
  final Color color;
  _LinesIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (int i = 1; i <= 3; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinesIconPainter old) => old.color != color;
}

class _NoneIconPainter extends CustomPainter {
  final Color color;
  _NoneIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final margin = size.width * 0.2;
    canvas.drawLine(
      Offset(margin, margin),
      Offset(size.width - margin, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, margin),
      Offset(margin, size.height - margin),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _NoneIconPainter old) => old.color != color;
}
