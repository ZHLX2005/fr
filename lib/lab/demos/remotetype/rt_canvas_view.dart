// lib/lab/demos/remotetype/rt_canvas_view.dart
//
// 横屏画布：触摸板 / 输入框 / 快捷按钮是同一模块系统的三类模块，整个横屏
// 自由编排。形态源自「游戏手柄」（左手触摸区、右手按钮区），但布局不封死
// ——编辑模式下模块与按钮都能拖动摆位、调整大小，触摸板/输入框/每个按钮
// 都能开关显隐。
//
// 两态（边界刻意做得明显）：
//   use（使用态）—— 触摸板吃手势、输入框打字、按钮点按触发 + 长按拖动；
//                   顶部浮层 = 连接点 · 灵敏度 · 进入编辑 · 退出。
//   edit（编辑态）—— 画布主色描边框 + 底部显隐面板 + 右下角完成钮（刻意
//                   不设顶部横幅：横屏每寸都是操作面，浮条压视野），所有
//                   使用类手势停用。拖动=移位、拉手=缩放、点按按钮=显隐
//                   （隐藏者以幽灵呈现可点回）。退出经完成钮或系统返回
//                   （页面层 PopScope 先退编辑再退画布）。
//
// 职责切分：快捷键「有哪些」归打字页编辑器（rt_shortcut_bar 的列表编辑），
// 「显示哪些」归画布（RtCanvasButtonPos.v）——定义与编排两层分离。
//
// 布局持久化：RtCanvasLayout（模块锚点含宽高 + 按钮位含倍率/显隐），拖动
// 期间本地预览、松手一次性回写（页面层落盘）。坐标全部归一化。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context/colors.dart';
import 'rt_canvas_button.dart' show RtCanvasButton, RtCanvasGripDot;
import 'rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasButtonPos,
        RtCanvasLayout,
        RtShortcutItem;
import 'rt_session.dart';
import 'rt_touch_surface.dart'
    show RtConnDot, RtPadChipButton, RtTouchSurface, showRtSensitivitySheet;

/// 按钮自动找位候选槽（画布右侧区，2 列 × 4 行，归一化画布坐标）。
/// 公开给单测对齐规则。
const List<Offset> kRtCanvasSlotAnchors = [
  Offset(0.60, 0.34), Offset(0.86, 0.34),
  Offset(0.60, 0.54), Offset(0.86, 0.54),
  Offset(0.60, 0.74), Offset(0.86, 0.74),
  Offset(0.60, 0.92), Offset(0.86, 0.92),
];

/// 摆位自动找位：候选槽里第一个与已摆按钮都拉开距离的空位；全满落右侧
/// 中心。顶层纯函数（无 widget 依赖），规则改动必须同步单测
/// （test/lab/demos/remotetype/rt_canvas_layout_test.dart）。
Offset rtFirstFreeCanvasSlot(Set<Offset> placed) {
  for (final candidate in kRtCanvasSlotAnchors) {
    final taken = placed.any((p) => (p - candidate).distance < 0.18);
    if (!taken) return candidate;
  }
  return const Offset(0.73, 0.55);
}

/// 模块 id（布局持久化的键，禁止改动——改了等于丢用户布局）。
const String kRtCanvasModuleTouchpad = 'touchpad';
const String kRtCanvasModuleInput = 'input';

class RtCanvasView extends StatefulWidget {
  const RtCanvasView({
    super.key,
    required this.session,
    required this.connected,
    required this.sensitivity,
    required this.onSensitivityChanged,
    required this.textController,
    required this.shortcuts,
    required this.firingId,
    required this.layout,
    required this.editMode,
    required this.onEditModeChanged,
    required this.onLayoutChanged,
    required this.onFire,
    required this.onEditShortcuts,
    required this.onExit,
    required this.onNotify,
  });

  /// 活会话（页面层保证仅在已连接状态下进入本页；重连期间短暂为旧会话，
  /// RtTouchSurface 对死 socket 发送安全）。
  final RtSession? session;
  final bool connected;
  final double sensitivity;
  final ValueChanged<double> onSensitivityChanged;

  /// 输入框模块与打字页共用同一 controller（同步管线挂在 controller 上，
  /// 两处输入天然同源）。
  final TextEditingController textController;
  final List<RtShortcutItem> shortcuts;

  /// 正在连发的快捷键 id（页面层防重入，按钮据此高亮）。
  final String? firingId;

