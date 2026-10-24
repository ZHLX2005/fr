// lib/core/remotetype/canvas/rt_canvas_dpad.dart
//
// 方向模块（游戏布局左手区），两种布局（[dir8]）：
//   · false = 四向十字键（默认）：标准手柄十字键样式——单一圆角十字轮廓
//     （横竖双圆角矩形并集）+ 中心凹槽 + 四向箭头，激活臂铺主色淡底。
//     按到某向 → 立即回报该向（vpad_dpad up/down/left/right）；PC 端虚拟
//     手柄保持该状态，**无需连发**。按住滑到另一向 = 换向；滑回中心毂或
//     松手 = 回报 null（映射 vpad_dpad 'none' 回中）。命中判定与视觉同形：
//     十字区域内臂归该向，中心毂与斜角空隙不触发（四向键语义，不出斜向）。
//     判定区域可按 [hitRatio] 缩放（编辑工具面板滑杆调整，编辑态虚线框
//     实时预览）。
//   · true = 八向分段轮盘：8 段圆角扇环 + 段内向外箭头，45° 扇区（22.5°
//     为界）判向，补 up_left/up_right/down_left/down_right 四个斜向；
//     中心旋钮拖动跟手、松手弹簧回中。
// 方向名与 rust input-agent vpad.rs 的 vpad_dir 白名单一致（四向 + 四斜向 +
// none），经 rt-align normalizeVpadOp 白名单放行。斜向需 PC 端同步更新。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/colors/strategy/color_strategy/color_strategy.dart';
import '../../../core/theme/context/colors.dart';

/// 中心死区占半径比例（八向轮盘）：指针在死区内 = 无方向（回中）。
const double kRtDpadDeadZoneRatio = 0.25;

/// 四向十字键几何（占模块边长比例，视觉与判定同源）：
/// 臂半长 0.46（十字外沿）、臂半宽 0.16（单臂宽度之半，≈手柄十字键比例）。
const double kRtDpadCrossHalfRatio = 0.46;
const double kRtDpadArmHalfRatio = 0.16;

/// 判定几何钳制上限（占模块边长比例）：hitRatio 放大后仍不出模块方块。
const double _kHitClampRatio = 0.49;

/// 八向轮盘段序（-90° 起每 45° 一段，与 _dirAt 扇区一致；判定与绘制同源）。
const List<String> _kWheelDirs = <String>[
  'up',
  'up_right',
  'right',
  'down_right',
  'down',
  'down_left',
  'left',
  'up_left',
];

class RtCanvasDpad extends StatefulWidget {
  const RtCanvasDpad({
    super.key,
    required this.enabled,
    required this.onDirection,
    this.showLegend = true,
    this.dir8 = false,
    this.hitRatio = 1.0,
    this.editMode = false,
  });

  /// false（未连接）：置灰且不响应。
  final bool enabled;

  /// 方向变化回报：非 null = 新方向（vpad_dpad up/down/left/right，
  /// 八向轮盘另加 up_left/up_right/down_left/down_right）；
  /// null = 回中（vpad_dpad none）。只在变化时回调，不连发。
  final ValueChanged<String?> onDirection;

  /// 编辑态由外层描边框接管说明，图例可不画。
  final bool showLegend;

  /// 方向布局：false = 四向十字键（默认）；true = 八向分段轮盘（补斜向）。
  final bool dir8;

  /// 四向判定区域倍率（仅四向十字键有意义）：1.0 = 与视觉十字同形；
  /// >1 放大触控判定（更跟手），<1 收紧。编辑工具面板滑杆实时调整，
  /// 持久化在 anchor.hit（稀疏字段）。
  final double hitRatio;

  /// 编辑态：四向叠画判定区虚线框（随 [hitRatio] 缩放）；取值手势由
  /// 外层编辑包装关停（编排与触发不串台）。
  final bool editMode;

  @override
  State<RtCanvasDpad> createState() => _RtCanvasDpadState();
}

class _RtCanvasDpadState extends State<RtCanvasDpad> {
  static const _dirs = <String, IconData>{
    'up': Icons.keyboard_arrow_up,
    'down': Icons.keyboard_arrow_down,
    'left': Icons.keyboard_arrow_left,
    'right': Icons.keyboard_arrow_right,
  };

