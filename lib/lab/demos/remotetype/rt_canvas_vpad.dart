// lib/lab/demos/remotetype/rt_canvas_vpad.dart
//
// 虚拟手柄键区模块（游戏布局右手区）：固定布局的 Xbox 形态按键，
//   · 顶行：LB / LT / RT / RB（肩键 + 扳机）
//   · 主区：ABXY 菱形（Y 上 / X 左 / B 右 / A 下，Xbox 摆位）
// 全部接 PC 端虚拟手柄（rust input-agent vpad_* 指令族）：
//   按下 = vpad_button true / vpad_trigger 1.0；松开 = false / 0.0。
// 按下/松开成对由本组件保证（Listener down/up/cancel），PC 端串行链保序。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context/colors.dart';

/// 触发回调：[button] ∈ a/b/x/y/lb/rb；[trigger] ∈ lt/rt。二者互斥非空；
/// [pressed] = 按下（true）/ 松开（false），每个键各回报一对。
typedef RtVpadKeyCallback = void Function({
  String? button,
  String? trigger,
  required bool pressed,
});

class RtCanvasVpad extends StatelessWidget {
  const RtCanvasVpad({
    super.key,
    required this.enabled,
    required this.onKey,
  });

  /// false（未连接）：置灰且不响应。
  final bool enabled;

  /// 按键事件（press 与 release 各回报一次）。
  final RtVpadKeyCallback onKey;

  /// 统一包装：onDown → pressed: true，onUp → pressed: false。
  void _fire({String? button, String? trigger, required bool pressed}) {
    onKey(button: button, trigger: trigger, pressed: pressed);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // 肩键行高占 22%，主区给 ABXY 菱形。
        final shoulderH = (h * 0.22).clamp(34.0, 64.0);
        final faceD = math.min(
          (w * 0.22).clamp(40.0, 84.0),
          (h - shoulderH) * 0.30,
        );
        return Column(
          children: [
            SizedBox(
              height: shoulderH,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: _VpadHoldButton(
                        label: 'LB',
                        enabled: enabled,
                        round: false,
                        onDown: () => _fire(button: 'lb', pressed: true),
                        onUp: () => _fire(button: 'lb', pressed: false),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _VpadHoldButton(
                        label: 'LT',
                        enabled: enabled,
                        round: false,
                        onDown: () => _fire(trigger: 'lt', pressed: true),
                        onUp: () => _fire(trigger: 'lt', pressed: false),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _VpadHoldButton(
                        label: 'RT',
                        enabled: enabled,
                        round: false,
                        onDown: () => _fire(trigger: 'rt', pressed: true),
                        onUp: () => _fire(trigger: 'rt', pressed: false),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _VpadHoldButton(
                        label: 'RB',
                        enabled: enabled,
                        round: false,
                        onDown: () => _fire(button: 'rb', pressed: true),
                        onUp: () => _fire(button: 'rb', pressed: false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  // ABXY 菱形：Y 上 / X 左 / B 右 / A 下（Xbox 摆位）
                  _diamondSlot(Alignment.topCenter, 'Y', faceD),
                  _diamondSlot(Alignment.centerLeft, 'X', faceD),
                  _diamondSlot(Alignment.centerRight, 'B', faceD),
                  _diamondSlot(Alignment.bottomCenter, 'A', faceD),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _diamondSlot(Alignment alignment, String label, double diameter) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: _VpadHoldButton(
          label: label,
          enabled: enabled,
          round: true,
          diameter: diameter,
          onDown: () => _fire(button: label.toLowerCase(), pressed: true),
          onUp: () => _fire(button: label.toLowerCase(), pressed: false),
        ),
      ),
    );
  }
}

/// 按住型手柄键：down = 按下（press / trigger 1.0），up/cancel = 松开。
/// 按住期间高亮；未连接置灰不响应。
class _VpadHoldButton extends StatefulWidget {
  const _VpadHoldButton({
    required this.label,
    required this.enabled,
    required this.round,
    required this.onDown,
    required this.onUp,
    this.diameter,
  });

  final String label;
  final bool enabled;

  /// true = 圆形（面键）；false = 圆角胶囊（肩键/扳机，撑满分配宽高）。
  final bool round;

  /// 圆形直径；null = 撑满父给定的约束（肩键行）。
  final double? diameter;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  State<_VpadHoldButton> createState() => _VpadHoldButtonState();
}

class _VpadHoldButtonState extends State<_VpadHoldButton> {
  bool _held = false;

  void _down() {
    if (!widget.enabled) return;
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _held = true);
    widget.onDown();
  }

  void _up() {
    if (!_held) return;
    setState(() => _held = false);
    widget.onUp();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final round = widget.round;
    final diameter = widget.diameter;

    final decoration = BoxDecoration(
      shape: round ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: round ? null : BorderRadius.circular(12),
      color: _held ? cs.primary : c.surface,
      border: Border.all(
        color: _held
            ? cs.primary
            : cs.outlineVariant.withValues(alpha: 0.7),
        width: _held ? 2 : 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: cs.shadow.withValues(alpha: _held ? 0.20 : 0.10),
          blurRadius: _held ? 12 : 6,
          offset: Offset(0, _held ? 4 : 2),
        ),
      ],
    );
    final label = Text(
      widget.label,
      maxLines: 1,
      style: TextStyle(
        fontSize: round ? 16 : 13,
        fontWeight: FontWeight.w700,
        color: _held
            ? cs.onPrimary
            : (widget.enabled ? c.text : c.textMuted),
      ),
    );

    final child = Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        decoration: decoration,
        alignment: Alignment.center,
        child: label,
      ),
    );

    if (diameter != null) {
      return SizedBox(width: diameter, height: diameter, child: child);
    }
    return SizedBox.expand(child: child);
  }
}
