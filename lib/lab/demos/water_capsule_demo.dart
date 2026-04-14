import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../lab_container.dart';

/// 水位胶囊 Demo
class WaterCapsuleDemo extends DemoPage {
  @override
  String get title => '水位胶囊';

  @override
  String get description => '波浪水位动画组件';

  @override
  Widget buildPage(BuildContext context) {
    return const _WaterCapsulePage();
  }
}

class _WaterCapsulePage extends StatefulWidget {
  const _WaterCapsulePage();

  @override
  State<_WaterCapsulePage> createState() => _WaterCapsulePageState();
}

class _WaterCapsulePageState extends State<_WaterCapsulePage>
    with TickerProviderStateMixin {
  // 配色
  static const Color _nearlyDarkBlue = Color(0xFF2633C5);
  static const Color _nearlyWhite = Color(0xFFFAFAFA);
  static const Color _darkText = Color(0xFF253840);
  static const Color _grey = Color(0xFF3A5160);
  static const Color _pink = Color(0xFFF65283);

  // 当前水量 (0-100)
  double _waterLevel = 60.0;
  final double _dailyGoal = 3500; // ml

  late AnimationController _waveAnimationController;
  late AnimationController _bubbleAnimationController;

  @override
  void initState() {
    super.initState();

    _waveAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _bubbleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _waveAnimationController.repeat();
  }

  @override
  void dispose() {
    _waveAnimationController.dispose();
    _bubbleAnimationController.dispose();
    super.dispose();
  }

  void _addWater() {
    setState(() {
      _waterLevel = (_waterLevel + 10).clamp(0.0, 100.0);
    });
  }

  void _removeWater() {
    setState(() {
      _waterLevel = (_waterLevel - 10).clamp(0.0, 100.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8.0),
                bottomLeft: Radius.circular(8.0),
                bottomRight: Radius.circular(8.0),
                topRight: Radius.circular(68.0),
              ),
              boxShadow: [
                BoxShadow(
                  color: _grey.withOpacity(0.2),
                  offset: const Offset(1.1, 1.1),
                  blurRadius: 10.0,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // 左侧文字信息
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 水量显示
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${(_waterLevel * _dailyGoal / 100).round()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 32,
                                color: _nearlyDarkBlue,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(left: 8, bottom: 8),
                              child: Text(
                                'ml',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 18,
                                  letterSpacing: -0.2,
                                  color: _nearlyDarkBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 4, top: 2, bottom: 14),
                          child: Text(
                            'of daily goal 3.5L',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                              color: _darkText,
                            ),
                          ),
                        ),
                        // 分割线
                        Container(
                          height: 2,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2F3F8),
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 最后喝水时间
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              color: _grey.withOpacity(0.5),
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Last drink 8:26 AM',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                color: _grey.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 提醒
                        Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Image.network(
                                'https://img.icons8.com/color/48/water-bottle.png',
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.water_drop,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                              ),
                            ),
                            const Flexible(
                              child: Text(
                                'Your bottle is empty, refill it!',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                  color: _pink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 中间加减按钮
                  SizedBox(
                    width: 34,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 加号按钮
                        Container(
                          decoration: BoxDecoration(
                            color: _nearlyWhite,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _nearlyDarkBlue.withOpacity(0.4),
                                offset: const Offset(4.0, 4.0),
                                blurRadius: 8.0,
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: _addWater,
                            child: const Padding(
                              padding: EdgeInsets.all(6.0),
                              child: Icon(
                                Icons.add,
                                color: _nearlyDarkBlue,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        // 减号按钮
                        Container(
                          decoration: BoxDecoration(
                            color: _nearlyWhite,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _nearlyDarkBlue.withOpacity(0.4),
                                offset: const Offset(4.0, 4.0),
                                blurRadius: 8.0,
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: _removeWater,
                            child: const Padding(
                              padding: EdgeInsets.all(6.0),
                              child: Icon(
                                Icons.remove,
                                color: _nearlyDarkBlue,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 右侧水位胶囊
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8, top: 16),
                    child: SizedBox(
                      width: 60,
                      height: 160,
                      child: WaveCapsule(
                        percentageValue: _waterLevel,
                        waveAnimation: _waveAnimationController,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 波浪胶囊组件
class WaveCapsule extends StatelessWidget {
  final double percentageValue;
  final Animation<double> waveAnimation;

  const WaveCapsule({
    super.key,
    required this.percentageValue,
    required this.waveAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDFE),
        borderRadius: BorderRadius.circular(80),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.4),
            offset: const Offset(2, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(80),
        child: AnimatedBuilder(
          animation: waveAnimation,
          builder: (context, child) {
            return CustomPaint(
              painter: WavePainter(
                waveValue: waveAnimation.value,
                percentage: percentageValue,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      percentageValue.round().toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 24,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      '%',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 波浪绘制器
class WavePainter extends CustomPainter {
  final double waveValue;
  final double percentage;

  static const Color _nearlyDarkBlue = Color(0xFF2633C5);

  WavePainter({
    required this.waveValue,
    required this.percentage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // 计算水位高度（从底部算起）
    final waterHeight = height * (percentage / 100);
    final waterY = height - waterHeight;

    // 波浪参数
    final waveDepth = 3 + (100 - percentage) / 100 * 4; // 3-7之间变化

    // 绘制第一层波浪（浅色）
    final path1 = Path();
    path1.moveTo(0, height);
    for (double x = 0; x <= width; x += 1) {
      final y = waterY + math.sin((waveValue * 360 - x * 5) * math.pi / 180) * waveDepth;
      path1.lineTo(x, y.clamp(0, height));
    }
    path1.lineTo(width, height);
    path1.close();

    final paint1 = Paint()
      ..color = _nearlyDarkBlue.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path1, paint1);

    // 绘制第二层波浪（深色）
    final path2 = Path();
    path2.moveTo(0, height);
    for (double x = 0; x <= width; x += 1) {
      final y = waterY + math.sin((waveValue * 360 - x * 5 + 30) * math.pi / 180) * waveDepth;
      path2.lineTo(x, y.clamp(0, height));
    }
    path2.lineTo(width, height);
    path2.close();

    final paint2 = Paint()
      ..color = _nearlyDarkBlue
      ..style = PaintingStyle.fill;
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) {
    return oldDelegate.waveValue != waveValue || oldDelegate.percentage != percentage;
  }
}

void registerWaterCapsuleDemo() {
  demoRegistry.register(WaterCapsuleDemo());
}
