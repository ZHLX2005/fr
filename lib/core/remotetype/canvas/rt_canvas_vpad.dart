// lib/core/remotetype/canvas/rt_canvas_vpad.dart
//
// 虚拟手柄键区模块（游戏布局右手区）：Xbox 形态按键，
//   · 顶行：LB / LT / RT / RB（肩键 + 扳机）
//   · 主区：ABXY 菱形（Y 上 / X 左 / B 右 / A 下，Xbox 摆位）
// 几何对齐 docs/prototypes/rt-canvas-gamepad.html：肩键行高 max(36, h*0.16)、
// 宽 82% 居中；面键直径 min(fw*0.36, fh*0.34)、臂长 0.80*d。
// 全部接 PC 端虚拟手柄（rust input-agent vpad_* 指令族）：
//   按下 = vpad_button true / vpad_trigger 1.0；松开 = false / 0.0。
// 按下/松开成对由本组件保证（Listener down/up/cancel + dispose 补发），
// PC 端串行链保序。
//
// 编辑态逐键编排：每个键可独立拖动（中心 = 模块盒内像素，钳在盒内）与
// 缩放（拉手，倍率钳 0.6..2.2）。键位以「模块盒内比例」持久化在布局
// buttons（id = vpad:<key>）——模块整体拖/缩时比例随盒子缩放，未自定义的
// 键回落出厂几何（[rtVpadDefaultSlots]），零迁移。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context/colors.dart';
import '../data/rt_prefs.dart' show kRtCanvasBtnScaleMax, kRtCanvasBtnScaleMin;

/// 触发回调：[button] ∈ a/b/x/y/lb/rb；[trigger] ∈ lt/rt。二者互斥非空；
/// [pressed] = 按下（true）/ 松开（false），每个键各回报一对。
typedef RtVpadKeyCallback =
    void Function({String? button, String? trigger, required bool pressed});

/// 编辑态逐键变换回报：[centerFraction] = 键中心在模块盒内的比例位（0..1，
/// 拖动落定）；[scale] = 键尺寸倍率（拉手落定）。一次回报带全量两维，
/// 调用方整条写 buttons，免空维合并。
typedef RtVpadKeyTransformCallback =
    void Function(String key, Offset centerFraction, double scale);

/// 手柄键名（buttons 持久化 id = vpad:<名>）。
const List<String> rtVpadKeyOrder = [
  'lb',
  'lt',
  'rt',
  'rb',
  'y',
  'x',
  'b',
  'a',
];

const Set<String> _kShoulderKeys = {'lb', 'lt', 'rt', 'rb'};

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

/// 键显示名（大写，与原 vpad 键区一致）。
String rtVpadKeyLabel(String key) => key.toUpperCase();

/// 肩键行高（模块盒内像素）。
double _rtVpadShoulderH(double boxH) => math.max(36.0, boxH * 0.16);

/// 键出厂几何：键名 → 模块盒内中心（像素）。设置页 / 画布渲染 / 单测
/// 三处同源；几何对齐原型（见文件头）。
Map<String, Offset> rtVpadDefaultSlots(Size box) {
  final w = box.width;
  final h = box.height;
  final shoulderH = _rtVpadShoulderH(h);
  const gap = 10.0;
  final faceH = math.max(0.0, h - shoulderH - gap);
  final rowW = w * 0.82;
  final keyW = (rowW - 3 * 7) / 4;
  final left = (w - rowW) / 2;
  final slots = <String, Offset>{
    for (var i = 0; i < _kShoulderKeys.length; i++)
      rtVpadKeyOrder[i]: Offset(left + (i + 0.5) * keyW + i * 7, shoulderH / 2),
  };
  final d = _rtVpadFaceD(w, faceH);
  final arm = d * 0.80;
  final cy = shoulderH + gap + faceH / 2;
  slots['y'] = Offset(w / 2, cy - arm);
  slots['x'] = Offset(w / 2 - arm, cy);
  slots['b'] = Offset(w / 2 + arm, cy);
  slots['a'] = Offset(w / 2, cy + arm);
  return slots;
}

/// 面键出厂直径（模块盒内像素）。
double _rtVpadFaceD(double boxW, double faceH) =>
    math.min(boxW * 0.36, faceH * 0.34);

/// 键出厂尺寸（模块盒内像素）：面键 = 直径方形；肩键 = 行内等分 × 行高。
Size rtVpadDefaultKeySize(String key, Size box) {
  final w = box.width;
  final shoulderH = _rtVpadShoulderH(box.height);
  const gap = 10.0;
  final faceH = math.max(0.0, box.height - shoulderH - gap);
  if (_kShoulderKeys.contains(key)) {
    final keyW = (w * 0.82 - 3 * 7) / 4;
    return Size(keyW, shoulderH);
  }
  final d = _rtVpadFaceD(w, faceH);
  return Size(d, d);
}

