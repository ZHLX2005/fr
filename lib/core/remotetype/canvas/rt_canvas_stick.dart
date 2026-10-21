// lib/core/remotetype/canvas/rt_canvas_stick.dart
//
// 模拟摇杆模块（左 / 右摇杆）：补齐协议已支持、但手机端此前没有的
// 斜向走位能力——4 向轮盘只能「先上再右」两次事件，多数动作游戏不认。
//
// 映射 PC 端虚拟手柄 vpad_axis（rust input-agent vpad.rs）：
//   · 拖动摇杆 → 连续上报 {action:'vpad_axis', vpad_axis:'lx'|'ly'|'rx'|'ry',
//     vpad_value: -1..1}；松手回中（两轴各报 0）。
//   · 坐标口径：右为 +x、**上为 +y**（ViGEmBus 模拟的是 XInput，sThumbLY
//     正值 = 上；与 SDL 的「上为负」相反——两端口径必须与 PC 端 rust
//     input-agent 一致，若那边按 SDL 口径实现，只需翻转本文件一处符号）。
//   · 死区：|v| < 0.12 视为 0（避免微抖漂移）。
// 值按 1/64 量化后只在变化时上报——拖动连发不会打爆链路。
//
// 编辑态：摇杆整体随模块拖动/缩放（模块级编排），摇杆自身的取值手势
// 关闭（与手柄键区同规矩：编排与触发不串台）。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context/colors.dart';

/// 摇杆死区（半径比例）：小于此值视为回中。
const double kRtStickDeadZone = 0.12;

/// 摇杆轴值量化步长（1/64）：拖动连发时避免打爆链路。
const double kRtStickQuantize = 1 / 64;

/// 轴变化回报：[axis] ∈ lx/ly/rx/ry；[value] ∈ -1..1。
typedef RtStickAxisCallback = void Function(String axis, double value);

class RtCanvasStick extends StatefulWidget {
  const RtCanvasStick({
    super.key,
    required this.enabled,
    required this.axes,
    required this.onAxis,
    this.editMode = false,
  });

  /// false（未连接）：置灰且不响应。
  final bool enabled;

  /// 本摇杆负责的轴前缀：'l'（左摇杆 → lx/ly）或 'r'（右摇杆 → rx/ry）。
  final String axes;

  /// 轴值变化回报（量化后仅在变化时触发）。
  final RtStickAxisCallback onAxis;

  /// 编辑态：取值手势关闭（编排走画布模块拖动）。
  final bool editMode;

  @override
  State<RtCanvasStick> createState() => _RtCanvasStickState();
}

class _RtCanvasStickState extends State<RtCanvasStick> {
  // 摇杆当前位移（归一化 -1..1，屏幕坐标：右为 +x、下为 +y）。
  Offset _knob = Offset.zero;

  bool _dragging = false;

  /// 位移 → 轴值（死区 + 量化）。
  static Offset _quantize(Offset v) {
    final len = v.distance;
    if (len < kRtStickDeadZone) return Offset.zero;
    // 量化到 1/64 网格（保持方向），再回夹到圆内。
    final q = Offset(
      (v.dx / kRtStickQuantize).round() * kRtStickQuantize,
      (v.dy / kRtStickQuantize).round() * kRtStickQuantize,
    );
    return q.distance > 1 ? q / q.distance : q;
  }

  void _emit(Offset v) {
    final q = _quantize(v);
    if (q == _knob) return;
    setState(() => _knob = q);
    // 屏幕坐标 → 手柄轴（XInput 口径）：右为 +x、上为 +y。
    widget.onAxis('${widget.axes}x', q.dx.clamp(-1.0, 1.0).toDouble());
    widget.onAxis('${widget.axes}y', (-q.dy).clamp(-1.0, 1.0).toDouble());
  }

  void _onPointerDown(PointerDownEvent e, Size size) {
    if (!widget.enabled || widget.editMode) return;
    _dragging = true;
    unawaited(HapticFeedback.selectionClick());
    _emit(_offsetAt(e.localPosition, size));
  }

  void _onPointerMove(PointerMoveEvent e, Size size) {
    if (!_dragging || !widget.enabled) return;
    _emit(_offsetAt(e.localPosition, size));
  }

  void _onPointerUp(PointerEvent e) {
    if (!_dragging) return;
    _dragging = false;
    // 回中：两轴各报 0（PC 端虚拟摇杆必须收到 0 才停）。
    if (_knob != Offset.zero) {
      setState(() => _knob = Offset.zero);
      widget.onAxis('${widget.axes}x', 0);
      widget.onAxis('${widget.axes}y', 0);
    }
  }

  /// 指针相对圆心的位移（**归一化** -1..1，半径 = 1）。
  Offset _offsetAt(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    if (r <= 0) return Offset.zero;
    final v = (local - center) / r;
    return v.distance <= 1 ? v : v / v.distance;
  }

  @override
  void dispose() {
    // 卸载时若摇杆仍偏着，必须回中上报——否则 PC 端虚拟摇杆保持倾斜，
    // 角色会一直往一个方向走（与手柄键卡死同源问题）。
    if (_knob != Offset.zero) {
      widget.onAxis('${widget.axes}x', 0);
      widget.onAxis('${widget.axes}y', 0);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final side = math.min(size.width, size.height);
        final knobSize = side * 0.42;
        final radius = side / 2;
        return Listener(
          // opaque：内部是纯装饰（不参与命中测试），必须由 Listener 自己
          // 吃下整块圆面，否则拖不动。
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _onPointerDown(e, size),
          onPointerMove: (e) => _onPointerMove(e, size),
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: widget.enabled ? 1.0 : 0.45,
            child: Center(
              child: SizedBox(
                width: side,
                height: side,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // 底盘：凹槽感（内阴影 + 描边）
                    Container(
                      width: side,
                      height: side,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.surface,
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.7),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                    // 方向刻度（十字虚线，弱）
                    IgnorePointer(
                      child: CustomPaint(
                        size: Size(side, side),
                        painter: _StickCrossPainter(color: cs.outlineVariant),
                      ),
                    ),
                    // 摇杆头
                    Transform.translate(
                      offset: Offset(
                        _knob.dx * (radius - knobSize / 2),
                        _knob.dy * (radius - knobSize / 2),
                      ),
                      child: Container(
                        width: knobSize,
                        height: knobSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomCenter,
                            colors: [c.surface, cs.surfaceContainerHighest],
                          ),
                          border: Border.all(
                            color: _dragging
                                ? cs.primary.withValues(alpha: 0.85)
                                : cs.outlineVariant.withValues(alpha: 0.7),
                            width: _dragging ? 2 : 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.shadow.withValues(
                                alpha: _dragging ? 0.24 : 0.14,
                              ),
                              blurRadius: _dragging ? 14 : 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.gamepad_outlined,
                          size: knobSize * 0.42,
                          color: c.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 摇杆底盘的十字刻度（弱装饰，指示轴向）。
class _StickCrossPainter extends CustomPainter {
  const _StickCrossPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    canvas
      ..drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), paint)
      ..drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), paint);
  }

  @override
  bool shouldRepaint(_StickCrossPainter oldDelegate) =>
      oldDelegate.color != color;
}
