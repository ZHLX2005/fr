import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/water_capsule_message_data.dart';

/// 波浪胶囊组件（动画版本，用于消息渲染）
class _WaveCapsule extends StatefulWidget {
  final int level;

  const _WaveCapsule({required this.level});

  @override
  State<_WaveCapsule> createState() => _WaveCapsuleState();
}

class _WaveCapsuleState extends State<_WaveCapsule>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDFE),
        borderRadius: BorderRadius.circular(80),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.4),
            offset: const Offset(2, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(80),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _WavePainter(
                waveValue: _controller.value,
                level: widget.level,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.level.round().toString(),
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

class _WavePainter extends CustomPainter {
  final double waveValue;
  final int level;

  static const Color _nearlyDarkBlue = Color(0xFF2633C5);

  _WavePainter({required this.waveValue, required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final waterHeight = height * (level / 100);
    final waterY = height - waterHeight;
    final waveDepth = 3.0;

    // 第一层波浪（浅色）
    final path1 = Path();
    path1.moveTo(0, height);
    for (double x = 0; x <= width; x += 1) {
      final y = waterY +
          math.sin((waveValue * 360 - x * 5) * math.pi / 180) * waveDepth;
      path1.lineTo(x, y.clamp(0, height));
    }
    path1.lineTo(width, height);
    path1.close();

    canvas.drawPath(
      path1,
      Paint()
        ..color = _nearlyDarkBlue.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill,
    );

    // 第二层波浪（深色）
    final path2 = Path();
    path2.moveTo(0, height);
    for (double x = 0; x <= width; x += 1) {
      final y = waterY +
          math.sin((waveValue * 360 - x * 5 + 30) * math.pi / 180) *
              waveDepth;
      path2.lineTo(x, y.clamp(0, height));
    }
    path2.lineTo(width, height);
    path2.close();

    canvas.drawPath(
      path2,
      Paint()
        ..color = _nearlyDarkBlue
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) {
    return oldDelegate.waveValue != waveValue || oldDelegate.level != level;
  }
}

/// Strategy for rendering water capsule messages
class WaterCapsuleMessageWidgetStrategy
    extends MessageWidgetStrategy<WaterCapsuleMessageData> {
  @override
  Widget build(BuildContext context, WaterCapsuleMessageData data) {
    return _WaveCapsule(level: data.level);
  }

  @override
  WaterCapsuleMessageData createMockData() => WaterCapsuleMessageData(65);
}
