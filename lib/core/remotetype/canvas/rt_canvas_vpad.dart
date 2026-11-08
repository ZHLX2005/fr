// lib/core/remotetype/canvas/rt_canvas_vpad.dart
//
// 虚拟手柄键区（键级直编排，1.7.0 起不再有「手柄」模块盒）：
//   · 组件以 Positioned.fill 铺满画布，13 键直接以画布为参考系摆放——
//     LB/LT 贴左缘、RB/RT 贴右缘、BACK/START/GUIDE 居中偏上、ABXY 右上
//     菱形、L3 / R3 落双摇之间偏下（摇杆模块负责轴，本键负责下压）。
//   · 键显隐按组控制（编辑工具面板「手柄键区」区块：XYAB / 肩键扳机 /
//     系统键 / 摇杆键四组，组开关 = 批量翻键 v）；每键仍可独立拖动/缩放。
// 几何出厂位对齐 docs/prototypes/rt-gamepad-mode-dpad.html。
// 全部接 PC 端虚拟手柄（rust input-agent vpad_* 指令族）：
//   按下 = vpad_button true / vpad_trigger 1.0；松开 = false / 0.0。
// 按下/松开成对由本组件保证（Listener down/up/cancel + dispose 补发），
// PC 端串行链保序。
//
// 编辑态逐键编排：点下即选中并允许同手势拖动；松手无位移 = 只选中不落盘，
// 有位移 = 写回中心。选中键显示描边 + 缩放拉手。位置/尺寸持久化在布局
// vpad（键名 → RtVpadKeyState；x/y null = 出厂几何，拖/缩落定才写比例）。
// 编辑态 v=false 的键渲染幽灵轮廓，点击即开（显隐入口也在编辑面板键行）。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context/colors.dart';
import '../data/rt_prefs.dart'
    show
        RtVpadKeyState,
        kRtCanvasBtnScaleMax,
        kRtCanvasBtnScaleMin,
        rtVpadKeyOrder;

/// 触发回调：[button] ∈ a/b/x/y/lb/rb；[trigger] ∈ lt/rt。二者互斥非空；
/// [pressed] = 按下（true）/ 松开（false），每个键各回报一对。
typedef RtVpadKeyCallback =
    void Function({String? button, String? trigger, required bool pressed});

/// 编辑态逐键变换回报：[centerFraction] = 键中心在画布内的比例位（拖动
/// 落定；null = 位置保持出厂几何，仅缩放落定时出现）；[scale] = 键尺寸
/// 倍率（拉手落定）。调用方整条写该键的 RtVpadKeyState，免空维合并。
typedef RtVpadKeyTransformCallback =
    void Function(String key, Offset? centerFraction, double scale);

/// 手柄键组（编辑工具面板「手柄键区」区块的组行，组开关 = 批量翻组内键 v）。
class RtVpadKeyGroup {
  const RtVpadKeyGroup(this.name, this.keys);
  final String name;
  final List<String> keys;
}