class RtCanvasVpad extends StatefulWidget {
  const RtCanvasVpad({
    super.key,
    required this.enabled,
    required this.onKey,
    this.keyOffsets = const {},
    this.keyScales = const {},
    this.editMode = false,
    this.onKeyTransform,
  });

  /// false（未连接）：置灰且不响应。
  final bool enabled;

  /// 按键事件（press 与 release 各回报一次）。
  final RtVpadKeyCallback onKey;

  /// 键名 → 模块盒内中心（像素）。缺条目的键回落出厂几何。
  final Map<String, Offset> keyOffsets;

  /// 键名 → 尺寸倍率（乘在出厂尺寸上）。缺条目 = 1.0。
  final Map<String, double> keyScales;

  /// 编辑态：键可拖动/缩放，按住不触发手柄事件。
  final bool editMode;

  /// 编辑态逐键变换落定（拖动松手 / 拉手松手各回报一次）。
  final RtVpadKeyTransformCallback? onKeyTransform;

  @override
  State<RtCanvasVpad> createState() => _RtCanvasVpadState();
}

class _RtCanvasVpadState extends State<RtCanvasVpad> {
  // 拖动/缩放的本地预览（松手一次性回写，所见即所得；与模块拖动同套路）。
  final Map<String, Offset> _previewCenters = {};
  final Map<String, double> _previewScales = {};
  Offset? _dragGrabDelta;

  Offset _effectiveCenter(String key, Size box) {
    final preview = _previewCenters[key];
    if (preview != null) return preview;
    final saved = widget.keyOffsets[key];
    if (saved != null) return saved;
    return rtVpadDefaultSlots(box)[key]!;
  }

  double _effectiveScale(String key) {
    final preview = _previewScales[key];
    if (preview != null) return preview;
    return widget.keyScales[key] ?? 1.0;
  }

  Size _keySize(String key, Size box) {
    final base = rtVpadDefaultKeySize(key, box);
    final s = _effectiveScale(key);
    return Size(base.width * s, base.height * s);
  }

  /// 键中心钳回模块盒内（键完整在场）。
  Offset _clampCenter(String key, Offset center, Size box) {
    final size = _keySize(key, box);
    final cx = center.dx.clamp(
      size.width / 2,
      box.width < size.width ? size.width / 2 : box.width - size.width / 2,
    );
    final cy = center.dy.clamp(
      size.height / 2,
      box.height < size.height ? size.height / 2 : box.height - size.height / 2,
    );
    return Offset(cx, cy);
  }

  void _fire({String? button, String? trigger, required bool pressed}) {
    widget.onKey(button: button, trigger: trigger, pressed: pressed);
  }

  // ---- 编辑态：逐键拖动 / 缩放 ----

  void _startKeyDrag(String key, Size box) {
    HapticFeedback.mediumImpact();
    setState(() {
      // 起点取当前有效中心（像素，模块盒内坐标）；后续按 delta 累加——
      // 不用 global 位减 local 位（两套坐标系混算会跳）。
      _dragGrabDelta = _effectiveCenter(key, box);
      _previewCenters[key] = _dragGrabDelta!;
    });
  }

  void _updateKeyDrag(String key, Offset delta, Size box) {
    final start = _dragGrabDelta;
    if (start == null) return;
    setState(() {
      _previewCenters[key] = _clampCenter(key, start + delta, box);
    });
  }

  void _endKeyDrag(String key, Size box) {
    final center = _previewCenters[key];
    if (center == null) return;
    setState(() => _previewCenters.remove(key));
    _dragGrabDelta = null;
    final fraction = Offset(
      (center.dx / box.width).clamp(0.0, 1.0).toDouble(),
      (center.dy / box.height).clamp(0.0, 1.0).toDouble(),
    );
    widget.onKeyTransform?.call(key, fraction, _effectiveScale(key));
    unawaited(HapticFeedback.selectionClick());
  }

  void _startKeyScale(String key) {
    HapticFeedback.mediumImpact();
    setState(() => _previewScales[key] = _effectiveScale(key));
  }

  void _updateKeyScale(String key, double delta) {
    if (_previewScales[key] == null) return;
    setState(() {
      _previewScales[key] = (_previewScales[key]! + delta / 160)
          .clamp(kRtCanvasBtnScaleMin, kRtCanvasBtnScaleMax)
          .toDouble();
    });
  }

