// lib/core/remotetype/canvas/rt_canvas_dpad.dart
//
// 方向模块（游戏布局左手区），两种布局（[dir8]）：
//   · false = 四向键（默认）：上下左右 4 颗独立按键十字排布。
//     按到某键 → 立即回报该向（vpad_dpad up/down/left/right）；
//     PC 端虚拟手柄保持该状态，**无需连发**。按住滑到另一键 = 换向；
//     滑回中心毂或松手 = 回报 null（映射 vpad_dpad 'none' 回中）。
//     命中按十字矩形：|dy| ≤ 臂厚归左右、|dx| ≤ 臂厚归上下，
//     斜角空隙不触发（四向键语义，不产生斜向）。
//   · true = 八向轮盘：圆形轮盘，45° 扇区（22.5° 为界）判向，
//     补 up_left/up_right/down_left/down_right 四个斜向；
//     旋钮拖动跟手、松手弹簧回中。
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

/// 四向键：单键边长占模块边长比例；臂半厚 ≈ 0.17 * side。
const double kRtDpadKeySideRatio = 0.34;

class RtCanvasDpad extends StatefulWidget {
  const RtCanvasDpad({
    super.key,
    required this.enabled,
    required this.onDirection,
    this.showLegend = true,
    this.dir8 = false,
  });

  /// false（未连接）：置灰且不响应。
  final bool enabled;

  /// 方向变化回报：非 null = 新方向（vpad_dpad up/down/left/right，
  /// 八向轮盘另加 up_left/up_right/down_left/down_right）；
  /// null = 回中（vpad_dpad none）。只在变化时回调，不连发。
  final ValueChanged<String?> onDirection;

  /// 编辑态由外层描边框接管说明，图例可不画。
  final bool showLegend;

  /// 方向布局：false = 四向键（默认）；true = 八向轮盘（补四个斜向）。
  final bool dir8;

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

  /// 四向键的对齐锚点（中心偏移占半边比例）。
  static const _keyAlign = <String, Alignment>{
    'up': Alignment(0, -0.62),
    'down': Alignment(0, 0.62),
    'left': Alignment(-0.62, 0),
    'right': Alignment(0.62, 0),
  };

  /// 八向轮盘的四个斜向箭头（四角，尺寸小于正方向箭头）。
  static const _diagDirs = <String, IconData>{
    'up_left': Icons.north_west,
    'up_right': Icons.north_east,
    'down_left': Icons.south_west,
    'down_right': Icons.south_east,
  };

  String? _activeDir;
  bool _pointerDown = false;

  // 旋钮位移（像素，相对轮盘中心，仅八向轮盘用）。拖动期间跟手（短延时
  // 直出），松手弹簧回中（easeOutBack 带回弹，对齐原型 knob）。
  Offset _knob = Offset.zero;

  // ================= 方向判定与回报 =================

  /// 指针相对模块中心的方向；中心毂/空隙返回 null。
  String? _dirAt(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final v = local - center;
    final radius = math.min(size.width, size.height) / 2;
    if (!widget.dir8) {
      // 四向键：十字矩形命中。臂半厚 = 键边长一半 ≈ 0.17 * side。
      final t = radius * kRtDpadKeySideRatio;
      final ax = v.dx.abs();
      final ay = v.dy.abs();
      if (ax <= t && ay <= t) return null; // 中心毂
      if (ay <= t) return v.dx >= 0 ? 'right' : 'left'; // 横臂
      if (ax <= t) return v.dy >= 0 ? 'down' : 'up'; // 竖臂
      return null; // 斜角空隙（四向键不出斜向）
    }
    // 八向轮盘：先看死区（半径 25%）。
    if (v.distance < radius * kRtDpadDeadZoneRatio) return null;
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

  /// 旋钮目标位（仅八向轮盘）：朝指针方向偏移，钳在半径 55% 内；死区回零。
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
          // 四向键布局键间有空隙（透明区），opaque 保证整块区域都收到指针。
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
                      : _buildCrossKeys(context, c, cs, enabled, side);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// 四向键：上下左右 4 颗独立按键十字排布 + 中心毂。
  Widget _buildCrossKeys(
    BuildContext context,
    ColorStrategy c,
    ColorScheme cs,
    bool enabled,
    double side,
  ) {
    final keySide = side * kRtDpadKeySideRatio;
    final hubSide = side * 0.30;

    Widget key(String dir) {
      final active = _activeDir == dir;
      return Align(
        alignment: _keyAlign[dir]!,
        child: AnimatedScale(
          scale: active ? 1.06 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: keySide,
            height: keySide,
            decoration: BoxDecoration(
              color: active ? cs.primary.withValues(alpha: 0.16) : c.surface,
              borderRadius: BorderRadius.circular(keySide * 0.26),
              border: Border.all(
                color: active
                    ? cs.primary.withValues(alpha: 0.9)
                    : cs.outlineVariant.withValues(alpha: 0.7),
                width: active ? 2 : 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: active ? 0.20 : 0.10),
                  blurRadius: active ? 12 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              _dirs[dir],
              size: keySide * 0.52,
              color: active
                  ? cs.primary
                  : (enabled
                        ? c.textMuted
                        : c.textMuted.withValues(alpha: 0.6)),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        for (final dir in _dirs.keys) key(dir),
        // 中心毂：图例（编辑态由外层描边框接管说明）。
        Center(
          child: Container(
            width: hubSide,
            height: hubSide,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.surface,
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: widget.showLegend
                ? Icon(
                    Icons.sports_esports,
                    size: hubSide * 0.5,
                    color: c.textMuted,
                  )
                : null,
          ),
        ),
      ],
    );
  }

  /// 八向轮盘：圆形轮盘 + 四正向/四斜向箭头 + 中心旋钮。
  Widget _buildWheel(
    BuildContext context,
    ColorStrategy c,
    ColorScheme cs,
    bool enabled,
    double side,
  ) {
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
          // 四正向箭头（激活向高亮 + 弹簧放大 1.22，对齐原型）
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
          // 四角斜向箭头（尺寸小于正方向，激活同规则）。
          for (final e in _diagDirs.entries)
            Align(
              alignment: switch (e.key) {
                'up_left' => Alignment(-0.68, -0.68),
                'up_right' => Alignment(0.68, -0.68),
                'down_left' => Alignment(-0.68, 0.68),
                _ => Alignment(0.68, 0.68),
              },
              child: AnimatedScale(
                scale: _activeDir == e.key ? 1.22 : 1.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: Icon(
                  e.value,
                  size: arrowSize * 0.72,
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
                      size: hubSize * 0.5,
                      color: c.textMuted,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