  /// 已保存的画布布局（模块锚点 + 按钮位）。
  final RtCanvasLayout layout;
  final bool editMode;
  final ValueChanged<bool> onEditModeChanged;

  /// 摆位 / 缩放 / 显隐回写（页面层持久化）。
  final ValueChanged<RtCanvasLayout> onLayoutChanged;
  final ValueChanged<RtShortcutItem> onFire;
  final VoidCallback onEditShortcuts;
  final VoidCallback onExit;
  final void Function(String message) onNotify;

  @override
  State<RtCanvasView> createState() => _RtCanvasViewState();
}

class _RtCanvasViewState extends State<RtCanvasView> {
  // 模块默认规格（布局数据缺条目时兜底）：触摸板居左偏大、输入框右上横条。
  static const double _padDefW = 0.54, _padDefH = 0.84;
  static const double _inputDefW = 0.46, _inputDefH = 0.18;

  // 模块尺寸范围（wMin, wMax, hMin, hMax，归一化）。
  static (double, double, double, double) _moduleRange(String id) =>
      id == kRtCanvasModuleTouchpad
          ? (0.25, 1.0, 0.35, 1.0)
          : (0.20, 1.0, 0.08, 0.40);

  // 输入框像素高度硬钳（fraction 随画布高浮动，太扁/太高都不成框）。
  static const double _inputHMinPx = 44, _inputHMaxPx = 180;

  final GlobalKey _canvasKey = GlobalKey();

  // 移动预览：模块/按钮 id → 当前归一化中心。松手一次性回写。
  String? _dragId;
  Offset? _dragPos;

  // 模块缩放预览：id + 实时宽高（归一化）。
  String? _resizeModuleId;
  double _liveW = 0;
  double _liveH = 0;

  // ================= 布局解析 =================

  /// 内置默认锚点（布局数据缺条目时兜底）——首跑即接近旧手柄形态。
  static RtCanvasAnchor _defaultAnchor(String id) {
    if (id == kRtCanvasModuleTouchpad) {
      return const RtCanvasAnchor(
        visible: true,
        x: 0.27,
        y: 0.55,
        w: _padDefW,
        h: _padDefH,
      );
    }
    return const RtCanvasAnchor(
      visible: true,
      x: 0.73,
      y: 0.16,
      w: _inputDefW,
      h: _inputDefH,
    );
  }

  RtCanvasAnchor _anchorOf(String id) =>
      widget.layout.modules[id] ?? _defaultAnchor(id);

  Offset _anchorPos(String id) {
    if (_dragId == id && _dragPos != null) return _dragPos!;
    final a = _anchorOf(id);
    return Offset(a.x, a.y);
  }

  /// 模块实时宽高（缩放预览优先，否则锚点值，缺省回默认）。
  (double, double) _moduleFractions(String id) {
    if (_resizeModuleId == id) return (_liveW, _liveH);
    final a = _anchorOf(id);
    final def = _defaultAnchor(id);
    return (a.w ?? def.w!, a.h ?? def.h!);
  }

  /// 全局坐标 → 画布归一化坐标。画布异常小（尺寸 ≤ 0）时 0/0 = NaN 会
  /// 一路漏进 Positioned 撑爆布局，落中心兜底。
  Offset _toCanvasNormalized(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return const Offset(0.5, 0.5);
    final size = box.size;
    if (size.width <= 0 || size.height <= 0) return const Offset(0.5, 0.5);
    final local = box.globalToLocal(global);
    double clamp01(double v) => v.clamp(0.0, 1.0).toDouble();
    return Offset(
        clamp01(local.dx / size.width), clamp01(local.dy / size.height));
  }

  // ================= 回写 =================

  void _commitModuleDrag() {
    final id = _dragId;
    final settled = _dragPos;
    setState(() {
      _dragId = null;
      _dragPos = null;
    });
    if (id == null || settled == null) return;
    if (id != kRtCanvasModuleTouchpad && id != kRtCanvasModuleInput) return;
    final cur = _anchorOf(id);
    // 空拖（点按没动）不回写：省一次无谓落盘。
    if ((settled - Offset(cur.x, cur.y)).distance <= 1e-6) return;
    widget.onLayoutChanged(
      widget.layout.withModule(
        id,
        RtCanvasAnchor(
          visible: cur.visible,
          x: settled.dx.clamp(0.0, 1.0).toDouble(),
          y: settled.dy.clamp(0.0, 1.0).toDouble(),
          w: cur.w,
          h: cur.h,
        ),
      ),
    );
    unawaited(HapticFeedback.selectionClick());
  }

