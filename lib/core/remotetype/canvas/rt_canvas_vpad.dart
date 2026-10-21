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
/// 13 键 = 协议面键全量：ABXY + LB/RB + BACK/START/GUIDE + L3/R3，
/// 外加 LT/RT 扳机（trigger 通道）。
const List<String> rtVpadKeyOrder = [
  'lb',
  'lt',
  'rt',
  'rb',
  'back',
  'start',
  'guide',
  'y',
  'x',
  'b',
  'a',
  'l3',
  'r3',
];

const Set<String> _kShoulderKeys = {'lb', 'lt', 'rt', 'rb'};

/// 系统面键行（BACK / START / GUIDE）。
const Set<String> _kSystemKeys = {'back', 'start', 'guide'};

/// 摇杆键（L3 / R3 = 摇杆中心点击）。
const Set<String> _kStickKeys = {'l3', 'r3'};

/// ABXY 面键（彩色环）。
const Set<String> _kFaceKeys = {'a', 'b', 'x', 'y'};

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
  final faceH = math.max(0.0, h - shoulderH - gap - _rtVpadSystemH(h) - gap);
  final rowW = w * 0.82;
  final keyW = (rowW - 3 * 7) / 4;
  final left = (w - rowW) / 2;
  final slots = <String, Offset>{
    for (var i = 0; i < _kShoulderKeys.length; i++)
      rtVpadKeyOrder[i]: Offset(left + (i + 0.5) * keyW + i * 7, shoulderH / 2),
  };
  // 系统面键行（BACK / START / GUIDE）：肩键行下方居中一排小键。
  final sysW = w * 0.58;
  final sysKeyW = (sysW - 2 * 6) / 3;
  final sysLeft = (w - sysW) / 2;
  final sysRowY = shoulderH + gap + _rtVpadSystemH(h) / 2;
  const sysOrder = ['back', 'start', 'guide'];
  for (var i = 0; i < sysOrder.length; i++) {
    slots[sysOrder[i]] = Offset(sysLeft + (i + 0.5) * sysKeyW + i * 6, sysRowY);
  }
  final d = _rtVpadFaceD(w, faceH);
  final arm = d * 0.80;
  final cy = shoulderH + gap + _rtVpadSystemH(h) + gap + faceH / 2;
  slots['y'] = Offset(w / 2, cy - arm);
  slots['x'] = Offset(w / 2 - arm, cy);
  slots['b'] = Offset(w / 2 + arm, cy);
  slots['a'] = Offset(w / 2, cy + arm);
  // 摇杆键：模块盒左右下角（Xbox 摆位：L3 左 / R3 右）。
  final stickD = _rtVpadStickKeyD(w, h);
  final stickY = h - stickD / 2 - 4;
  slots['l3'] = Offset(stickD / 2 + 4, stickY);
  slots['r3'] = Offset(w - stickD / 2 - 4, stickY);
  return slots;
}

/// 系统面键行高（BACK / START / GUIDE）。
double _rtVpadSystemH(double boxH) => math.max(22.0, boxH * 0.09);

/// 摇杆键（L3 / R3）直径。
double _rtVpadStickKeyD(double boxW, double boxH) =>
    math.min(boxW * 0.16, boxH * 0.20);

/// 面键出厂直径（模块盒内像素）。
double _rtVpadFaceD(double boxW, double faceH) =>
    math.min(boxW * 0.36, faceH * 0.34);

/// 键出厂尺寸（模块盒内像素）：面键 = 直径方形；肩键 = 行内等分 × 行高。
Size rtVpadDefaultKeySize(String key, Size box) {
  final w = box.width;
  final h = box.height;
  final shoulderH = _rtVpadShoulderH(h);
  const gap = 10.0;
  final faceH = math.max(0.0, h - shoulderH - gap - _rtVpadSystemH(h) - gap);
  if (_kShoulderKeys.contains(key)) {
    final keyW = (w * 0.82 - 3 * 7) / 4;
    return Size(keyW, shoulderH);
  }
  if (_kSystemKeys.contains(key)) {
    final sysW = w * 0.58;
    return Size((sysW - 2 * 6) / 3, _rtVpadSystemH(h));
  }
  if (_kStickKeys.contains(key)) {
    final d = _rtVpadStickKeyD(w, h);
    return Size(d, d);
  }
  final d = _rtVpadFaceD(w, faceH);
  return Size(d, d);
}

