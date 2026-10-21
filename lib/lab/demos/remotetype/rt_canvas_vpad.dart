// lib/lab/demos/remotetype/rt_canvas_vpad.dart
//
// 虚拟手柄键区模块（游戏布局右手区）：固定布局的 Xbox 形态按键，
//   · 顶行：LB / LT / RT / RB（肩键 + 扳机）
//   · 主区：ABXY 菱形（Y 上 / X 左 / B 右 / A 下，Xbox 摆位）
// 几何对齐 docs/prototypes/rt-canvas-gamepad.html：肩键行高 max(36, h*0.16)、
// 宽 82% 居中；面键直径 min(fw*0.36, fh*0.34)、臂长 0.80*d、绝对定位。
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

/// Xbox 面键惯例色（fr design_tokens fA/fB/fX/fY 原值，跨主题恒定——
/// 玩家对面键颜色的记忆点大于主题统一性，原型同源）。
const Map<String, Color> _kFaceColors = {
  'A': Color(0xFF3FB950),
  'B': Color(0xFFF0524D),
  'X': Color(0xFF4C8DF6),
  'Y': Color(0xFFE3B341),
};

/// Y 键底色偏亮，按住填充时用深字保对比（其余面键白字），原型同规。
const Color _kFaceYOnColor = Color(0xFF2C2A24);

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
        // 原型：shH = max(36, mh*0.16)；shoulders 宽 82% 居中；肩键与面区 gap 10。
        final shoulderH = math.max(36.0, h * 0.16);
        const gap = 10.0;
        final faceH = math.max(0.0, h - shoulderH - gap);
        final faceW = w;
        final d = math.min(faceW * 0.36, faceH * 0.34);
        final arm = d * 0.80;
        final cx = faceW / 2;
        final cy = faceH / 2;
        final spots = <String, Offset>{
          'Y': Offset(cx, cy - arm),
          'X': Offset(cx - arm, cy),
          'B': Offset(cx + arm, cy),
          'A': Offset(cx, cy + arm),
        };
        return Column(
          children: [
            Align(
              child: SizedBox(
                width: w * 0.82,
                height: shoulderH,
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
                    const SizedBox(width: 7),
                    Expanded(
                      child: _VpadHoldButton(
                        label: 'LT',
                        enabled: enabled,
                        round: false,
                        onDown: () => _fire(trigger: 'lt', pressed: true),
                        onUp: () => _fire(trigger: 'lt', pressed: false),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: _VpadHoldButton(
                        label: 'RT',
                        enabled: enabled,
                        round: false,
                        onDown: () => _fire(trigger: 'rt', pressed: true),
                        onUp: () => _fire(trigger: 'rt', pressed: false),
                      ),
                    ),
                    const SizedBox(width: 7),
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
            const SizedBox(height: gap),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final k in const ['Y', 'X', 'B', 'A'])
                    Positioned(
                      left: spots[k]!.dx - d / 2,
                      top: spots[k]!.dy - d / 2,
                      width: d,
                      height: d,
                      child: _VpadHoldButton(
                        label: k,
                        enabled: enabled,
                        round: true,
                        diameter: d,
                        faceColor: _kFaceColors[k],
                        onDown: () =>
                            _fire(button: k.toLowerCase(), pressed: true),
                        onUp: () =>
                            _fire(button: k.toLowerCase(), pressed: false),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 按住型手柄键：down = 按下（press / trigger 1.0），up/cancel = 松开。
/// 手感对齐原型（iOS Q 弹）：按下缩至 0.88 弹回、held 同色辉光、键面顶部
/// 高光。未连接置灰不响应。
class _VpadHoldButton extends StatefulWidget {
  const _VpadHoldButton({
    required this.label,
    required this.enabled,
    required this.round,
    required this.onDown,
    required this.onUp,
    this.diameter,
    this.faceColor,
  });

  final String label;
  final bool enabled;

  /// true = 圆形（面键）；false = 圆角胶囊（肩键/扳机，撑满分配宽高）。
  final bool round;

  /// 圆形直径；null = 撑满父给定的约束（肩键行）。
  final double? diameter;

  /// 面键彩色环（A 绿 / B 红 / X 蓝 / Y 黄）；null = 中性键（肩键/扳机）。
  final Color? faceColor;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  State<_VpadHoldButton> createState() => _VpadHoldButtonState();
}

class _VpadHoldButtonState extends State<_VpadHoldButton> {
  bool _held = false;

  void _down() {
    // 卸载后迟到的 pointer 事件仍会派发到缓存的命中路径（旋转 / 切布局
    // 场景实测可复现）：defunct 态一律吞掉，release 已由 dispose 补发。
    if (!widget.enabled || !mounted) return;
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _held = true);
    widget.onDown();
  }

  void _up() {
    if (!_held || !mounted) return;
    setState(() => _held = false);
    widget.onUp();
  }

  @override
  void dispose() {
    // 按住期间模块被卸载（旋转 / 切布局 / 退画布）：Listener 收不到
    // pointer cancel，必须在这里补发松开——否则 PC 端虚拟手柄该键卡死。
    if (_held) widget.onUp();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final round = widget.round;
    final diameter = widget.diameter;
    final face = widget.faceColor;
    final accent = face ?? cs.primary;
    // Y 键亮底深字，其余按住填充白字（原型同规）。
    final onAccent =
        widget.label == 'Y' ? _kFaceYOnColor : (face ?? cs.onPrimary);

    final decoration = BoxDecoration(
      shape: round ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: round ? null : BorderRadius.circular(999),
      gradient: _held
          ? null
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                c.surface,
                Color.alphaBlend(
                  cs.outlineVariant.withValues(alpha: 0.16),
                  c.surface,
                ),
              ],
            ),
      color: _held ? accent : null,
      border: Border.all(
        color: _held
            ? accent
            : (face ??
                cs.outlineVariant.withValues(alpha: 0.7)),
        width: _held ? 2 : (face != null ? 2 : 1.2),
      ),
      boxShadow: [
        BoxShadow(
          color: _held
              ? accent.withValues(alpha: face != null ? 0.50 : 0.40)
              : cs.shadow.withValues(alpha: 0.10),
          blurRadius: _held ? 18 : 6,
          offset: Offset(0, _held ? 4 : 2),
        ),
      ],
    );
    final label = Text(
      widget.label,
      maxLines: 1,
      style: TextStyle(
        fontSize: round ? 14 : 11,
        fontWeight: FontWeight.w700,
        letterSpacing: round ? 0 : 0.8,
        color: _held
            ? onAccent
            : (face ??
                (widget.enabled ? c.text : c.textMuted)),
      ),
    );

    final child = Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: AnimatedScale(
        // 按压缩放回弹：easeOutBack 双向都带一点 overshoot（Q 弹手感）。
        scale: _held ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: decoration,
          alignment: Alignment.center,
          child: label,
        ),
      ),
    );

    if (diameter != null) {
      return SizedBox(width: diameter, height: diameter, child: child);
    }
    return SizedBox.expand(child: child);
  }
}