/// 键分组：XYAB 面键 / 肩键扳机 / 系统面键 / 摇杆键（L3 R3）。
const List<RtVpadKeyGroup> rtVpadKeyGroups = [
  RtVpadKeyGroup('XYAB', ['a', 'b', 'x', 'y']),
  RtVpadKeyGroup('肩键扳机', ['lb', 'rb', 'lt', 'rt']),
  RtVpadKeyGroup('系统键', ['back', 'start', 'guide']),
  RtVpadKeyGroup('摇杆键', ['l3', 'r3']),
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

/// 面键出厂直径（模块盒内像素）：相对「右上菱形」参考盒。
double _rtVpadFaceD(double boxW, double boxH) {
  final faceSide = math.min(boxW * 0.18, boxH * 0.40);
  return faceSide * 0.32;
}

/// 摇杆键（L3 / R3）直径。
double _rtVpadStickKeyD(double boxW, double boxH) =>
    math.min(boxW * 0.055, boxH * 0.10);

/// 键出厂几何：键名 → 画布内中心（像素）。设置页 / 画布渲染 / 单测
/// 三处同源；几何对齐 docs/prototypes/rt-gamepad-mode-dpad.html。
/// [canvas] = 画布尺寸（键区铺满画布，无模块盒）。
Map<String, Offset> rtVpadDefaultSlots(Size canvas) {
  final w = canvas.width;
  final h = canvas.height;
  final d = _rtVpadFaceD(w, h);
  final arm = d * 0.88;
  const faceCx = 0.79;
  const faceCy = 0.45;
  return {
    // 左右侧缘竖排肩/扳。
    'lb': Offset(w * 0.048, h * 0.38),
    'lt': Offset(w * 0.048, h * 0.52),
    'rb': Offset(w * 0.952, h * 0.38),
    'rt': Offset(w * 0.952, h * 0.52),
    // 居中偏上系统键。
    'back': Offset(w * 0.445, h * 0.22),
    'guide': Offset(w * 0.50, h * 0.22),
    'start': Offset(w * 0.555, h * 0.22),
    // 右上 ABXY 菱形。
    'y': Offset(w * faceCx, h * faceCy - arm),
    'x': Offset(w * faceCx - arm, h * faceCy),
    'b': Offset(w * faceCx + arm, h * faceCy),
    'a': Offset(w * faceCx, h * faceCy + arm),
    // L3 / R3：双摇之间偏下，避开摇杆命中圆。
    'l3': Offset(w * 0.40, h * 0.80),
    'r3': Offset(w * 0.60, h * 0.80),
  };
}

/// 键出厂尺寸（画布内像素）。
Size rtVpadDefaultKeySize(String key, Size canvas) {
  final w = canvas.width;
  final h = canvas.height;
  if (_kShoulderKeys.contains(key)) {
    return Size(w * 0.05, h * 0.085);
  }
  if (_kSystemKeys.contains(key)) {
    final s = math.min(w * 0.038, h * 0.085);
    return Size(s, s);
  }
  if (_kStickKeys.contains(key)) {
    final d = _rtVpadStickKeyD(w, h);
    return Size(d, d);
  }
  final d = _rtVpadFaceD(w, h);
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
    this.keyStates = const {},
    this.editMode = false,
    this.onKeyTransform,
    this.onKeyToggleVisible,
    this.onKeyEditActive,
  });

  /// false（未连接）：置灰且不响应。
  final bool enabled;

  /// 按键事件（press 与 release 各回报一次）。
  final RtVpadKeyCallback onKey;

  /// 键名 → 编排态（显隐 + 比例位 + 倍率）。缺条目的键 = 出厂几何 + 可见。
  final Map<String, RtVpadKeyState> keyStates;

  /// 编辑态：键可拖动/缩放、v=false 键出幽灵可点开；按住不触发手柄事件。
  final bool editMode;

  /// 编辑态逐键变换落定（拖动松手 / 拉手松手各回报一次）。
  final RtVpadKeyTransformCallback? onKeyTransform;

  /// 编辑态幽灵键（v=false）点击开启。
  final ValueChanged<String>? onKeyToggleVisible;

  /// 逐键拖/缩进行中（true）/结束（false）。编辑态下提示外层有键在动
  /// （1.7.0 起外层无模块整搬，保留给上层屏蔽其它编辑手势）。
  final ValueChanged<bool>? onKeyEditActive;

  @override
  State<RtCanvasVpad> createState() => _RtCanvasVpadState();
}

class _RtCanvasVpadState extends State<RtCanvasVpad> {
  // 拖动/缩放的本地预览（松手一次性回写，所见即所得；与模块拖动同套路）。
  final Map<String, Offset> _previewCenters = {};
  final Map<String, double> _previewScales = {};
  Offset? _dragGrabDelta;
  Offset? _dragStartCenter;
  double? _scaleGrabX;
  double? _scaleAtStart;

  /// 编辑态当前选中键（null = 未选；拉手只挂在选中键上）。
  String? _selectedKey;

  /// 拖动判定：位移小于此值视为「只点选」，松手不落盘。
  static const double _kDragCommitPx = 6;