  void _endKeyScale(String key, Size box) {
    final scale = _previewScales[key];
    if (scale == null) return;
    setState(() => _previewScales.remove(key));
    final center = _clampCenter(key, _effectiveCenter(key, box), box);
    widget.onKeyTransform?.call(
      key,
      Offset(
        (center.dx / box.width).clamp(0.0, 1.0).toDouble(),
        (center.dy / box.height).clamp(0.0, 1.0).toDouble(),
      ),
      scale,
    );
    unawaited(HapticFeedback.selectionClick());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        return Stack(
          clipBehavior: Clip.none,
          children: [for (final key in rtVpadKeyOrder) _buildKey(key, box)],
        );
      },
    );
  }

  Widget _buildKey(String key, Size box) {
    final center = _clampCenter(key, _effectiveCenter(key, box), box);
    final size = _keySize(key, box);
    final isShoulder = _kShoulderKeys.contains(key);
    Widget keyWidget = _VpadHoldButton(
      label: rtVpadKeyLabel(key),
      enabled: widget.enabled,
      interactive: !widget.editMode,
      round: !isShoulder,
      diameter: isShoulder ? null : size.width,
      faceColor: _kFaceColors[key.toUpperCase()],
      onDown: () => _fire(
        button: _kShoulderKeys.contains(key) && key != 'lb' && key != 'rb'
            ? null
            : key,
        trigger: key == 'lt' || key == 'rt' ? key : null,
        pressed: true,
      ),
      onUp: () => _fire(
        button: _kShoulderKeys.contains(key) && key != 'lb' && key != 'rb'
            ? null
            : key,
        trigger: key == 'lt' || key == 'rt' ? key : null,
        pressed: false,
      ),
    );
    if (widget.editMode && widget.onKeyTransform != null) {
      keyWidget = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _startKeyDrag(key, box),
        onPanUpdate: (d) => _updateKeyDrag(key, d.delta, box),
        onPanEnd: (_) => _endKeyDrag(key, box),
        onPanCancel: () {
          if (_previewCenters.containsKey(key)) {
            setState(() => _previewCenters.remove(key));
          }
        },
        child: keyWidget,
      );
      // 逐键缩放拉手（右下角，命中区大于视觉）。
      keyWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          keyWidget,
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => _startKeyScale(key),
              onPanUpdate: (d) => _updateKeyScale(key, d.delta.dx),
              onPanEnd: (_) => _endKeyScale(key, box),
              onPanCancel: () {
                if (_previewScales.containsKey(key)) {
                  setState(() => _previewScales.remove(key));
                }
              },
              child: SizedBox(
                width: 34,
                height: 34,
                child: Center(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: context.colors.scheme.primary.withValues(
                        alpha: 0.92,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: context.colors.scheme.surface,
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      Icons.open_in_full,
                      size: 9,
                      color: context.colors.scheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Positioned(
      left: center.dx - size.width / 2,
      top: center.dy - size.height / 2,
      width: size.width,
      height: size.height,
      child: keyWidget,
    );
  }
}

/// 按住型手柄键：down = 按下（press / trigger 1.0），up/cancel = 松开。
/// 手感对齐原型（iOS Q 弹）：按下缩至 0.88 弹回、held 同色辉光、键面顶部
/// 高光。未连接 / 编辑态不响应按压（编辑态键只做拖动编排）。
class _VpadHoldButton extends StatefulWidget {
  const _VpadHoldButton({
    required this.label,
    required this.enabled,
    required this.interactive,
    required this.round,
    required this.onDown,
    required this.onUp,
    this.diameter,
    this.faceColor,
  });

  final String label;
  final bool enabled;

  /// false（编辑态）：置灰之外的按压完全关断（拖动编排期间不发事件）。
  final bool interactive;

  /// true = 圆形（面键）；false = 圆角胶囊（肩键/扳机，撑满给定尺寸）。
  final bool round;

  /// 圆形直径；null = 用 [size] 撑满（肩键行）。
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
    if (!widget.enabled || !widget.interactive || !mounted) return;
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
    final onAccent = widget.label == 'Y'
        ? _kFaceYOnColor
        : (face ?? cs.onPrimary);

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
            : (face ?? cs.outlineVariant.withValues(alpha: 0.7)),
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
        fontSize: round ? 16 : 13,
        fontWeight: FontWeight.w700,
        color: _held
            ? onAccent
            : (face ?? (widget.enabled ? c.text : c.textMuted)),
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
          width: diameter,
          height: diameter,
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