  /// 四向箭头位置（十字键臂中位，中心偏移占半边比例）。
  static const _armAlign = <String, Alignment>{
    'up': Alignment(0, -0.60),
    'down': Alignment(0, 0.60),
    'left': Alignment(-0.60, 0),
    'right': Alignment(0.60, 0),
  };

  String? _activeDir;
  bool _pointerDown = false;

  // 旋钮位移（像素，相对轮盘中心，仅八向轮盘用）。拖动期间跟手（短延时
  // 直出），松手弹簧回中（easeOutBack 带回弹）。
  Offset _knob = Offset.zero;

  // ================= 方向判定与回报 =================

  /// 指针相对模块中心的方向；中心毂/空隙返回 null。
  String? _dirAt(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final v = local - center;
    final side = math.min(size.width, size.height);
    if (!widget.dir8) {
      // 四向十字键：判定区 = 视觉同形的十字（可按 hitRatio 缩放，钳在模块内）。
      final t = math.min(
        side * kRtDpadArmHalfRatio * widget.hitRatio,
        side * _kHitClampRatio,
      );
      final l = math.min(
        side * kRtDpadCrossHalfRatio * widget.hitRatio,
        side * _kHitClampRatio,
      );
      final ax = v.dx.abs();
      final ay = v.dy.abs();
      if (math.max(ax, ay) > l) return null; // 十字臂长之外（判定区外）
      if (ax <= t && ay <= t) return null; // 中心毂
      if (ay <= t) return v.dx >= 0 ? 'right' : 'left'; // 横臂
      if (ax <= t) return v.dy >= 0 ? 'down' : 'up'; // 竖臂
      return null; // 斜角空隙（四向键不出斜向）
    }
    // 八向轮盘：先看死区（半径 25%）。
    if (v.distance < side / 2 * kRtDpadDeadZoneRatio) return null;
    // 45° 扇区八分圆，22.5° 为界。Flutter 坐标 y 向下为正：
    // 0°=右、90°=下、-90°=上、±180°=左。
    final deg = math.atan2(v.dy, v.dx) * 180 / math.pi;
    return switch (deg) {
      < -157.5 || >= 157.5 => 'left',
      >= -157.5 && < -112.5 => 'up_left',
      >= -112.5 && < -67.5 => 'up',
      >= -67.5 && < -22.5 => 'up_right',
      >= -22.5 && < 22.5 => 'right',
      >= 22.5 && < 67.5 => 'down_right',
      >= 67.5 && < 112.5 => 'down',
      _ => 'down_left',
    };
  }

  /// 旋钮目标位（仅八向轮盘）：朝指针方向偏移，钳在轮盘内圈里
  /// （0.32 半径 + 毂半径 ≈ 内圈 0.30 边长比，不出扇环）；死区回零。
  Offset _knobTarget(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final v = local - center;
    if (v.distance < radiusOf(size) * kRtDpadDeadZoneRatio) return Offset.zero;
    final maxR = radiusOf(size) * 0.32;
    return v.distance <= maxR ? v : (v / v.distance) * maxR;
  }

  double radiusOf(Size size) => math.min(size.width, size.height) / 2;

  void _setDirection(String? dir) {
    if (dir == _activeDir) return;
    setState(() => _activeDir = dir);
    if (dir != null) unawaited(HapticFeedback.selectionClick());
    widget.onDirection(dir);
  }

  void _onPointerDown(PointerDownEvent e, Size size) {
    if (!widget.enabled) return;
    _pointerDown = true;
    unawaited(HapticFeedback.mediumImpact());
    if (widget.dir8) {
      setState(() => _knob = _knobTarget(e.localPosition, size));
    }
    _setDirection(_dirAt(e.localPosition, size));
  }

  void _onPointerMove(PointerMoveEvent e, Size size) {
    if (!_pointerDown || !widget.enabled) return;
    if (widget.dir8) {
      setState(() => _knob = _knobTarget(e.localPosition, size));
    }
    _setDirection(_dirAt(e.localPosition, size));
  }

  void _onPointerUp(PointerEvent e) {
    _pointerDown = false;
    if (widget.dir8) {
      setState(() => _knob = Offset.zero);
    }
    _setDirection(null);
  }