  @override
  void didUpdateWidget(covariant RtCanvasVpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.editMode && oldWidget.editMode) {
      _selectedKey = null;
      _previewCenters.clear();
      _previewScales.clear();
      _dragGrabDelta = null;
      _dragStartCenter = null;
      _scaleGrabX = null;
      _scaleAtStart = null;
      _setKeyEditActive(false);
    }
  }

  /// 键是否可见（使用态渲染判定；编辑态 v=false 出幽灵）。
  bool _keyOn(String key) => widget.keyStates[key]?.v ?? true;

  Offset _effectiveCenter(String key, Size canvas) {
    final preview = _previewCenters[key];
    if (preview != null) return preview;
    final state = widget.keyStates[key];
    if (state != null && state.hasPosition) {
      return Offset(state.x! * canvas.width, state.y! * canvas.height);
    }
    return rtVpadDefaultSlots(canvas)[key]!;
  }

  double _effectiveScale(String key) {
    final preview = _previewScales[key];
    if (preview != null) return preview;
    return widget.keyStates[key]?.s ?? 1.0;
  }

  Size _keySize(String key, Size canvas) {
    final base = rtVpadDefaultKeySize(key, canvas);
    final s = _effectiveScale(key);
    return Size(base.width * s, base.height * s);
  }

  /// 键中心钳回画布内（键完整在场）。
  Offset _clampCenter(String key, Offset center, Size canvas) {
    final size = _keySize(key, canvas);
    final cx = center.dx.clamp(
      size.width / 2,
      canvas.width < size.width ? size.width / 2 : canvas.width - size.width / 2,
    );
    final cy = center.dy.clamp(
      size.height / 2,
      canvas.height < size.height
          ? size.height / 2
          : canvas.height - size.height / 2,
    );
    return Offset(cx, cy);
  }

  void _fire({String? button, String? trigger, required bool pressed}) {
    widget.onKey(button: button, trigger: trigger, pressed: pressed);
  }

  // ---- 编辑态：逐键拖动 / 缩放 ----

  void _setKeyEditActive(bool active) {
    widget.onKeyEditActive?.call(active);
  }

  void _startKeyDrag(String key, Offset global, Size canvas) {
    final center = _effectiveCenter(key, canvas);
    // 抓取偏移 = 指针落点 - 键中心（均为画布内绝对坐标）。
    final pointer = _canvasLocal(global);
    _setKeyEditActive(true);
    setState(() {
      _dragGrabDelta = pointer - center;
      _dragStartCenter = center;
      _previewCenters[key] = center;
    });
  }

  void _updateKeyDrag(String key, Offset global, Size canvas) {
    final grab = _dragGrabDelta;
    if (grab == null) return;
    setState(() {
      _previewCenters[key] = _clampCenter(
        key,
        _canvasLocal(global) - grab,
        canvas,
      );
    });
  }

  /// 指针位置 → 画布内绝对坐标（global 先经本组件 RenderBox 转 local）。
  Offset _canvasLocal(Offset global) {
    final render = context.findRenderObject() as RenderBox?;
    if (render == null) return Offset.zero;
    return render.globalToLocal(global);
  }

  /// 键中心 → 画布归一化比例（0..1，钳回画布内）。[center] 由调用方给定
  /// （预览捕获位）——不走 [_effectiveCenter]，避免「预览已清、读回旧位」。
  Offset _centerFractionOf(Offset center, Size canvas) => Offset(
    (center.dx / canvas.width).clamp(0.0, 1.0).toDouble(),
    (center.dy / canvas.height).clamp(0.0, 1.0).toDouble(),
  );

  /// 键中心（当前有效位）→ 画布归一化比例（缩放落定等不动位场景用）。
  Offset _centerFraction(String key, Size canvas) => _centerFractionOf(
    _clampCenter(key, _effectiveCenter(key, canvas), canvas),
    canvas,
  );

  /// 指针是否落在本键的缩放拉手上（小键的拉手区会盖住键心——命中判别
  /// 错了会把「拖动」变成「缩放」）。
  bool _onGrip(Offset global, Size canvas, String key) {
    const grip = 20.0;
    final size = _keySize(key, canvas);
    final center = _effectiveCenter(key, canvas);
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
    return gripRect.contains(_canvasLocal(global));
  }

  void _cancelKeyDrag(String key) {
    if (!_previewCenters.containsKey(key)) return;
    setState(() {
      _previewCenters.remove(key);
      _dragGrabDelta = null;
      _dragStartCenter = null;
    });
    _setKeyEditActive(false);
  }

  void _endKeyDrag(String key, Size canvas) {
    final center = _previewCenters[key];
    final start = _dragStartCenter;
    if (center == null) return;
    setState(() {
      _previewCenters.remove(key);
      _dragGrabDelta = null;
      _dragStartCenter = null;
    });
    _setKeyEditActive(false);
    // 位移太小 = 纯点选，不落盘（避免「点一下就写 vpad」）。
    if (start != null && (center - start).distance < _kDragCommitPx) {
      return;
    }
    widget.onKeyTransform?.call(
      key,
      _centerFractionOf(center, canvas),
      _effectiveScale(key),
    );
    unawaited(HapticFeedback.selectionClick());
  }

  void _startKeyScale(String key, Offset global) {
    unawaited(HapticFeedback.mediumImpact());
    _setKeyEditActive(true);
    setState(() {
      _scaleGrabX = global.dx;
      _scaleAtStart = _effectiveScale(key);
      _previewScales[key] = _scaleAtStart!;
    });
  }

  /// 缩放：起点倍率 + (当前 x − 起点 x)/160（绝对量，不累加每帧）。
  void _updateKeyScale(String key, Offset global) {
    final startX = _scaleGrabX;
    final base = _scaleAtStart;
    if (startX == null || base == null) return;
    setState(() {
      _previewScales[key] = (base + (global.dx - startX) / 160)
          .clamp(kRtCanvasBtnScaleMin, kRtCanvasBtnScaleMax)
          .toDouble();
    });
  }

  void _cancelKeyScale(String key) {
    if (!_previewScales.containsKey(key)) return;
    setState(() {
      _previewScales.remove(key);
      _scaleGrabX = null;
      _scaleAtStart = null;
    });
    _setKeyEditActive(false);
  }

  void _endKeyScale(String key, Size canvas) {
    final scale = _previewScales[key];
    if (scale == null) return;
    setState(() {
      _previewScales.remove(key);
      _scaleGrabX = null;
      _scaleAtStart = null;
    });
    _setKeyEditActive(false);
    // 缩放不动位置：键还在出厂几何（无显式位）→ centerFraction 传 null，
    // 位置保持出厂（随画布尺寸自适应）；有显式位才随写比例位。
    final hasPosition = widget.keyStates[key]?.hasPosition ?? false;
    widget.onKeyTransform?.call(
      key,
      hasPosition ? _centerFraction(key, canvas) : null,
      scale,
    );
    unawaited(HapticFeedback.selectionClick());
  }

  @override
  void dispose() {
    // 拖/缩中途卸载：松开编辑占用，避免 onKeyEditActive 卡死。
    _setKeyEditActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvas = constraints.biggest;
        // 使用态只渲染 v=true 的键；编辑态全渲染（v=false 出幽灵可点开）。
        final keys = [
          for (final key in rtVpadKeyOrder)
            if (widget.editMode || _keyOn(key)) key,
        ];
        // 不在外层挂 GestureDetector.onTap 取消选中：Listener 不占手势竞技场，
        // 点键后父级 onTap 仍会赢 → 选中立刻被清掉。改选 = 点另一键；
        // 再点已选中键 = 直接开拖/缩（无中途取消选中，退出编辑态才复位）。
        return Stack(
          clipBehavior: Clip.none,
          children: [for (final key in keys) _buildKey(key, canvas)],
        );
      },
    );
  }

  Widget _buildKey(String key, Size canvas) {
    final state = widget.keyStates[key];
    final ghost = widget.editMode && !(state?.v ?? true);
    if (ghost) return _buildGhostKey(key, canvas);
    final center = _clampCenter(key, _effectiveCenter(key, canvas), canvas);
    final size = _keySize(key, canvas);
    final kind = rtVpadKeyKind(key);
    final isTrigger = key == 'lt' || key == 'rt';
    final selected = widget.editMode && _selectedKey == key;
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
      selected: selected,
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
      // 点下选中并可同势拖动。裸 Listener 吃指针（不用 pan：首位移会被吞）。
      keyWidget = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          // 点下即选中；同手势可拖。拉手命中留给缩放 Listener。
          final wasSelected = _selectedKey == key;
          if (!wasSelected) {
            setState(() => _selectedKey = key);
            unawaited(HapticFeedback.selectionClick());
          }
          // 拉手只挂在「已选中」的键上（且作为 Stack 顶层 Listener 抢先
          // 命中，按下压根到不了这里）——未选中键的右下角不该被当拉手，
          // 否则首次从角上拖动整段无效。
          if (wasSelected && _onGrip(e.position, canvas, key)) return;
          _startKeyDrag(key, e.position, canvas);
        },
        onPointerMove: (e) {
          if (_selectedKey != key || !_previewCenters.containsKey(key)) {
            return;
          }
          _updateKeyDrag(key, e.position, canvas);
        },
        onPointerUp: (_) {
          if (_selectedKey != key) return;
          if (_previewCenters.containsKey(key)) _endKeyDrag(key, canvas);
        },
        onPointerCancel: (_) {
          if (_selectedKey != key) return;
          _cancelKeyDrag(key);
        },
        child: keyWidget,
      );
      // 缩放拉手仅选中键显示。
      if (selected) {
        keyWidget = Stack(
          clipBehavior: Clip.none,
          children: [
            keyWidget,
            Positioned(
              right: -2,
              bottom: -2,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _startKeyScale(key, e.position),
                onPointerMove: (e) => _updateKeyScale(key, e.position),
                onPointerUp: (_) => _endKeyScale(key, canvas),
                onPointerCancel: (_) => _cancelKeyScale(key),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: Center(
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: context.colors.scheme.primary.withValues(
                          alpha: 0.95,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.colors.scheme.surface,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.scheme.primary
                                .withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
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
    }
    return Positioned(
      left: center.dx - size.width / 2,
      top: center.dy - size.height / 2,
      width: size.width,
      height: size.height,
      child: keyWidget,
    );
  }

  /// 编辑态幽灵键（v=false）：半透明轮廓 + 键名 + 关闭角标，点击即开。
  /// 位置/尺寸与正常键同源（条目位或出厂几何），让「这里有个关掉的键」
  /// 在画布上直接可见——显隐入口的另一端（编辑面板键行）之外的手感入口。
  Widget _buildGhostKey(String key, Size canvas) {
    final c = context.colors;
    final cs = c.scheme;
    final center = _clampCenter(key, _effectiveCenter(key, canvas), canvas);
    final size = _keySize(key, canvas);
    final kind = rtVpadKeyKind(key);
    final round = kind == 'face' || kind == 'stick';
    return Positioned(
      left: center.dx - size.width / 2,
      top: center.dy - size.height / 2,
      width: size.width,
      height: size.height,
      child: GestureDetector(
        key: ValueKey('vpad-ghost:$key'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.onKeyToggleVisible?.call(key);
          unawaited(HapticFeedback.selectionClick());
        },
        child: Container(
          decoration: BoxDecoration(
            shape: round ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: round ? null : BorderRadius.circular(999),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.55),
              width: 1.2,
            ),
            color: cs.surface.withValues(alpha: 0.35),
          ),
          alignment: Alignment.center,
          child: Text(
            rtVpadKeyLabel(key),
            maxLines: 1,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: c.textMuted.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
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
    this.selected = false,
  });

  final String label;
  final bool enabled;

  /// false（编辑态）：置灰之外的按压完全关断（拖动编排期间不发事件）。
  final bool interactive;

  /// 编辑态选中：主色描边 + 轻辉光，标识当前精细调整目标。
  final bool selected;

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

    final borderColor = _held
        ? accent
        : widget.selected
            ? cs.primary
            : (face ?? cs.outlineVariant.withValues(alpha: 0.7));
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
        color: borderColor,
        width: _held || widget.selected ? 2.4 : (face != null ? 2 : 1.2),
      ),
      boxShadow: [
        BoxShadow(
          color: _held
              ? accent.withValues(alpha: face != null ? 0.50 : 0.40)
              : widget.selected
                  ? cs.primary.withValues(alpha: 0.35)
                  : cs.shadow.withValues(alpha: 0.10),
          blurRadius: _held ? 18 : (widget.selected ? 14 : 6),
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
