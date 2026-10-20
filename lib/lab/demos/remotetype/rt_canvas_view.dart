// lib/lab/demos/remotetype/rt_canvas_view.dart
//
// 横屏画布：触摸板 / 输入框 / 快捷按钮是同一模块系统的三类模块，整个横屏
// 自由编排。当前编排属于「激活的布局」—— 用户可在编辑态从底部「布局」入口
// 切换 / 复制 / 重命名自定义 / 内置恢复出厂 / 删除（详见 rt_canvas_presets +
// rt_canvas_layouts_sheet；sheet 渲染持久化版本，缩略图即各布局真实样子）。
//
// 两态（边界刻意做得明显）：
//   use（使用态）—— 触摸板吃手势、输入框打字、按钮点按触发 + 长按拖动；
//                   顶部浮层 = 连接点 · 灵敏度 · 切换布局 · 进入编辑 · 退出。
//   edit（编辑态）—— 画布主色描边框 + 底部显隐面板 + 右下角完成钮，所有使用类
//                   手势停用。拖动=移位、右下角拉手=缩放、点按按钮=显隐
//                   （隐藏者以幽灵呈现可点回）。切布局会自动清掉拖动预览
//                   （避免旧布局预览值瞬移到新布局）。
//
// 职责切分：快捷键「有哪些」归打字页编辑器（rt_shortcut_bar 的列表编辑），
// 「显示哪些」归画布（RtCanvasButtonPos.v）。布局集合「用哪一套」归画布
// sheet（RtCanvasLayouts）。两层职责相互独立。

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context/colors.dart';
import 'rt_canvas_button.dart' show RtCanvasButton, RtCanvasGripDot;
import 'rt_canvas_dpad.dart' show RtCanvasDpad;
import 'rt_canvas_layouts_sheet.dart' show RtCanvasLayoutsSheet;
import 'rt_canvas_vpad.dart' show RtCanvasVpad;
import 'rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasButtonPos,
        RtCanvasLayout,
        RtCanvasLayouts,
        RtShortcutItem,
        kRtCanvasInputDefH,
        kRtCanvasInputDefW,
        kRtCanvasModuleDpad,
        kRtCanvasModuleInput,
        kRtCanvasModuleTouchpad,
        kRtCanvasModuleVpad,
        kRtCanvasPadDefH,
        kRtCanvasPadDefW;
import 'rt_session.dart';
import 'rt_touch_surface.dart'
    show RtConnDot, RtPadChipButton, RtTouchSurface, showRtSensitivitySheet;

