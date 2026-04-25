import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 弧线选择器 Demo
/// PageView 吸附 + 极坐标弧线布局 + 自定义弧段轨道 + 非遮蔽文字 + 进度条
class ArcSelectorDemo extends DemoPage {
  @override
  String get title => '弧线选择器';

  @override
  String get description => '圆环弧段 UI，横向滑动吸附，弧线排布';

  @override
  Widget buildPage(BuildContext context) {
    return const _ArcSelectorPage();
  }
}

class _ArcSelectorPage extends StatefulWidget {
  const _ArcSelectorPage();

  @override
  State<_ArcSelectorPage> createState() => _ArcSelectorPageState();
}

class _ArcSelectorPageState extends State<_ArcSelectorPage> {
  final PageController _controller = PageController(viewportFraction: 0.22);

  final List<String> _words = List.generate(20, (i) => 'Item $i');

  // 弧线参数
  static const double _startAngle = 200 * math.pi / 180; // 弧段起始角（左下）
  static const double _sweepAngle = 140 * math.pi / 180; // 弧段总角度
  static const int _visibleCount = 7; // 可见项数量

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      body: LayoutBuilder(
        builder: (_, constraints) {
          final size = constraints.biggest;
          // 圆心放屏幕外下方，使其更像圆环弧段
          final cx = size.width / 2;
          final cy = size.height * 1.15;
          final radius = size.shortestSide * 0.85;

          return Stack(
            children: [
              // 弧段轨道背景 + 高光
              CustomPaint(
                size: size,
                painter: _ArcPainter(
                  cx: cx,
                  cy: cy,
                  radius: radius,
                  startAngle: _startAngle,
                  sweepAngle: _sweepAngle,
                ),
              ),

              // 弧线布局文字层
              _ArcLayer(
                controller: _controller,
                words: _words,
                cx: cx,
                cy: cy,
                radius: radius,
                startAngle: _startAngle,
                sweepAngle: _sweepAngle,
                visibleCount: _visibleCount,
              ),

              // PageView 手势层
              PageView.builder(
                controller: _controller,
                itemCount: _words.length,
                itemBuilder: (_, __) => const SizedBox.expand(),
              ),

              // 底部进度条
              Positioned(
                left: 40,
                right: 40,
                bottom: 48,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (_, __) {
                    final page = _controller.hasClients
                        ? (_controller.page ?? 0)
                        : 0.0;
                    final progress = page / (_words.length - 1);
                    return _ArcProgressBar(
                      progress: progress,
                      word: _words[page.round().clamp(0, _words.length - 1)],
                      theme: theme,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 弧段轨道绘制
class _ArcPainter extends CustomPainter {
  final double cx;
  final double cy;
  final double radius;
  final double startAngle;
  final double sweepAngle;

  _ArcPainter({
    required this.cx,
    required this.cy,
    required this.radius,
    required this.startAngle,
    required this.sweepAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(cx, cy);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 底轨
    final basePaint = Paint()
      ..color = const Color(0xFF2A2A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, basePaint);

    // 高光渐变轨道
    final gradientColors = [
      Color(0xFF4FC3F7),
      Color(0xFF7C4DFF),
      Color(0xFF4FC3F7),
    ];

    final highlightPaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: gradientColors,
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, highlightPaint);

    // 两端圆点装饰
    final dotPaint = Paint()..color = const Color(0xFF4FC3F7);

    for (final angle in [startAngle, startAngle + sweepAngle]) {
      final dx = cx + radius * math.cos(angle);
      final dy = cy + radius * math.sin(angle);
      canvas.drawCircle(Offset(dx, dy), 5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) =>
      cx != oldDelegate.cx ||
      cy != oldDelegate.cy ||
      radius != oldDelegate.radius;
}

/// 弧线布局层
class _ArcLayer extends StatelessWidget {
  final PageController controller;
  final List<String> words;
  final double cx;
  final double cy;
  final double radius;
  final double startAngle;
  final double sweepAngle;
  final int visibleCount;

  const _ArcLayer({
    required this.controller,
    required this.words,
    required this.cx,
    required this.cy,
    required this.radius,
    required this.startAngle,
    required this.sweepAngle,
    required this.visibleCount,
  });

  @override
  Widget build(BuildContext context) {
    final k = (visibleCount - 1) / 2;

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.hasClients ? (controller.page ?? 0) : 0.0;

        final children = <Widget>[];

        for (int i = 0; i < words.length; i++) {
          final d = i - t;

          // 裁剪：只渲染可见范围
          if (d.abs() > k + 1) continue;

          // 计算在弧上的位置 [0, 1]
          final u = ((d + k) / (2 * k)).clamp(0.0, 1.0);
          final theta = startAngle + sweepAngle * u;

          // 弧上坐标
          final x = cx + radius * math.cos(theta);
          final y = cy + radius * math.sin(theta);

          // 外法线方向（向外偏移，不遮挡弧线）
          final nx = x - cx;
          final ny = y - cy;
          final len = math.sqrt(nx * nx + ny * ny);
          const lift = 36.0; // 抬升距离

          final ox = x + (nx / len) * lift;
          final oy = y + (ny / len) * lift;

          // 中心项 emphasis
          final emphasis = (1 - (d.abs() / k)).clamp(0.0, 1.0);
          final scale = 0.65 + 0.45 * emphasis;
          final opacity = 0.25 + 0.75 * emphasis;

          children.add(
            Positioned(
              left: ox - 44,
              top: oy - 18,
              width: 88,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: Center(
                    child: Text(
                      words[i],
                      style: TextStyle(
                        color: i <= t.round()
                            ? const Color(0xFF4FC3F7)
                            : Colors.white70,
                        fontSize: 15,
                        fontWeight: emphasis > 0.5
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Stack(children: children);
      },
    );
  }
}

/// 底部进度条
class _ArcProgressBar extends StatelessWidget {
  final double progress;
  final String word;
  final ThemeData theme;

  const _ArcProgressBar({
    required this.progress,
    required this.word,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 当前选中文字
        Text(
          word,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        // 进度条
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: const Color(0xFF2A2A2E),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4FC3F7)),
          ),
        ),
        const SizedBox(height: 6),
        // 百分比
        Text(
          '${(progress * 100).round()}%',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

void registerArcSelectorDemo() {
  demoRegistry.register(ArcSelectorDemo());
}
