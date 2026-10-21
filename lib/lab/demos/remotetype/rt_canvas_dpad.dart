// lib/lab/demos/remotetype/rt_canvas_dpad.dart
//
// 方向轮盘模块（游戏布局左手区）：圆形轮盘，接 PC 端虚拟手柄的十字键。
//   · 手指按到某向 → 立即回报该向（vpad_dpad up/down/left/right）；
//     PC 端虚拟手柄保持该状态，**无需连发**。
//   · 按住滑到另一向 = 换向；滑回中心死区（半径 25%）或松手 = 回报 null
//     （映射为 vpad_dpad 'none' 回中）。
// 方向名与 rust input-agent vpad.rs 的 vpad_dir 白名单一致（up/down/left/
// right/none），经 rt-align normalizeVpadOp 白名单放行。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context/colors.dart';

/// 中心死区占半径比例：指针在死区内 = 无方向（回中）。
const double kRtDpadDeadZoneRatio = 0.25;

class RtCanvasDpad extends StatefulWidget {
  const RtCanvasDpad({
    super.key,
    required this.enabled,
    required this.onDirection,
    this.showLegend = true,
  });

  /// false（未连接）：置灰且不响应。
  final bool enabled;

  /// 方向变化回报：非 null = 新方向（vpad_dpad up/down/left/right）；
  /// null = 回中（vpad_dpad none）。只在变化时回调，不连发。
  final ValueChanged<String?> onDirection;

  /// 编辑态由外层描边框接管说明，图例可不画。
  final bool showLegend;

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

  String? _activeDir;
  bool _pointerDown = false;

  // 旋钮位移（像素，相对轮盘中心）。拖动期间跟手（短延时直出），松手
  // 弹簧回中（easeOutBack 带回弹，对齐原型 knob）。
  Offset _knob = Offset.zero;

  // ================= 方向判定与回报 =================

  /// 指针相对轮盘中心的方向；死区内返回 null。
  String? _dirAt(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final v = local - center;
    final radius = math.min(size.width, size.height) / 2;
    if (v.distance < radius * kRtDpadDeadZoneRatio) return null;
    return v.dx.abs() >= v.dy.abs()
        ? (v.dx >= 0 ? 'right' : 'left')
        : (v.dy >= 0 ? 'down' : 'up');
  }

  /// 旋钮目标位：朝指针方向偏移，钳在半径 55% 内；死区回零。
  Offset _knobTarget(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final v = local - center;
    if (v.distance < radiusOf(size) * kRtDpadDeadZoneRatio) return Offset.zero;
    final maxR = radiusOf(size) * 0.55;
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
    setState(() => _knob = _knobTarget(e.localPosition, size));
    _setDirection(_dirAt(e.localPosition, size));
  }

  void _onPointerMove(PointerMoveEvent e, Size size) {
    if (!_pointerDown || !widget.enabled) return;
    setState(() => _knob = _knobTarget(e.localPosition, size));
    _setDirection(_dirAt(e.localPosition, size));
  }

  void _onPointerUp(PointerEvent e) {
    _pointerDown = false;
    setState(() => _knob = Offset.zero);
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
                  // 箭头/中心毂随轮盘尺寸缩放（小轮盘不撑爆，大轮盘不显空旷）。
                  final side = math.min(inner.maxWidth, inner.maxHeight);
                  final arrowSize = (side * 0.16).clamp(18.0, 34.0);
                  final hubSize = (side * 0.17).clamp(22.0, 36.0);
                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.surface,
                      border: Border.all(
                        color: _activeDir != null
                            ? cs.primary.withValues(alpha: 0.85)
                            : cs.outlineVariant.withValues(alpha: 0.7),
                        width: _activeDir != null ? 2 : 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withValues(alpha: 0.12),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // 四向箭头（激活向高亮 + 弹簧放大 1.22，对齐原型）
                        for (final e in _dirs.entries)
                          Align(
                            alignment: switch (e.key) {
                              'up' => Alignment(0, -0.80),
                              'down' => Alignment(0, 0.80),
                              'left' => Alignment(-0.80, 0),
                              _ => Alignment(0.80, 0),
                            },
                            child: AnimatedScale(
                              scale: _activeDir == e.key ? 1.22 : 1.0,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutBack,
                              child: Icon(
                                e.value,
                                size: arrowSize,
                                color: _activeDir == e.key
                                    ? cs.primary
                                    : (enabled
                                        ? c.textMuted
                                        : c.textMuted.withValues(alpha: 0.6)),
                              ),
                            ),
                          ),
                        // 中心旋钮：拖动跟手、松手弹簧回中（带高光顶缘）。
                        Center(
                          child: AnimatedContainer(
                            duration: _pointerDown
                                ? const Duration(milliseconds: 40)
                                : const Duration(milliseconds: 420),
                            curve: _pointerDown
                                ? Curves.linear
                                : Curves.easeOutBack,
                            transform: Matrix4.translationValues(
                              _knob.dx,
                              _knob.dy,
                              0,
                            ),
                            width: hubSize,
                            height: hubSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomCenter,
                                colors: [
                                  c.surface,
                                  cs.surfaceContainerHighest,
                                ],
                              ),
                              border: Border.all(
                                color: cs.outlineVariant.withValues(
                                  alpha: _pointerDown ? 0.95 : 0.6,
                                ),
                                width: _pointerDown ? 1.6 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: cs.shadow.withValues(
                                    alpha: _pointerDown ? 0.22 : 0.10,
                                  ),
                                  blurRadius: _pointerDown ? 14 : 6,
                                  offset: Offset(0, _pointerDown ? 4 : 2),
                                ),
                              ],
                            ),
                            child: widget.showLegend
                                ? Icon(
                                    Icons.sports_esports,
                                    size: hubSize * 0.5,
                                    color: c.textMuted,
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