/// 按钮自动找位候选槽（画布右侧区，2 列 × 4 行，归一化画布坐标）。
const List<Offset> kRtCanvasSlotAnchors = [
  Offset(0.60, 0.34),
  Offset(0.86, 0.34),
  Offset(0.60, 0.54),
  Offset(0.86, 0.54),
  Offset(0.60, 0.74),
  Offset(0.86, 0.74),
  Offset(0.60, 0.92),
  Offset(0.86, 0.92),
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
    required this.activeLayout,
    required this.activeId,
    required this.layouts,
    required this.editMode,
    required this.onLayoutChanged,
    required this.onSwitchLayout,
    required this.onCopyToCustom,
    required this.onDeleteCustom,
    required this.onRenameCustom,
    required this.onResetBuiltin,
    required this.onDirection,
    required this.onVpadKey,
    required this.onEditModeChanged,
    required this.onFire,
    required this.onEditShortcuts,
    required this.onExit,
    required this.onNotify,
  });

  final RtSession? session;
  final bool connected;
  final double sensitivity;
  final ValueChanged<double> onSensitivityChanged;

  final TextEditingController textController;
  final List<RtShortcutItem> shortcuts;
  final String? firingId;

  /// 当前激活布局的数据（页面层随 activeId 变化而切到新数据）。
  final RtCanvasLayout activeLayout;

  /// 当前激活布局的 id。仅用于 sheet 高亮与「切布局」时识别——画布渲染
  /// 只看 activeLayout。
  final String activeId;

  /// 全部布局（内置 + 自定义），仅 sheet 用。
  final RtCanvasLayouts layouts;
  final bool editMode;

  /// 当前激活布局的内容变更（拖动 / 缩放 / 显隐 / 模块开关）。
  final ValueChanged<RtCanvasLayout> onLayoutChanged;

  /// 切换激活布局。
  final ValueChanged<String> onSwitchLayout;

  /// 「复制当前为新自定义」—— sheet footer 触发。
  final VoidCallback onCopyToCustom;

  /// 删除某条自定义布局（仅自定义，长按 sheet 列表项触发）。
  final ValueChanged<String> onDeleteCustom;

  /// 重命名自定义布局（sheet 长按菜单触发）。
  final void Function(String id, String name) onRenameCustom;

  /// 内置布局恢复出厂摆放（sheet 内置长按触发）。
  final ValueChanged<String> onResetBuiltin;

  /// 方向轮盘方向变化（非 null = 方向，null = 回中；映射 vpad_dpad）。
  final ValueChanged<String?> onDirection;

  /// 手柄键区按键事件（button: a/b/x/y/lb/rb 或 trigger: lt/rt，按下与
  /// 松开各回报一次；映射 vpad_button / vpad_trigger）。
  final void Function({String? button, String? trigger, required bool pressed})
      onVpadKey;

  final ValueChanged<bool> onEditModeChanged;
  final ValueChanged<RtShortcutItem> onFire;
  final VoidCallback onEditShortcuts;
  final VoidCallback onExit;
  final void Function(String message) onNotify;

  @override
  State<RtCanvasView> createState() => _RtCanvasViewState();
}

class _RtCanvasViewState extends State<RtCanvasView> {
  // 模块尺寸范围（wMin, wMax, hMin, hMax，归一化）。轮盘恒以正方形渲染
  // （取宽高像素较小者），范围即正方形的两轴限位。
  static (double, double, double, double) _moduleRange(String id) =>
      switch (id) {
        kRtCanvasModuleTouchpad => (0.25, 1.0, 0.35, 1.0),
        kRtCanvasModuleDpad => (0.12, 0.65, 0.12, 0.85),
        kRtCanvasModuleVpad => (0.25, 0.70, 0.35, 1.0),
        _ => (0.20, 1.0, 0.08, 0.40),
      };

  // 输入框像素高度硬钳（fraction 随画布高浮动，太扁/太高都不成框）。
  static const double _inputHMinPx = 44, _inputHMaxPx = 180;

  final GlobalKey _canvasKey = GlobalKey();

  // 输入框焦点：IME 弹出时输入模块停靠键盘上方（见 _inputModule），失焦回锚点。
  final FocusNode _inputFocus = FocusNode();

  // 移动预览：模块 id → 当前归一化中心。松手一次性回写。
  String? _dragId;
  Offset? _dragPos;

  // 模块缩放预览：id + 实时宽高（归一化）。
  String? _resizeModuleId;
  double _liveW = 0;
  double _liveH = 0;

  @override
  void initState() {
    super.initState();
    // 焦点变化触发重建：IME 弹出/收起时输入模块在「停靠位 ↔ 锚点位」间切换。
    _inputFocus.addListener(_onInputFocusChanged);
  }