  void _commitModuleResize() {
    final id = _resizeModuleId;
    final wf = _liveW;
    final hf = _liveH;
    setState(() => _resizeModuleId = null);
    if (id == null) return;
    final cur = _anchorOf(id);
    final def = _defaultAnchor(id);
    // 空拖（碰拉手没动）不回写。
    if ((wf - (cur.w ?? def.w!)).abs() <= 1e-6 &&
        (hf - (cur.h ?? def.h!)).abs() <= 1e-6) {
      return;
    }
    widget.onLayoutChanged(
      widget.layout.withModule(
        id,
        RtCanvasAnchor(visible: cur.visible, x: cur.x, y: cur.y, w: wf, h: hf),
      ),
    );
    unawaited(HapticFeedback.selectionClick());
  }

  void _updateButton(String id, RtCanvasButtonPos pos) {
    widget.onLayoutChanged(widget.layout.withButton(id, pos));
  }

  void _toggleModuleVisible(String id) {
    final cur = _anchorOf(id);
    widget.onLayoutChanged(
      widget.layout.withModule(
        id,
        RtCanvasAnchor(
          visible: !cur.visible,
          x: cur.x,
          y: cur.y,
          w: cur.w,
          h: cur.h,
        ),
      ),
    );
    unawaited(HapticFeedback.selectionClick());
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerHighest,
      body: Stack(
        key: _canvasKey,
        clipBehavior: Clip.none,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final canvasSize = constraints.biggest;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  if (_anchorOf(kRtCanvasModuleTouchpad).visible)
                    _touchpadModule(canvasSize),
                  if (_anchorOf(kRtCanvasModuleInput).visible)
                    _inputModule(canvasSize),
                  ..._buttonModules(canvasSize),
                ],
              );
            },
          ),
          // 顶层：use 态浮层 / edit 态横幅 + 显隐面板（互斥，边界一眼可辨）
          if (widget.editMode) ..._editChrome(cs) else _useOverlay(cs),
        ],
      ),
    );
  }

  // ---- 使用态浮层 ----

  Widget _useOverlay(ColorScheme cs) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Row(
          children: [
            RtConnDot(connected: widget.connected, cs: cs),
            const Spacer(),
            RtPadChipButton(
              icon: Icons.tune,
              tooltip: '触摸板灵敏度',
              onTap: () => showRtSensitivitySheet(
                context,
                value: widget.sensitivity,
                onChanged: widget.onSensitivityChanged,
              ),
            ),
            const SizedBox(width: 8),
            RtPadChipButton(
              icon: Icons.edit,
              tooltip: '编辑布局',
              onTap: () => widget.onEditModeChanged(true),
            ),
            const SizedBox(width: 8),
            RtPadChipButton(
              icon: Icons.keyboard,
              tooltip: '返回打字',
              onTap: widget.onExit,
            ),
          ],
        ),
      ),
    );
  }

  // ---- 编辑态 chrome：横幅 + 底部显隐面板 + 画布描边 ----

  List<Widget> _editChrome(ColorScheme cs) {
    return [
      // 画布主色描边：编辑态的「场」边界
      Positioned.fill(
        child: IgnorePointer(
          child: Container(
            foregroundDecoration: BoxDecoration(
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.55),
                width: 2,
              ),
            ),
          ),
        ),
      ),
      // 右下角完成钮：编辑态唯一常驻出口（不设顶部横幅，横屏视野优先；
      // 拖动/缩放/显隐操作靠模块自身的编辑框与幽灵态自解释）。实心主色
      // 与左侧半透明芯片拉开层级——它是这态里唯一的「离开」动作。
      Align(
        alignment: Alignment.bottomRight,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 16, 12),
            child: FilledButton.icon(
              onPressed: () => widget.onEditModeChanged(false),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('完成'),
            ),
          ),
        ),
      ),
      // 底部显隐面板：模块开关 + 快捷键增删入口
      Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _moduleVisibilityChip(
                  icon: Icons.mouse_outlined,
                  label: '触摸板',
                  id: kRtCanvasModuleTouchpad,
                ),
                _moduleVisibilityChip(
                  icon: Icons.keyboard_alt_outlined,
                  label: '输入框',
                  id: kRtCanvasModuleInput,
                ),
                ActionChip(
                  avatar: Icon(Icons.playlist_add,
                      size: 18, color: cs.onSurfaceVariant),
                  label: const Text('编辑快捷键'),
                  onPressed: widget.onEditShortcuts,
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _moduleVisibilityChip({
    required IconData icon,
    required String label,
    required String id,
  }) {
    final cs = context.colors.scheme;
    final visible = _anchorOf(id).visible;
    return FilterChip(
      selected: visible,
      onSelected: (_) => _toggleModuleVisible(id),
      avatar: Icon(
        visible ? Icons.visibility : Icons.visibility_off,
        size: 18,
        color: visible ? cs.primary : cs.onSurfaceVariant,
      ),
      label: Text(label),
    );
  }

  // ---- 模块通用：尺寸解析与编辑态包装 ----

  /// 模块像素尺寸（缩放预览优先；输入框高度另有像素硬钳）。
  Size _moduleSizePx(String id, Size canvasSize) {
    final (wf, hf) = _moduleFractions(id);
    double w = wf * canvasSize.width;
    double h = hf * canvasSize.height;
    if (id == kRtCanvasModuleInput) {
      h = h.clamp(_inputHMinPx, _inputHMaxPx).toDouble();
    }
    return Size(w, h);
  }

  /// 编辑态模块包装：直拖移位（pan）+ 右下角拉手缩放。
  Widget _editModuleWrapper({
    required String id,
    required String label,
    required Widget child,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            HapticFeedback.mediumImpact();
            setState(() {
              _dragId = id;
              _dragPos = _anchorPos(id);
            });
          },
          onPanUpdate: (d) {
            // 双指各拖一个模块时只跟自己的 id——共享预览字段没守卫会把
            // 两个模块拽成同步移动。
            if (_dragId != id || _dragPos == null) return;
            final box =
                _canvasKey.currentContext?.findRenderObject() as RenderBox?;
            if (box == null) return;
            setState(() {
              _dragPos = Offset(
                _dragPos!.dx + d.delta.dx / box.size.width,
                _dragPos!.dy + d.delta.dy / box.size.height,
              );
            });
          },
          // end/cancel 同样认 id：预览被后落指覆盖时，先落指的抬手是空操作。
          onPanEnd: (_) {
            if (_dragId == id) _commitModuleDrag();
          },
          onPanCancel: () {
            if (_dragId == id) {
              setState(() {
                _dragId = null;
                _dragPos = null;
              });
            }
          },
          // 模块本体停用（触摸板手势/输入框键盘），只留移位 pan。
          child: IgnorePointer(child: _editFrame(child, label)),
        ),
        // 右下缩放拉手：前置于模块之上，命中优先于移位 pan。
        Positioned(
          right: 2,
          bottom: 2,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              HapticFeedback.mediumImpact();
              final (wf, hf) = _moduleFractions(id);
              setState(() {
                _resizeModuleId = id;
                _liveW = wf;
                _liveH = hf;
              });
            },
            onPanUpdate: (d) {
              if (_resizeModuleId != id) return;
              final box =
                  _canvasKey.currentContext?.findRenderObject() as RenderBox?;
              if (box == null || box.size.width <= 0 || box.size.height <= 0) {
                return;
              }
              final (wMin, wMax, hMin, hMax) = _moduleRange(id);
              setState(() {
                _liveW = (_liveW + d.delta.dx / box.size.width)
                    .clamp(wMin, wMax)
                    .toDouble();
                _liveH = (_liveH + d.delta.dy / box.size.height)
                    .clamp(hMin, hMax)
                    .toDouble();
              });
            },
            onPanEnd: (_) {
              if (_resizeModuleId == id) _commitModuleResize();
            },
            onPanCancel: () {
              if (_resizeModuleId == id) {
                setState(() => _resizeModuleId = null);
              }
            },
            child: RtCanvasGripDot(cs: context.colors.scheme),
          ),
        ),
      ],
    );
  }

  /// 编辑态模块外框：主色描边 + 名称签（边界一眼可辨）。
  Widget _editFrame(Widget child, String label) {
    final cs = context.colors.scheme;
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.75),
          width: 1.6,
        ),
      ),
      child: Stack(
        children: [
          child,
          Positioned(
            left: 8,
            top: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.drag_indicator,
                    size: 14, color: cs.primary.withValues(alpha: 0.9)),
                const SizedBox(width: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: cs.primary.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 归一化中心 + 像素规格 → 像素矩形（夹回画布内）。
  ({double left, double top}) _moduleRect(
    Offset pos,
    Size moduleSize,
    Size canvasSize,
  ) {
    final cx = (pos.dx * canvasSize.width).clamp(
      moduleSize.width / 2,
      canvasSize.width < moduleSize.width
          ? moduleSize.width / 2
          : canvasSize.width - moduleSize.width / 2,
    );
    final cy = (pos.dy * canvasSize.height).clamp(
      moduleSize.height / 2,
      canvasSize.height < moduleSize.height
          ? moduleSize.height / 2
          : canvasSize.height - moduleSize.height / 2,
    );
    return (left: cx - moduleSize.width / 2, top: cy - moduleSize.height / 2);
  }

  // ---- 模块：触摸板 ----

  Widget _touchpadModule(Size canvasSize) {
    final size = _moduleSizePx(kRtCanvasModuleTouchpad, canvasSize);
    final rect = _moduleRect(
      _anchorPos(kRtCanvasModuleTouchpad),
      size,
      canvasSize,
    );
    Widget pad = RtTouchSurface(
      session: widget.session,
      connected: widget.connected,
      sensitivity: widget.sensitivity,
      onNotify: widget.onNotify,
      // 编辑态不展示手势图例（图例讲的是使用态手势）。
      showLegend: !widget.editMode,
    );
    if (widget.editMode) {
      pad = _editModuleWrapper(
        id: kRtCanvasModuleTouchpad,
        label: '触摸板',
        child: SizedBox(width: size.width, height: size.height, child: pad),
      );
    }
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: size.width,
      height: size.height,
      child: pad,
    );
  }

  // ---- 模块：输入框 ----

  Widget _inputModule(Size canvasSize) {
    final size = _moduleSizePx(kRtCanvasModuleInput, canvasSize);
    final rect = _moduleRect(_anchorPos(kRtCanvasModuleInput), size, canvasSize);
    final cs = context.colors.scheme;
    Widget box = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: widget.textController,
              style: const TextStyle(fontSize: 14),
              decoration: const InputDecoration(
                hintText: '输入同步到电脑…',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.backspace_outlined, size: 18),
            tooltip: '清空',
            onPressed: () {
              widget.textController.clear();
              unawaited(HapticFeedback.selectionClick());
            },
          ),
        ],
      ),
    );
    if (widget.editMode) {
      // 编辑态：输入框停用（不弹键盘），只留移位/缩放。
      box = _editModuleWrapper(
        id: kRtCanvasModuleInput,
        label: '输入框',
        child: SizedBox(width: size.width, height: size.height, child: box),
      );
    }
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: size.width,
      height: size.height,
      child: box,
    );
  }

  // ---- 模块：快捷按钮 ----

  List<Widget> _buttonModules(Size canvasSize) {
    // 摆位解析：已存的直接用；没存过的按候选槽找空位（本次 build 内
    // 顺次占位，保证多个新按钮互不重叠、且重建结果稳定）。
    final assigned = <String, Offset>{
      for (final e in widget.layout.buttons.entries)
        e.key: Offset(e.value.x, e.value.y),
    };
    final resolved = <String, Offset>{};
    for (final item in widget.shortcuts) {
      final saved = assigned[item.id];
      if (saved != null) {
        resolved[item.id] = saved;
        continue;
      }
      final slot = rtFirstFreeCanvasSlot(assigned.values.toSet());
      assigned[item.id] = slot;
      resolved[item.id] = slot;
    }

    final out = <Widget>[];
    for (final item in widget.shortcuts) {
      final center = resolved[item.id]!;
      final pos = widget.layout.buttons[item.id] ??
          RtCanvasButtonPos(x: center.dx, y: center.dy);
      // 使用态隐藏按钮不渲染；编辑态以幽灵呈现（可点回）。
      if (!widget.editMode && !pos.v) continue;
      out.add(
        RtCanvasButton(
          item: item,
          pos: pos,
          canvasSize: canvasSize,
          connected: widget.connected,
          busy: widget.firingId == item.id,
          editMode: widget.editMode,
          toCanvasNormalized: _toCanvasNormalized,
          onTransform: (c, sc) => _updateButton(
            item.id,
            pos.copyWith(
              x: c?.dx.clamp(0.0, 1.0).toDouble(),
              y: c?.dy.clamp(0.0, 1.0).toDouble(),
              s: sc,
            ),
          ),
          onToggleVisible: () =>
              _updateButton(item.id, pos.copyWith(v: !pos.v)),
          onFire: widget.onFire,
        ),
      );
    }
    return out;
  }
}