  // ================= 视觉 =================

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final enabled = widget.enabled;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Listener(
          // 四向十字轮廓外与八向扇环间隙是透明区，opaque 保证整块区域
          // 都收到指针（滑出轮廓换向/回中的手感依赖连续移动）。
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _onPointerDown(e, size),
          onPointerMove: (e) => _onPointerMove(e, size),
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: enabled ? 1.0 : 0.45,
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, inner) {
                  final side = math.min(inner.maxWidth, inner.maxHeight);
                  return widget.dir8
                      ? _buildWheel(context, c, cs, enabled, side)
                      : _buildCrossPad(context, c, cs, enabled, side);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// 四向：标准手柄十字键——单一圆角十字轮廓（画笔）+ 臂中箭头 + 中心凹槽。
  Widget _buildCrossPad(
    BuildContext context,
    ColorStrategy c,
    ColorScheme cs,
    bool enabled,
    double side,
  ) {
    final iconSize = (side * 0.17).clamp(18.0, 40.0);
    return CustomPaint(
      painter: _CrossPadPainter(
        activeDir: _activeDir,
        baseColor: c.surface,
        lineColor: cs.outlineVariant,
        accentColor: cs.primary,
        dishColor: cs.surfaceContainerHighest,
        shadowColor: cs.shadow,
        editMode: widget.editMode,
        hitRatio: widget.hitRatio,
      ),
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(
          children: [
            // 臂中箭头：激活向高亮 + 放大按压反馈。
            for (final e in _dirs.entries)
              Align(
                alignment: _armAlign[e.key]!,
                child: AnimatedScale(
                  scale: _activeDir == e.key ? 1.18 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    e.value,
                    size: iconSize,
                    color: _activeDir == e.key
                        ? cs.primary
                        : (enabled
                              ? c.textMuted
                              : c.textMuted.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            // 中心凹槽图例（编辑态由外层描边框接管说明）。
            if (widget.showLegend)
              Center(
                child: Icon(
                  Icons.sports_esports,
                  size: (side * 0.15).clamp(16.0, 34.0),
                  color: c.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 八向：分段轮盘——8 段圆角扇环 + 段内向外箭头（画笔）+ 中心旋钮。
  Widget _buildWheel(
    BuildContext context,
    ColorStrategy c,
    ColorScheme cs,
    bool enabled,
    double side,
  ) {
    final hubSize = (side * 0.27).clamp(34.0, 72.0);
    return CustomPaint(
      painter: _WheelPainter(
        activeDir: _activeDir,
        baseColor: c.surface,
        lineColor: cs.outlineVariant,
        accentColor: cs.primary,
        arrowIdleColor: enabled
            ? c.textMuted
            : c.textMuted.withValues(alpha: 0.6),
        shadowColor: cs.shadow,
      ),
      child: SizedBox(
        width: side,
        height: side,
        child: Center(
          // 中心旋钮：拖动跟手、松手弹簧回中（带高光顶缘）。
          child: AnimatedContainer(
            duration: _pointerDown
                ? const Duration(milliseconds: 40)
                : const Duration(milliseconds: 420),
            curve: _pointerDown ? Curves.linear : Curves.easeOutBack,
            transform: Matrix4.translationValues(_knob.dx, _knob.dy, 0),
            width: hubSize,
            height: hubSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomCenter,
                colors: [c.surface, cs.surfaceContainerHighest],
              ),
              border: Border.all(
                color: cs.outlineVariant.withValues(
                  alpha: _pointerDown ? 0.95 : 0.6,
                ),
                width: _pointerDown ? 1.6 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: _pointerDown ? 0.22 : 0.10),
                  blurRadius: _pointerDown ? 14 : 6,
                  offset: Offset(0, _pointerDown ? 4 : 2),
                ),
              ],
            ),
            child: widget.showLegend
                ? Icon(
                    Icons.sports_esports,
                    size: hubSize * 0.44,
                    color: c.textMuted,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// 极坐标点（屏幕系：角度顺时针增，0 = 右）。
Offset _polar(Offset c, double r, double a) =>
    c + Offset(math.cos(a), math.sin(a)) * r;

/// 四向十字键画笔：圆角双矩形并集的单一十字轮廓（标准手柄十字键），
/// 激活臂在轮廓内铺主色淡底，中心凹槽碟形；编辑态叠画判定区虚线框
/// （随 hitRatio 缩放，实时预览触控范围）。
class _CrossPadPainter extends CustomPainter {
  const _CrossPadPainter({
    required this.activeDir,
    required this.baseColor,
    required this.lineColor,
    required this.accentColor,
    required this.dishColor,
    required this.shadowColor,
    required this.editMode,
    required this.hitRatio,
  });

  final String? activeDir;
  final Color baseColor;
  final Color lineColor;
  final Color accentColor;
  final Color dishColor;
  final Color shadowColor;
  final bool editMode;
  final double hitRatio;

  /// 圆角十字路径：竖臂 ∪ 横臂（双圆角矩形并集，外角圆润）。
  Path _crossPath(Offset c, double halfLen, double halfW, double radius) {
    final v = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: halfW * 2, height: halfLen * 2),
      Radius.circular(radius),
    );
    final h = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: halfLen * 2, height: halfW * 2),
      Radius.circular(radius),
    );
    return Path.combine(
      PathOperation.union,
      Path()..addRRect(v),
      Path()..addRRect(h),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final halfLen = s * kRtDpadCrossHalfRatio;
    final halfW = s * kRtDpadArmHalfRatio;
    final rOut = s * 0.05;
    final cross = _crossPath(c, halfLen, halfW, rOut);

    // 投影（跟十字剪影，托起按键感）。
    canvas.drawPath(
      cross,
      Paint()
        ..color = shadowColor.withValues(alpha: 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // 底面。
    canvas.drawPath(cross, Paint()..color = baseColor);
    // 激活臂：clip 到十字轮廓内，从中心到臂尖铺主色淡底（连中心区）。
    if (activeDir != null) {
      final Rect arm = switch (activeDir!) {
        'up' => Rect.fromLTRB(c.dx - halfW, c.dy - halfLen, c.dx + halfW, c.dy),
        'down' => Rect.fromLTRB(
          c.dx - halfW,
          c.dy,
          c.dx + halfW,
          c.dy + halfLen,
        ),
        'left' => Rect.fromLTRB(
          c.dx - halfLen,
          c.dy - halfW,
          c.dx,
          c.dy + halfW,
        ),
        _ => Rect.fromLTRB(c.dx, c.dy - halfW, c.dx + halfLen, c.dy + halfW),
      };
      canvas.save();
      canvas.clipPath(cross);
      final tint = Paint()..color = accentColor.withValues(alpha: 0.16);
      canvas.drawRect(arm, tint);
      canvas.drawRect(
        Rect.fromCenter(center: c, width: halfW * 2, height: halfW * 2),
        tint,
      );
      canvas.restore();
    }
    // 描边（激活时主色加重，反馈按在哪条臂）。
    final active = activeDir != null;
    canvas.drawPath(
      cross,
      Paint()
        ..color = active
            ? accentColor.withValues(alpha: 0.85)
            : lineColor.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 2 : 1.4,
    );
    // 中心凹槽碟形（手柄十字键的经典收腰视觉）。
    canvas.drawCircle(
      c,
      halfW * 0.98,
      Paint()..color = dishColor.withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      c,
      halfW * 0.98,
      Paint()
        ..color = lineColor.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // 编辑态：判定区虚线框（随 hitRatio 缩放；默认与视觉轮廓重合，
    // 放大/收紧一眼可见）。
    if (editMode) {
      final jl = math.min(halfLen * hitRatio, s * _kHitClampRatio);
      final jw = math.min(halfW * hitRatio, s * _kHitClampRatio);
      final outline = _crossPath(
        c,
        jl,
        jw,
        math.max(4.0, rOut * hitRatio),
      );
      final dash = Paint()
        ..color = accentColor.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (final metric in outline.computeMetrics()) {
        for (double d = 0; d < metric.length; d += 10) {
          canvas.drawPath(
            metric.extractPath(d, math.min(d + 6, metric.length)),
            dash,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CrossPadPainter oldDelegate) =>
      oldDelegate.activeDir != activeDir ||
      oldDelegate.editMode != editMode ||
      oldDelegate.hitRatio != hitRatio ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.dishColor != dishColor ||
      oldDelegate.shadowColor != shadowColor;
}

/// 八向分段轮盘画笔：8 段圆角扇环（45° 一段，段间留缝）+ 段内向外箭头，
/// 激活段铺主色淡底、箭头主色并微微外推（方向即时可读）。
class _WheelPainter extends CustomPainter {
  const _WheelPainter({
    required this.activeDir,
    required this.baseColor,
    required this.lineColor,
    required this.accentColor,
    required this.arrowIdleColor,
    required this.shadowColor,
  });

  final String? activeDir;
  final Color baseColor;
  final Color lineColor;
  final Color accentColor;
  final Color arrowIdleColor;
  final Color shadowColor;

  /// 单段扇环路径：外弧 + 两角小圆角（二次贝塞尔）+ 径向直边 + 内弧，
  /// 保持利落扇形轮廓（只收外角，不内拉径向边）。
  Path _sectorPath(Offset c, double r1, double r2, double a1, double a2) {
    final span = a2 - a1;
    final dOut = span * 0.10; // 外角沿弧向的圆角缩进
    final e = (r2 - r1) * 0.16; // 外角沿径向的圆角缩进
    final o1 = _polar(c, r2, a1 + dOut); // 外弧左端（圆角后）
    final c1 = _polar(c, r2, a1); // 左外角顶点（控制点）
    final c2 = _polar(c, r2, a2); // 右外角顶点（控制点）
    final q1 = _polar(c, r2 - e, a1); // 左径向边圆角终点
    final q2 = _polar(c, r2 - e, a2); // 右径向边圆角终点
    final i2 = _polar(c, r1, a2);
    return Path()
      ..moveTo(o1.dx, o1.dy)
      // 外弧：a1+dOut → a2-dOut（两端缩进留给圆角）
      ..arcTo(
        Rect.fromCircle(center: c, radius: r2),
        a1 + dOut,
        span - 2 * dOut,
        false,
      )
      // 右外角圆角 → 右径向直边
      ..quadraticBezierTo(c2.dx, c2.dy, q2.dx, q2.dy)
      ..lineTo(i2.dx, i2.dy)
      // 内弧：a2 → a1（直角，扇环内缘）
      ..arcTo(Rect.fromCircle(center: c, radius: r1), a2, -span, false)
      // 左径向直边 → 左外角圆角
      ..lineTo(q1.dx, q1.dy)
      ..quadraticBezierTo(c1.dx, c1.dy, o1.dx, o1.dy)
      ..close();
  }

  /// 段内向外箭头（两笔折线），激活时外推一小段（呼吸感）。
  void _chevron(
    Canvas canvas,
    Offset c,
    double radius,
    double angle,
    double size,
    Color color,
    bool active,
  ) {
    final dir = Offset(math.cos(angle), math.sin(angle));
    final perp = Offset(-dir.dy, dir.dx);
    final push = active ? size * 0.22 : 0.0;
    final tip = c + dir * (radius + size * 0.5 + push);
    final base = c + dir * (radius - size * 0.30 + push);
    final path = Path()
      ..moveTo((base + perp * (size * 0.5)).dx, (base + perp * (size * 0.5)).dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo((base - perp * (size * 0.5)).dx, (base - perp * (size * 0.5)).dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.22
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final r1 = s * 0.27; // 扇环内半径
    final r2 = s * 0.48; // 扇环外半径
    final rm = (r1 + r2) / 2;
    final arrowSize = s * 0.09;
    const gap = 0.06; // 段间缝（弧度，≈3.4°，分段可辨但不散）
    const step = math.pi / 4;

    // 环形投影（跟扇环剪影，不糊住中心孔）。
    canvas.drawCircle(
      c,
      rm,
      Paint()
        ..color = shadowColor.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r2 - r1
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    for (var i = 0; i < 8; i++) {
      final mid = -math.pi / 2 + i * step;
      final a1 = mid - step / 2 + gap / 2;
      final a2 = mid + step / 2 - gap / 2;
      final dir = _kWheelDirs[i];
      final active = activeDir == dir;
      final path = _sectorPath(c, r1, r2, a1, a2);
      canvas.drawPath(
        path,
        Paint()..color = active ? accentColor.withValues(alpha: 0.16) : baseColor,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = active
              ? accentColor.withValues(alpha: 0.9)
              : lineColor.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 2 : 1.2,
      );
      _chevron(
        canvas,
        c,
        rm,
        mid,
        arrowSize,
        active ? accentColor : arrowIdleColor,
        active,
      );
    }
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) =>
      oldDelegate.activeDir != activeDir ||
      oldDelegate.baseColor != baseColor ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.arrowIdleColor != arrowIdleColor ||
      oldDelegate.shadowColor != shadowColor;
}
