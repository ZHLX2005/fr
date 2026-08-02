import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../interfaces/interfaces.dart';
import '../data/water_capsule_message_data.dart';

/// 波浪胶囊组件（动画版本，用于消息渲染）
class _WaveCapsule extends StatefulWidget {
  final int level;
  final bool dev;

  const _WaveCapsule({required this.level, this.dev = false});

  @override
  State<_WaveCapsule> createState() => _WaveCapsuleState();
}

class _WaveCapsuleState extends State<_WaveCapsule>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late int _level;

  @override
  void initState() {
    super.initState();
    _level = widget.level;
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

  void _addWater() {
    setState(() {
      _level = (_level + 10).clamp(0, 100);
    });
  }

  void _removeWater() {
    setState(() {
      _level = (_level - 10).clamp(0, 100);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 波浪胶囊
        Container(
          width: 60,
          height: 160,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(80),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow,
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
                    level: _level,
                    waveColor: scheme.primary,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _level.round().toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 24,
                            color: scheme.onPrimary,
                          ),
                        ),
                        Text(
                          '%',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // Dev控制按钮
        if (widget.dev) ...[
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildControlButton(Icons.add, _addWater),
              const SizedBox(height: 16),
              _buildControlButton(Icons.remove, _removeWater),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow,
            offset: const Offset(2, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: scheme.primary, size: 24),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double waveValue;
  final int level;
  final Color waveColor;

  _WavePainter({
    required this.waveValue,
    required this.level,
    required this.waveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final waterHeight = height * (level / 100);
    final waterY = height - waterHeight;
    final waveDepth = 3 + (100 - level) / 100 * 4; // 3-7之间变化

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
        ..color = waveColor.withValues(alpha: 0.5)
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
        ..color = waveColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) {
    return oldDelegate.waveValue != waveValue ||
        oldDelegate.level != level ||
        oldDelegate.waveColor != waveColor;
  }
}

/// Strategy for rendering water capsule messages
class WaterCapsuleMessageWidgetStrategy
    extends MessageWidgetStrategy<WaterCapsuleMessageData> {
  @override
  Widget build(BuildContext context, WaterCapsuleMessageData data) {
    return _WaveCapsule(level: data.level, dev: data.dev);
  }

  @override
  WaterCapsuleMessageData createMockData() => WaterCapsuleMessageData(60, dev: true);
}
