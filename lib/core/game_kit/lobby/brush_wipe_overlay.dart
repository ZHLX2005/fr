// 进房油漆刷过渡（原型 feature-list-and-lobby 落盘）。
// TL→BR 铺开；每笔沿 TR→BL 扫出。取消/回退不做反向动画。

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 全屏刷子覆盖层；播完后调用 [onDone]。
class BrushWipeOverlay extends StatefulWidget {
  const BrushWipeOverlay({
    super.key,
    required this.onDone,
    this.duration = const Duration(milliseconds: 2200),
    this.tint = const Color(0xFF7A9A7E),
  });

  final VoidCallback onDone;
  final Duration duration;
  final Color tint;

  @override
  State<BrushWipeOverlay> createState() => _BrushWipeOverlayState();
}

class _BrushWipeOverlayState extends State<BrushWipeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  ui.Image? _brush;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      });
    _loadBrush().then((_) {
      if (mounted) _ctrl.forward();
    });
  }

  Future<void> _loadBrush() async {
    try {
      final data = await rootBundle.load('assets/lobby/brush-stroke.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _brush = frame.image);
    } catch (_) {
      // 无贴图时仍播色块扫过
      if (mounted) _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _brush?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return CustomPaint(
            painter: _BrushWipePainter(
              progress: Curves.easeInOutCubic.transform(_ctrl.value),
              brush: _brush,
              tint: widget.tint,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _BrushWipePainter extends CustomPainter {
  _BrushWipePainter({
    required this.progress,
    required this.brush,
    required this.tint,
  });

  final double progress;
  final ui.Image? brush;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    // 4 笔中心沿 TL→BR；每笔角度 = TR→BL（135°）
    const us = [0.14, 0.38, 0.62, 0.86];
    final length = math.sqrt(w * w + h * h) * 1.4;
    final thickness = math.max(h * 0.4, w * 0.58);
    final angle = math.atan2(1, -1);

    for (var i = 0; i < us.length; i++) {
      final start = i * 0.2;
      final end = i == us.length - 1 ? 1.0 : math.min(1.0, start + 0.38);
      final local = progress <= start
          ? 0.0
          : progress >= end
              ? 1.0
              : _smoothstep((progress - start) / (end - start));
      if (local <= 0.001) continue;

      final u = us[i];
      final cx = w * u + (i.isOdd ? 10.0 : -10.0);
      final cy = h * u + (i.isOdd ? -8.0 : 8.0);
      _drawStroke(
        canvas,
        cx: cx,
        cy: cy,
        angle: angle + (i - 1.5) * 0.018,
        length: length,
        thickness: thickness,
        reveal: local,
      );
    }

    if (progress > 0.9) {
      final a = ((progress - 0.9) / 0.1).clamp(0.0, 1.0);
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFE8F0E5).withValues(alpha: a),
      );
    }
  }

  void _drawStroke(
    Canvas canvas, {
    required double cx,
    required double cy,
    required double angle,
    required double length,
    required double thickness,
    required double reveal,
  }) {
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    final revealW = length * reveal;
    canvas.clipRect(Rect.fromLTWH(-length / 2, -thickness / 2, revealW, thickness));

    if (brush != null) {
      final src = Rect.fromLTWH(
        0,
        0,
        brush!.width.toDouble(),
        brush!.height.toDouble(),
      );
      final dst = Rect.fromCenter(
        center: Offset.zero,
        width: length,
        height: thickness,
      );
      final paint = Paint()
        ..colorFilter = ColorFilter.mode(tint, BlendMode.srcIn);
      canvas.drawImageRect(brush!, src, dst, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: length,
            height: thickness * 0.85,
          ),
          Radius.circular(thickness / 2),
        ),
        Paint()..color = tint.withValues(alpha: 0.85),
      );
    }
    canvas.restore();
  }

  double _smoothstep(double t) {
    final x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  @override
  bool shouldRepaint(covariant _BrushWipePainter old) =>
      old.progress != progress || old.brush != brush || old.tint != tint;
}
