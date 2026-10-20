// lib/lab/demos/remotetype/rt_canvas_dpad.dart
//
// 方向轮盘模块（游戏布局左手区）：圆形轮盘，上下左右四向发方向键。
//   · 按下立即发一发；按住不松 160ms 连发（游戏里按住 = 持续移动）。
//   · 按住期间手指滑到另一向 = 换向（先停旧向连发，新向立即发一发）。
//   · 滑回中心死区（半径 25%）= 停发不松手；再滑出 = 恢复。
// 方向键名走 syncHotkey 既有词汇（'up'/'down'/'left'/'right'，与快捷键
// 编辑器 RtKeyDisplay 同一套键名表）。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context/colors.dart';

/// 轮盘连发间隔。
const Duration kRtDpadRepeatInterval = Duration(milliseconds: 160);

/// 中心死区占半径比例：指针在死区内 = 无方向（停发）。
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

  /// 方向触发（含连发的每一发）。key ∈ 'up'/'down'/'left'/'right'。
  final ValueChanged<String> onDirection;

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
  Timer? _repeat;
  bool _pointerDown = false;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  // ================= 方向判定与连发 =================

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

  void _setDirection(String? dir) {
    if (dir == _activeDir) return;
    _repeat?.cancel();
    _repeat = null;
    setState(() => _activeDir = dir);
    if (dir == null) return;
    unawaited(HapticFeedback.selectionClick());
    widget.onDirection(dir);
    _repeat = Timer.periodic(kRtDpadRepeatInterval, (_) {
      if (mounted && widget.enabled) widget.onDirection(dir);
    });
  }

  void _onPointerDown(PointerDownEvent e, Size size) {
    if (!widget.enabled) return;
    _pointerDown = true;
    unawaited(HapticFeedback.mediumImpact());
    _setDirection(_dirAt(e.localPosition, size));
  }

  void _onPointerMove(PointerMoveEvent e, Size size) {
    if (!_pointerDown || !widget.enabled) return;
    _setDirection(_dirAt(e.localPosition, size));
  }

  void _onPointerUp(PointerEvent e) {
    _pointerDown = false;
    _setDirection(null);
  }

  // ================= 视觉 =================

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final enabled = widget.enabled;

    return LayoutBuilder(builder: (context, constraints) {
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
            child: Container(
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
                  // 四向箭头（激活向高亮）
                  for (final e in _dirs.entries)
                    Align(
                      alignment: switch (e.key) {
                        'up' => Alignment(0, -0.82),
                        'down' => Alignment(0, 0.82),
                        'left' => Alignment(-0.82, 0),
                        _ => Alignment(0.82, 0),
                      },
                      child: Icon(
                        e.value,
                        size: 30,
                        color: _activeDir == e.key
                            ? cs.primary
                            : (enabled
                                ? c.textMuted
                                : c.textMuted.withValues(alpha: 0.6)),
                      ),
                    ),
                  // 中心毂
                  Center(
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cs.surfaceContainerHighest,
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      child: widget.showLegend
                          ? Icon(Icons.sports_esports,
                              size: 15, color: c.textMuted)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}