/// 键形态：face = ABXY 彩环圆键；shoulder = 肩键/扳机胶囊；system = 系统面键
/// 小胶囊；stick = 摇杆键小圆键。
String rtVpadKeyKind(String key) {
  if (_kFaceKeys.contains(key)) return 'face';
  if (_kShoulderKeys.contains(key)) return 'shoulder';
  if (_kSystemKeys.contains(key)) return 'system';
  if (_kStickKeys.contains(key)) return 'stick';
  return 'face';
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
  double? _scaleGrabX;

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

  void _startKeyDrag(String key, Offset global, Size box) {
    HapticFeedback.mediumImpact();
    final center = _effectiveCenter(key, box);
    // 抓取偏移 = 指针落点 - 键中心（模块盒内坐标，global 先转 local）。
    final pointer = _pointerOffset(global, box);
    setState(() {
      _dragGrabDelta = pointer - center;
      _previewCenters[key] = center;
    });
  }

  void _updateKeyDrag(String key, Offset global, Size box) {
    final grab = _dragGrabDelta;
    if (grab == null) return;
    setState(() {
      _previewCenters[key] = _clampCenter(
        key,
        _pointerOffset(global, box) - grab,
        box,
      );
    });
  }

  /// 指针位置 → 模块盒内坐标（global 先经本组件 RenderBox 转 local——
  /// 不用 delta 累加，快速一拖的第一个位移不会被手势识别器吞掉）。
  Offset _moduleLocal(Offset global, Size box) {
    final render = context.findRenderObject() as RenderBox?;
    if (render == null) return Offset.zero;
    return render.globalToLocal(global);
  }

  /// 指针相对模块盒圆心的偏移。
  Offset _pointerOffset(Offset global, Size box) {
    final center = Offset(box.width / 2, box.height / 2);
    return _moduleLocal(global, box) - center;
  }

  /// 指针是否落在本键的缩放拉手上（小键的拉手区会盖住键心——命中判别
  /// 错了会把「拖动」变成「缩放」）。
  bool _onGrip(Offset global, Size box, String key) {
    const grip = 20.0;
    final size = _keySize(key, box);
    final center = _effectiveCenter(key, box);
    final keyRect = Rect.fromCenter(
      center: center,
      width: size.width,
      height: size.height,
    );
    final gripRect = Rect.fromLTWH(
      keyRect.right - grip,
      keyRect.bottom - grip,
      grip,
      grip,
    );
    return gripRect.contains(_moduleLocal(global, box));
  }

  void _cancelKeyDrag(String key) {
    if (!_previewCenters.containsKey(key)) return;
    setState(() => _previewCenters.remove(key));
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

  void _startKeyScale(String key, Offset global) {
    HapticFeedback.mediumImpact();
    setState(() {
      _scaleGrabX = global.dx;
      _previewScales[key] = _effectiveScale(key);
    });
  }

  /// 缩放：按「当前 x − 起点 x」算倍率（绝对量，不靠 delta 累加——
  /// 第一个位移会被手势识别器吞掉）。
  void _updateKeyScale(String key, Offset global) {
    final startX = _scaleGrabX;
    if (startX == null || !_previewScales.containsKey(key)) return;
    setState(() {
      _previewScales[key] = (_previewScales[key]! + (global.dx - startX) / 160)
          .clamp(kRtCanvasBtnScaleMin, kRtCanvasBtnScaleMax)
          .toDouble();
    });
  }

  void _cancelKeyScale(String key) {
    if (!_previewScales.containsKey(key)) return;
    setState(() => _previewScales.remove(key));
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
    final kind = rtVpadKeyKind(key);
    final isTrigger = key == 'lt' || key == 'rt';
    // 键面标签：ABXY 单字母；系统面键用短名（BACK/START/GUIDE 太长，用
    // 缩写 B / S / G 会被误认，保留 3~5 字母小字）。
    final label = switch (kind) {
      'face' => key.toUpperCase(),
      'shoulder' => key.toUpperCase(),
      'system' => const {
        'back': 'BACK',
        'start': 'START',
        'guide': 'GUIDE',
      }[key]!,
      _ => key.toUpperCase(),
    };
    Widget keyWidget = _VpadHoldButton(
      label: label,
      enabled: widget.enabled,
      interactive: !widget.editMode,
      // 形态：面键/摇杆键 = 圆；肩键/系统面键 = 胶囊。
      round: kind == 'face' || kind == 'stick',
      diameter: kind == 'face' || kind == 'stick' ? size.width : null,
      faceColor: kind == 'face' ? _kFaceColors[key.toUpperCase()] : null,
      compact: kind == 'system' || kind == 'stick',
      onDown: () => _fire(
        button: isTrigger ? null : key,
        trigger: isTrigger ? key : null,
        pressed: true,
      ),
      onUp: () => _fire(
        button: isTrigger ? null : key,
        trigger: isTrigger ? key : null,
        pressed: false,
      ),
    );
    if (widget.editMode && widget.onKeyTransform != null) {
      // 裸 Listener 吃指针事件（不用 pan 识别器）：pan 要第二次 move 才
      // 回调 update，第一个位移会被吞——快速一拖键位不动。
      keyWidget = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          // 落在缩放拉手上 → 让位给拉手（否则小键的拉手区会吞掉拖动）。
          if (_onGrip(e.position, box, key)) return;
          _startKeyDrag(key, e.position, box);
        },
        onPointerMove: (e) => _updateKeyDrag(key, e.position, box),
        onPointerUp: (_) => _endKeyDrag(key, box),
        onPointerCancel: (_) => _cancelKeyDrag(key),
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
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _startKeyScale(key, e.position),
              onPointerMove: (e) => _updateKeyScale(key, e.position),
              onPointerUp: (_) => _endKeyScale(key, box),
              onPointerCancel: (_) => _cancelKeyScale(key),
              child: SizedBox(
                width: 20,
                height: 20,
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
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
    this.compact = false,
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

  /// 小号键（系统面键 / 摇杆键）：字号更小，容纳 BACK/START/GUIDE。
  final bool compact;
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
        fontSize: widget.compact ? 10 : (round ? 16 : 13),
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
