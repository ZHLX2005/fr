import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 拖拽混合效果Demo
/// 向上拖动卡片，颜色与文字样式随拖动比例平滑插值变化
class DragBlendDemo extends DemoPage {
  @override
  String get title => '拖拽混合';

  @override
  String get description => '上拖卡片产生颜色与文字混合渐变效果';

  @override
  Widget buildPage(BuildContext context) => const _DragBlendPage();
}

class _DragBlendPage extends StatefulWidget {
  const _DragBlendPage();

  @override
  State<_DragBlendPage> createState() => _DragBlendPageState();
}

class _DragBlendPageState extends State<_DragBlendPage>
    with SingleTickerProviderStateMixin {
  // ---- 配置常量 ----
  static const double _cardHeight = 220;
  static const double _maxDragDistance = 300;

  // 起止颜色
  static const Color _colorStart = Color(0xFF6C63FF);
  static const Color _colorEnd = Color(0xFFFF6584);

  // 起止文字样式
  static const TextStyle _textStart = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 1.2,
  );
  static const TextStyle _textEnd = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w900,
    color: Colors.yellow,
    letterSpacing: 3.0,
  );

  // ---- 状态 ----
  double _dragOffset = 0;
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;

  double get _ratio =>
      (_dragOffset.abs() / _maxDragDistance).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragOffset = (_dragOffset + d.delta.dy).clamp(-_maxDragDistance, 0);
    });
  }

  void _onDragEnd(DragEndDetails _) {
    final target = _ratio > 0.5 ? -_maxDragDistance : 0.0;
    final start = _dragOffset;
    _snapAnimation = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() => _dragOffset = _snapAnimation.value);
      });
    _snapController
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final t = _ratio;
    final bgColor = Color.lerp(_colorStart, _colorEnd, t)!;
    final textStyle = TextStyle.lerp(_textStart, _textEnd, t)!;
    final borderRadius = BorderRadius.circular(24 + 16 * t);
    final elevation = 4 + 12 * t;
    final titleText = t < 0.5 ? '向上拖动我 ↑' : '✨ 混合效果';

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C),
      body: SafeArea(
        child: Center(
          child: GestureDetector(
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 0),
                width: 300,
                height: _cardHeight + 60 * t,
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      bgColor,
                      bgColor.withAlpha((bgColor.alpha * 0.7).toInt()),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: bgColor.withAlpha((bgColor.alpha * 0.5).toInt()),
                      blurRadius: elevation * 2,
                      offset: Offset(0, elevation),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // 背景装饰圆
                    Positioned(
                      top: -30 + 20 * t,
                      right: -20 + 10 * t,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              Colors.white.withAlpha(((0.08 + 0.12 * t) * 255).toInt()),
                        ),
                      ),
                    ),
                    // 主内容
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(titleText, style: textStyle),
                          const SizedBox(height: 12),
                          // 进度条
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: t,
                              backgroundColor: Colors.white.withAlpha(61),
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white.withAlpha((0.8 * 255).toInt())),
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '混合进度: ${(t * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withAlpha(((0.6 + 0.4 * t) * 255).toInt()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void registerDragBlendDemo() {
  demoRegistry.register(DragBlendDemo());
}