  void _onInputFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _inputFocus.removeListener(_onInputFocusChanged);
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RtCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换布局：清掉上一套布局的拖动/缩放预览，避免预览值瞬移到新布局。
    if (oldWidget.activeId != widget.activeId) {
      setState(() {
        _dragId = null;
        _dragPos = null;
        _resizeModuleId = null;
        _liveW = 0;
        _liveH = 0;
      });
    }
  }

  // ================= 布局解析 =================

  /// 模块锚点（内置布局与自定义都必有；防御性兜底：缺则按隐藏处理）。
  RtCanvasAnchor _anchorOf(String id) {
    final a = widget.activeLayout.modules[id];
    if (a != null) return a;
    return const RtCanvasAnchor(visible: false, x: 0.5, y: 0.5);
  }

  Offset _anchorPos(String id) {
    if (_dragId == id && _dragPos != null) return _dragPos!;
    final a = _anchorOf(id);
    return Offset(a.x, a.y);
  }

  /// 模块实时宽高（缩放预览优先，否则锚点值，缺省回默认）。
  (double, double) _moduleFractions(String id) {
    if (_resizeModuleId == id) return (_liveW, _liveH);
    final a = _anchorOf(id);
    if (a.w != null && a.h != null) return (a.w!, a.h!);
    return switch (id) {
      // 轮盘默认规格 = 游戏布局内置值（缩略图同源，两处不许两套）。
      kRtCanvasModuleDpad => (0.30, 0.78),
      kRtCanvasModuleVpad => (0.44, 0.90),
      kRtCanvasModuleTouchpad => (kRtCanvasPadDefW, kRtCanvasPadDefH),
      _ => (kRtCanvasInputDefW, kRtCanvasInputDefH),
    };
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
      clamp01(local.dx / size.width),
      clamp01(local.dy / size.height),
    );
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
    if ((settled - Offset(cur.x, cur.y)).distance <= 1e-6) return;
    widget.onLayoutChanged(
      _patchAnchor(
        id,
        x: settled.dx.clamp(0.0, 1.0).toDouble(),
        y: settled.dy.clamp(0.0, 1.0).toDouble(),
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
    if ((wf - (cur.w ?? _moduleFractions(id).$1)).abs() <= 1e-6 &&
        (hf - (cur.h ?? _moduleFractions(id).$2)).abs() <= 1e-6) {
      return;
    }
    widget.onLayoutChanged(_patchAnchor(id, w: wf, h: hf));
    unawaited(HapticFeedback.selectionClick());
  }

  void _updateButton(String id, RtCanvasButtonPos pos) {
    widget.onLayoutChanged(_patchButton(id, pos));
  }

  void _toggleModuleVisible(String id) {
    final cur = _anchorOf(id);
    // 首次加回（无锚点条目）给一个语义化初始位：轮盘落左侧手柄位，
    // 其余落画布中心——避免轮盘凭空压在右侧按钮簇上。
    if (widget.activeLayout.modules[id] == null) {
      final seed = id == kRtCanvasModuleDpad
          ? const RtCanvasAnchor(
              visible: true,
              x: 0.24,
              y: 0.52,
              w: 0.30,
              h: 0.78,
            )
          : null;
      if (seed != null) {
        widget.onLayoutChanged(
          _patchAnchor(
            id,
            visible: true,
            x: seed.x,
            y: seed.y,
            w: seed.w,
            h: seed.h,
          ),
        );
        unawaited(HapticFeedback.selectionClick());
        return;
      }
    }
    widget.onLayoutChanged(_patchAnchor(id, visible: !cur.visible));
    unawaited(HapticFeedback.selectionClick());
  }

  /// 拷贝当前 activeLayout 并替换指定模块/按钮后返回新 RtCanvasLayout。
  RtCanvasLayout _patchAnchor(
    String id, {
    bool? visible,
    double? x,
    double? y,
    double? w,
    double? h,
  }) {
    final modules = Map<String, RtCanvasAnchor>.of(widget.activeLayout.modules);
    final cur =
        modules[id] ?? const RtCanvasAnchor(visible: true, x: 0.5, y: 0.5);
    modules[id] = RtCanvasAnchor(
      visible: visible ?? cur.visible,
      x: x ?? cur.x,
      y: y ?? cur.y,
      w: w ?? cur.w,
      h: h ?? cur.h,
    );
    return RtCanvasLayout(
      modules: modules,
      buttons: widget.activeLayout.buttons,
    );
  }

  RtCanvasLayout _patchButton(String id, RtCanvasButtonPos pos) {
    final buttons = Map<String, RtCanvasButtonPos>.of(
      widget.activeLayout.buttons,
    );
    buttons[id] = pos;
    return RtCanvasLayout(
      modules: widget.activeLayout.modules,
      buttons: buttons,
    );
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    return Scaffold(
      // 键盘不压缩画布：横屏弹 IME 若整页 resize，归一化坐标全部漂移、
      // 模块被压扁——画布保持原尺寸，输入框由 [_inputModule] 停靠到键盘上方。
      resizeToAvoidBottomInset: false,
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
                  if (_anchorOf(kRtCanvasModuleDpad).visible)
                    _dpadModule(canvasSize),
                  if (_anchorOf(kRtCanvasModuleVpad).visible)
                    _vpadModule(canvasSize),
                  if (_anchorOf(kRtCanvasModuleTouchpad).visible)
                    _touchpadModule(canvasSize),
                  if (_anchorOf(kRtCanvasModuleInput).visible)
                    _inputModule(canvasSize),
                  ..._buttonModules(canvasSize),
                ],
              );
            },
          ),
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
            const SizedBox(width: 8),
            // 当前布局名：配置隔离的可见面——不看 sheet 也知道此刻是哪套。
            Flexible(
              child: Text(
                _activeName() ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
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
              icon: Icons.dashboard_customize_outlined,
              tooltip: '切换布局',
              onTap: () => _openLayoutsSheet(),
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

  // ---- 编辑态 chrome：顶部面板 + 左下完成钮 + 画布描边 ----
  // 面板放顶部、完成钮放左下：游戏布局的按钮簇占据右半与底部（次键
  // y≈0.88），chrome 放底部会压簇、放右下会压键——顶部与左下是簇外空位。

  List<Widget> _editChrome(ColorScheme cs) {
    return [
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
      Align(
        alignment: Alignment.bottomLeft,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 0, 12),
            child: FilledButton.icon(
              onPressed: () => widget.onEditModeChanged(false),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('完成'),
            ),
          ),
        ),
      ),
      Align(
        alignment: Alignment.topCenter,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _moduleVisibilityChip(
                    icon: Icons.mouse_outlined,
                    label: '触摸板',
                    id: kRtCanvasModuleTouchpad,
                  ),
                  const SizedBox(width: 8),
                  _moduleVisibilityChip(
                    icon: Icons.keyboard_alt_outlined,
                    label: '输入框',
                    id: kRtCanvasModuleInput,
                  ),
                  const SizedBox(width: 8),
                  _moduleVisibilityChip(
                    icon: Icons.gamepad_outlined,
                    label: '轮盘',
                    id: kRtCanvasModuleDpad,
                  ),
                  const SizedBox(width: 8),
                  _moduleVisibilityChip(
                    icon: Icons.sports_esports_outlined,
                    label: '手柄',
                    id: kRtCanvasModuleVpad,
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(
                      Icons.dashboard_customize_outlined,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                    label: const Text('布局'),
                    onPressed: _openLayoutsSheet,
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(
                      Icons.playlist_add,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                    label: const Text('编辑快捷键'),
                    onPressed: widget.onEditShortcuts,
                  ),
                ],
              ),
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

  /// 当前激活布局名（sheet 同源；查不到返回 null → 浮层不显示名字）。
  String? _activeName() {
    for (final p in widget.layouts.list) {
      if (p.id == widget.activeId) return p.name;
    }
    return null;
  }

  // ---- 布局 sheet ----

  Future<void> _openLayoutsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RtCanvasLayoutsSheet(
        layouts: widget.layouts,
        activeId: widget.activeId,
        onSwitch: (id) {
          widget.onSwitchLayout(id);
          Navigator.of(ctx).pop();
        },
        onCopy: () {
          widget.onCopyToCustom();
          Navigator.of(ctx).pop();
        },
        onDelete: (id) {
          widget.onDeleteCustom(id);
          Navigator.of(ctx).pop();
        },
        onRename: (id, name) {
          widget.onRenameCustom(id, name);
          Navigator.of(ctx).pop();
        },
        onResetBuiltin: (id) {
          widget.onResetBuiltin(id);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  // ---- 模块通用：尺寸解析与编辑态包装 ----

  Size _moduleSizePx(String id, Size canvasSize) {
    final (wf, hf) = _moduleFractions(id);
    double w = wf * canvasSize.width;
    double h = hf * canvasSize.height;
    if (id == kRtCanvasModuleInput) {
      h = h.clamp(_inputHMinPx, _inputHMaxPx).toDouble();
    }
    return Size(w, h);
  }

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
          child: IgnorePointer(child: _editFrame(child, label)),
        ),
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
                Icon(
                  Icons.drag_indicator,
                  size: 14,
                  color: cs.primary.withValues(alpha: 0.9),
                ),
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

  // ---- 模块：方向轮盘 ----

  Widget _dpadModule(Size canvasSize) {
    final (wf, hf) = _moduleFractions(kRtCanvasModuleDpad);
    // 恒正方形：取宽高像素较小者（fractions 相对 W/H 两轴，直接乘会出椭圆）。
    final side = math.min(wf * canvasSize.width, hf * canvasSize.height);
    final rect = _moduleRect(
      _anchorPos(kRtCanvasModuleDpad),
      Size(side, side),
      canvasSize,
    );
    Widget pad = RtCanvasDpad(
      enabled: widget.connected,
      showLegend: !widget.editMode,
      onDirection: widget.onDirection,
    );
    if (widget.editMode) {
      pad = _editModuleWrapper(
        id: kRtCanvasModuleDpad,
        label: '轮盘',
        child: SizedBox(width: side, height: side, child: pad),
      );
    }
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: side,
      height: side,
      child: pad,
    );
  }

  // ---- 模块：手柄键区（ABXY + LB/RB + LT/RT，接 PC 虚拟手柄）----

  Widget _vpadModule(Size canvasSize) {
    final (wf, hf) = _moduleFractions(kRtCanvasModuleVpad);
    final size = Size(wf * canvasSize.width, hf * canvasSize.height);
    final rect = _moduleRect(
      _anchorPos(kRtCanvasModuleVpad),
      size,
      canvasSize,
    );
    Widget pad = RtCanvasVpad(
      enabled: widget.connected,
      onKey: ({String? button, String? trigger, required bool pressed}) =>
          widget.onVpadKey(button: button, trigger: trigger, pressed: pressed),
    );
    if (widget.editMode) {
      pad = _editModuleWrapper(
        id: kRtCanvasModuleVpad,
        label: '手柄',
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
    final rect = _moduleRect(
      _anchorPos(kRtCanvasModuleInput),
      size,
      canvasSize,
    );
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
              focusNode: _inputFocus,
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
      box = _editModuleWrapper(
        id: kRtCanvasModuleInput,
        label: '输入框',
        child: SizedBox(width: size.width, height: size.height, child: box),
      );
      return Positioned(
        left: rect.left,
        top: rect.top,
        width: size.width,
        height: size.height,
        child: box,
      );
    }
    // 使用态 IME 停靠：键盘弹出且输入框聚焦 → 输入框浮到键盘正上方
    // （水平近满宽）。画布本体不动（resize 已关），失焦回锚点位；停靠位
    // 是纯视图态，不落盘。
    final imeHeight = MediaQuery.viewInsetsOf(context).bottom;
    if (imeHeight > 0 && _inputFocus.hasFocus) {
      return Positioned(
        left: canvasSize.width * 0.04,
        right: canvasSize.width * 0.04,
        bottom: imeHeight + 8,
        height: size.height,
        child: box,
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
    // 纯手柄布局（游戏布局）：按钮区归 vpad 模块，快捷键按钮整体不参与。
    if (widget.activeLayout.hideShortcuts) return const [];
    final assigned = <String, Offset>{
      for (final e in widget.activeLayout.buttons.entries)
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
      final pos =
          widget.activeLayout.buttons[item.id] ??
          RtCanvasButtonPos(x: center.dx, y: center.dy);
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
