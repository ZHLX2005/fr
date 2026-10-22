// lib/core/remotetype/canvas/rt_canvas_view.dart
//
// 横竖屏画布：触摸板 / 输入框 / 虚拟键盘 / 轮盘 / 手柄键区 / 快捷按钮同属
// 一个模块系统，自由编排。当前编排属于「当前朝向的激活布局」—— 用户可在
// 编辑态的「布局」入口切换 / 复制（自选横竖屏）/ 重命名 / 恢复出厂 / 删除
// （详见 rt_canvas_presets + rt_canvas_layouts_sheet；面板渲染持久化版本，
// 缩略图即各布局真实样子；横屏左抽屉 / 竖屏底抽屉，对齐原型）。
//
// 两态（边界刻意做得明显；编辑布局只有一个入口）：
//   use（使用态）—— 触摸板吃手势、输入框打字、键盘按键即发、按钮点按触发；
//                   编排手势一律不在使用态提供（编辑唯一入口 = 左上胶囊菜单
//                   的「编辑布局」）；胶囊收起时只露「状态点 + 布局名」。
//   edit（编辑态）—— 画布主色描边框 + 顶部居中显隐面板（含「完成」），
//                   所有使用类手势停用。拖动=移位、右下角拉手=缩放、
//                   点按按钮=显隐（隐藏者以幽灵呈现可点回）。切布局会
//                   自动清掉拖动预览（避免旧布局预览值瞬移到新布局）。
//   竖屏提示层 —— 激活布局锁定横屏（含轮盘/手柄/键盘模块）时旋转到竖屏，
//                   毛玻璃提示层盖住画布：旋转手机动画 + 请横屏使用 +
//                   一键锁横屏 / 切换布局逃生（用户主动选定竖屏布局后
//                   本轮不再提示）。
//
// 职责切分：快捷键「有哪些」归打字页编辑器；画布「显示哪几个」= 布局
// buttons 显式收录且 v=true（opt-in，未收录使用态不出现）。布局集合
// 「用哪一套」归画布面板（RtCanvasLayouts，分朝向激活）。

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context/colors.dart';
import 'rt_canvas_button.dart' show RtCanvasButton, RtCanvasGripDot;
import 'rt_canvas_dpad.dart' show RtCanvasDpad;
import 'rt_canvas_kb.dart' show RtCanvasKb;
import 'rt_canvas_modules.dart'
    show
        RtCanvasModuleSpec,
        kRtCanvasModuleSpecs,
        rtCanvasModuleDefaults,
        rtCanvasModuleRange;
import 'rt_canvas_stick.dart' show RtCanvasStick;
import 'rt_canvas_vpad.dart' show RtCanvasVpad, rtVpadKeyOrder;
import '../ui/rt_layout_picker.dart' show showRtLayoutPicker;
import '../data/rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasButtonPos,
        RtCanvasLayout,
        RtCanvasLayouts,
        RtShortcutItem,
        kRtCanvasModuleComposer,
        kRtCanvasModuleDpad,
        kRtCanvasModuleInput,
        kRtCanvasModuleKb,
        kRtCanvasModuleStickL,
        kRtCanvasModuleStickR,
        kRtCanvasModuleTouchpad,
        kRtCanvasModuleVpad;
import '../protocol/rt_session.dart';
import 'rt_touch_surface.dart' show RtTouchSurface, showRtSensitivitySheet;

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
/// （test/core/remotetype/rt_canvas_layout_test.dart）。
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
    required this.orientation,
    required this.composerModule,
    required this.editMode,
    required this.onLayoutChanged,
    required this.onSwitchLayout,
    required this.onOpenSettings,
    required this.onDirection,
    required this.onVpadKey,
    required this.onStickAxis,
    required this.onKbChord,
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

  /// 当前激活布局的 id（页面按当前朝向取的那条）。仅用于 sheet 高亮与
  /// 「切布局」时识别——画布渲染只看 activeLayout。
  final String activeId;

  /// 全部布局（内置 + 自定义，横竖两朝向），sheet 按朝向分组展示用。
  final RtCanvasLayouts layouts;

  /// 画布当前朝向（kRtCanvasOrient*，页面随设备旋转刷新）。决定 sheet
  /// 哪一组可交互、以及「当前激活」高亮取哪一侧。
  final String orientation;

  /// 输入页模块的内容（页面层装配好的 RtInputView——连接态/回调都在页面，
  /// 画布只负责按锚点摆放）。
  final Widget composerModule;
  final bool editMode;

  /// 当前激活布局的内容变更（拖动 / 缩放 / 显隐 / 模块开关）。
  final ValueChanged<RtCanvasLayout> onLayoutChanged;

  /// 切换激活布局。
  final ValueChanged<String> onSwitchLayout;

  /// 打开 RT 设置页（编排 / 发送换行 / 灵敏度 / 快捷键都在那里）。
  final VoidCallback onOpenSettings;

  /// 方向轮盘方向变化（非 null = 方向，null = 回中；映射 vpad_dpad）。
  final ValueChanged<String?> onDirection;

  /// 手柄键区按键事件（button: a/b/x/y/lb/rb 或 trigger: lt/rt，按下与
  /// 松开各回报一次；映射 vpad_button / vpad_trigger）。
  final void Function({String? button, String? trigger, required bool pressed})
  onVpadKey;

  /// 模拟摇杆轴值变化（axis ∈ lx/ly/rx/ry，value ∈ -1..1）→ 发 vpad_axis。
  final void Function(String axis, double value) onStickAxis;

  /// 虚拟键盘一次按键（修饰键已由键盘模块粘滞合成进 chord）→ 发 hotkey。
  final ValueChanged<List<String>> onKbChord;

  final ValueChanged<bool> onEditModeChanged;
  final ValueChanged<RtShortcutItem> onFire;
  final VoidCallback onEditShortcuts;
  final VoidCallback onExit;
  final void Function(String message) onNotify;

  @override
  State<RtCanvasView> createState() => _RtCanvasViewState();
}

class _RtCanvasViewState extends State<RtCanvasView>
    with SingleTickerProviderStateMixin {
  // 模块尺寸限位 / 缺省规格：登记表单一事实源（设置页档位同口径）。
  static (double, double, double, double) _moduleRange(String id) =>
      rtCanvasModuleRange(id);

  // 输入框像素高度硬钳（fraction 随画布高浮动，太扁/太高都不成框）。
  static const double _inputHMinPx = 44, _inputHMaxPx = 180;

  final GlobalKey _canvasKey = GlobalKey();

  // 输入框焦点：IME 弹出时输入模块停靠键盘上方（见 _inputModule），失焦回锚点。
  final FocusNode _inputFocus = FocusNode();

  // 移动预览：模块 id → 当前归一化中心。松手一次性回写。
  String? _dragId;
  Offset? _dragPos;

  /// 手柄逐键拖/缩进行中 → 模块整搬让路（见 [RtCanvasVpad.onKeyEditActive]）。
  bool _vpadKeyEditActive = false;

  // 模块缩放预览：id + 实时宽高（归一化）。
  String? _resizeModuleId;
  double _liveW = 0;
  double _liveH = 0;

  /// 编辑态功能清单是否收起（收起后只留一颗「编辑工具」chip，不挡画布）。
  /// 默认收起——进编辑态先把画布还给用户，清单点开再看。
  bool _editBarCollapsed = true;

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
    // 进入编辑态：默认收起，只留一颗「编辑工具」chip——功能清单点开再看，
    // 不一进编辑态就把工具条铺在画布上（横屏顶部是主视线）。
    if (widget.editMode && !oldWidget.editMode) {
      _editBarCollapsed = true;
    }
    if (!widget.editMode && oldWidget.editMode) {
      _vpadKeyEditActive = false;
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
    // 缺省规格 = 登记表出厂值（原型 LAYOUTS 同源；缩略图/设置页档位同口径）。
    return rtCanvasModuleDefaults(id);
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
    // 全部模块都可整搬（旧实现只放行触摸板/输入框，轮盘/手柄/键盘拖不动）。
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
    // 首次加回（无锚点条目）：非锁定模块落登记表缺省规格 + 画布中心；
    // 轮盘/手柄/键盘给出厂语义位（对齐原型 LAYOUTS），避免压住其它模块。
    if (widget.activeLayout.modules[id] == null) {
      final seed = switch (id) {
        kRtCanvasModuleDpad => const RtCanvasAnchor(
          visible: true,
          x: 0.21,
          y: 0.54,
          w: 0.22,
          h: 0.52,
        ),
        kRtCanvasModuleVpad => const RtCanvasAnchor(
          visible: true,
          x: 0.765,
          y: 0.53,
          w: 0.36,
          h: 0.70,
        ),
        kRtCanvasModuleKb => const RtCanvasAnchor(
          visible: true,
          x: 0.50,
          y: 0.55,
          w: 0.94,
          h: 0.82,
        ),
        kRtCanvasModuleComposer => const RtCanvasAnchor(
          visible: true,
          x: 0.50,
          y: 0.50,
          w: 1.0,
          h: 1.0,
        ),
        _ => null,
      };
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
  /// hideShortcuts 必须原样携带——游戏/键盘布局靠它压掉快捷键按钮，丢了
  /// 等于「拖一下模块，按钮整体复活」（跨布局配置串台）。
  /// anchor 同理走 copyWith——轮盘的方向模式（dir8）挂在 anchor 上，
  /// 手建新对象会把它悄悄丢掉（切了八向、拖一下模块就回四向）。
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
    modules[id] = cur.copyWith(
      visible: visible,
      x: x,
      y: y,
      w: w,
      h: h,
    );
    return RtCanvasLayout(
      modules: modules,
      buttons: widget.activeLayout.buttons,
      hideShortcuts: widget.activeLayout.hideShortcuts,
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
      hideShortcuts: widget.activeLayout.hideShortcuts,
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
                  if (_anchorOf(kRtCanvasModuleKb).visible)
                    _kbModule(canvasSize),
                  if (_anchorOf(kRtCanvasModuleStickL).visible)
                    _stickModule(canvasSize, kRtCanvasModuleStickL, 'l'),
                  if (_anchorOf(kRtCanvasModuleStickR).visible)
                    _stickModule(canvasSize, kRtCanvasModuleStickR, 'r'),
                  if (_anchorOf(kRtCanvasModuleComposer).visible)
                    _composerModule(canvasSize),
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

  // ---- 使用态浮层：左上胶囊（状态点 + 布局名 + 菜单），对齐原型 ----
  // 原型把操作区收进一颗可展开胶囊，收起时只露「布局名 + 状态点」——画布
  // 主体（触摸板/手柄）不被顶部工具行切割视线。

  Widget _useOverlay(ColorScheme cs) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Row(
          children: [
            _CanvasCapsule(
              cs: cs,
              connected: widget.connected,
              name: _activeName() ?? '',
              onSensitivity: () => showRtSensitivitySheet(
                context,
                value: widget.sensitivity,
                onChanged: widget.onSensitivityChanged,
              ),
              onLayouts: _openLayoutPicker,
              onSettings: widget.onOpenSettings,
              onExit: widget.onExit,
            ),
          ],
        ),
      ),
    );
  }

  // ---- 编辑态 chrome：功能清单可收纳。竖屏收在头部，横屏收在右侧。 ----
  // 展开 = 模块显隐 + 编辑快捷键 + 完成；收起 = 只留一颗「编辑工具」chip，
  // 不挡手柄/键盘视线。
  // 分朝向摆放：竖屏沿用顶部横条（头部位置，横条在窄屏上滑）；横屏把收纳
  // 挪到右侧竖排面板——横屏的上方是游戏/手柄的主视线，不能被工具条切掉。

  List<Widget> _editChrome(ColorScheme cs) {
    final portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
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
      if (portrait)
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: _editBarCollapsed
                  ? _editTriggerChip(cs)
                  : _editTopBar(cs),
            ),
          ),
        )
      else
        Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _editBarCollapsed
                  ? _editTriggerChip(cs)
                  : _editSidePanel(cs),
            ),
          ),
        ),
    ];
  }

  /// 收纳态：单颗「编辑工具」chip（竖屏在头部、横屏在右侧，同一颗）。
  Widget _editTriggerChip(ColorScheme cs) => ActionChip(
    avatar: Icon(Icons.edit_note_outlined, size: 18, color: cs.primary),
    label: Text(
      '编辑工具',
      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
    ),
    onPressed: () => setState(() => _editBarCollapsed = false),
  );

  /// 展开态 · 竖屏：顶部横条（窄屏上滑）。
  Widget _editTopBar(ColorScheme cs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ActionChip(
            avatar: Icon(
              Icons.unfold_less,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            label: const Text('收起'),
            onPressed: () => setState(() => _editBarCollapsed = true),
          ),
          const SizedBox(width: 8),
          // 模块 chip 行由登记表驱动（与模块设置页同一清单）。
          for (final spec in kRtCanvasModuleSpecs) ...[
            _moduleVisibilityChip(
              icon: spec.icon,
              label: spec.name,
              id: spec.id,
            ),
            const SizedBox(width: 8),
          ],
          ActionChip(
            avatar: Icon(
              Icons.playlist_add,
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            label: const Text('编辑快捷键'),
            onPressed: widget.onEditShortcuts,
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: Icon(Icons.check, size: 18, color: cs.primary),
            label: Text(
              '完成',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () => widget.onEditModeChanged(false),
          ),
        ],
      ),
    );
  }

  /// 展开态 · 横屏：右侧竖排控制列表（模块开关逐行 + 快捷键 + 完成）。
  /// 顶栏在横屏是主视线，工具一律挪到右缘竖着排。
  Widget _editSidePanel(ColorScheme cs) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        maxWidth: 208,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(-2, 4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sideRow(
                cs: cs,
                icon: Icons.unfold_more,
                label: '收起',
                onTap: () => setState(() => _editBarCollapsed = true),
              ),
              Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
              // 模块显隐：右侧竖排控制列表（与模块设置页同一清单）。
              for (final spec in kRtCanvasModuleSpecs)
                _moduleSideRow(cs, spec),
              Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
              _sideRow(
                cs: cs,
                icon: Icons.playlist_add,
                label: '编辑快捷键',
                onTap: widget.onEditShortcuts,
              ),
              _sideRow(
                cs: cs,
                icon: Icons.check,
                label: '完成',
                primary: true,
                onTap: () => widget.onEditModeChanged(false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 右侧面板的一行功能（图标 + 文字）。
  Widget _sideRow({
    required ColorScheme cs,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Row(
          children: [
            Icon(
              icon,
              size: 17,
              color: primary ? cs.primary : c.textMuted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: primary ? FontWeight.w700 : FontWeight.w500,
                  color: primary ? cs.primary : c.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右侧面板里的模块行：图标 + 名称 + 显隐开关。
  Widget _moduleSideRow(ColorScheme cs, RtCanvasModuleSpec spec) {
    final c = context.colors;
    final visible = _anchorOf(spec.id).visible;
    return InkWell(
      onTap: () => _toggleModuleVisible(spec.id),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Row(
          children: [
            Icon(spec.icon, size: 16, color: c.textMuted),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                spec.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.text),
              ),
            ),
            Icon(
              visible ? Icons.visibility : Icons.visibility_off,
              size: 16,
              color: visible ? cs.primary : c.textMuted,
            ),
          ],
        ),
      ),
    );
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

  // ---- 布局切换（只切，不编排） ----

  /// 布局切换面板：第一层是所有布局的列表，底下附设置入口。编排（改名 /
  /// 删除 / 新建 / 恢复出厂 / 模块摆放）都在 RT 设置页里。
  Future<void> _openLayoutPicker() async {
    await showRtLayoutPicker(
      context,
      layouts: widget.layouts,
      orientation: widget.orientation,
      activeId: widget.activeId,
      onPick: widget.onSwitchLayout,
      onOpenSettings: widget.onOpenSettings,
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
    bool innerInteractive = false,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            // 逐键拖/缩已占指针：不抢模块整搬，否则键相对画布「拖不动」。
            if (innerInteractive && _vpadKeyEditActive) return;
            HapticFeedback.mediumImpact();
            setState(() {
              _dragId = id;
              _dragPos = _anchorPos(id);
            });
          },
          onPanUpdate: (d) {
            if (innerInteractive && _vpadKeyEditActive) return;
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
          // innerInteractive：模块内容要自己接管手势（手柄逐键拖动）时
          // 不挡指针——键区手势优先，空白处仍由本层整搬。
          child: innerInteractive
              ? _editFrame(child, label)
              : IgnorePointer(child: _editFrame(child, label)),
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
        clipBehavior: Clip.none,
        children: [
          child,
          // 模块标签 pill：顶部居中悬出（对齐原型 tag），主色胶囊 + 同色辉光。
          Positioned(
            top: -9,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.45),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.drag_indicator,
                      size: 12,
                      color: cs.onPrimary.withValues(alpha: 0.95),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: cs.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
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
      dir8: _anchorOf(kRtCanvasModuleDpad).dir8,
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
    final rect = _moduleRect(_anchorPos(kRtCanvasModuleVpad), size, canvasSize);
    // 逐键编排数据：布局 buttons 里的 vpad:<key> 条目（盒内比例位 + 倍率）。
    final offsets = <String, Offset>{};
    final scales = <String, double>{};
    for (final key in rtVpadKeyOrder) {
      final pos = widget.activeLayout.buttons['vpad:$key'];
      if (pos == null) continue;
      offsets[key] = Offset(pos.x * size.width, pos.y * size.height);
      scales[key] = pos.s;
    }
    Widget pad = RtCanvasVpad(
      enabled: widget.connected,
      editMode: widget.editMode,
      keyOffsets: offsets,
      keyScales: scales,
      onKeyEditActive: (active) => _vpadKeyEditActive = active,
      onKeyTransform: (key, center, scale) {
        widget.onLayoutChanged(
          _patchButton(
            'vpad:$key',
            RtCanvasButtonPos(
              x: center.dx.clamp(0.0, 1.0).toDouble(),
              y: center.dy.clamp(0.0, 1.0).toDouble(),
              s: scale,
            ),
          ),
        );
      },
      onKey: ({String? button, String? trigger, required bool pressed}) =>
          widget.onVpadKey(button: button, trigger: trigger, pressed: pressed),
    );
    if (widget.editMode) {
      pad = _editModuleWrapper(
        id: kRtCanvasModuleVpad,
        label: '手柄',
        // 键位要能各自拖动 → 不用 IgnorePointer 挡内容（键区自身接管手势）。
        innerInteractive: true,
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

  // ---- 模块：模拟摇杆（左 / 右）----

  Widget _stickModule(Size canvasSize, String moduleId, String axes) {
    final size = _moduleSizePx(moduleId, canvasSize);
    final rect = _moduleRect(_anchorPos(moduleId), size, canvasSize);
    Widget stick = RtCanvasStick(
      enabled: widget.connected,
      axes: axes,
      editMode: widget.editMode,
      onAxis: widget.onStickAxis,
    );
    if (widget.editMode) {
      stick = _editModuleWrapper(
        id: moduleId,
        label: axes == 'l' ? '左摇杆' : '右摇杆',
        child: SizedBox(width: size.width, height: size.height, child: stick),
      );
    }
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: size.width,
      height: size.height,
      child: stick,
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

  // ---- 模块：输入页（连接后落到的打字页整体，页面层装配内容）----

  Widget _composerModule(Size canvasSize) {
    final size = _moduleSizePx(kRtCanvasModuleComposer, canvasSize);
    final rect = _moduleRect(
      _anchorPos(kRtCanvasModuleComposer),
      size,
      canvasSize,
    );
    Widget page = Material(
      color: context.colors.scheme.surfaceContainerHighest,
      child: widget.composerModule,
    );
    if (widget.editMode) {
      page = _editModuleWrapper(
        id: kRtCanvasModuleComposer,
        label: '输入页',
        child: SizedBox(width: size.width, height: size.height, child: page),
      );
    }
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: size.width,
      height: size.height,
      child: page,
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
    Widget box = ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
          decoration: BoxDecoration(
            color: context.colors.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(999),
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
        ),
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

  // ---- 模块：虚拟键盘（按键即发 hotkey）----

  Widget _kbModule(Size canvasSize) {
    final size = _moduleSizePx(kRtCanvasModuleKb, canvasSize);
    final rect = _moduleRect(_anchorPos(kRtCanvasModuleKb), size, canvasSize);
    Widget kb = RtCanvasKb(
      enabled: widget.connected,
      onChord: widget.onKbChord,
    );
    if (widget.editMode) {
      kb = _editModuleWrapper(
        id: kRtCanvasModuleKb,
        label: '键盘',
        child: SizedBox(width: size.width, height: size.height, child: kb),
      );
    }
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: size.width,
      height: size.height,
      child: kb,
    );
  }

  // ---- 模块：快捷按钮（逐键 opt-in）----
  // 使用态：仅 buttons 里显式收录且 v=true 的键；未收录 = 不渲染。
  // 编辑态：已收录可拖/显隐；未收录以幽灵出现，点按即写入 buttons(v=true)。
  // hideShortcuts（游戏/键盘）：整区不参与，编辑态也不出幽灵。

  List<Widget> _buttonModules(Size canvasSize) {
    if (widget.activeLayout.hideShortcuts) return const [];

    final assigned = <String, Offset>{
      for (final e in widget.activeLayout.buttons.entries)
        e.key: Offset(e.value.x, e.value.y),
    };
    final out = <Widget>[];
    for (final item in widget.shortcuts) {
      final saved = widget.activeLayout.buttons[item.id];
      if (!widget.editMode) {
        if (saved == null || !saved.v) continue;
        out.add(_shortcutButton(item, saved, canvasSize));
        continue;
      }
      // 编辑态：未收录先占一个空槽做幽灵预览（不落盘，点按才写入）。
      final RtCanvasButtonPos pos;
      if (saved != null) {
        pos = saved;
      } else {
        final slot = rtFirstFreeCanvasSlot(assigned.values.toSet());
        assigned[item.id] = slot;
        pos = RtCanvasButtonPos(x: slot.dx, y: slot.dy, v: false);
      }
      out.add(
        _shortcutButton(
          item,
          pos,
          canvasSize,
          onToggleVisible: () {
            if (saved == null) {
              // 首次点按 = 收录并显示
              _updateButton(item.id, pos.copyWith(v: true));
            } else {
              _updateButton(item.id, pos.copyWith(v: !pos.v));
            }
          },
        ),
      );
    }
    return out;
  }

  Widget _shortcutButton(
    RtShortcutItem item,
    RtCanvasButtonPos pos,
    Size canvasSize, {
    VoidCallback? onToggleVisible,
  }) {
    return RtCanvasButton(
      item: item,
      pos: pos,
      canvasSize: canvasSize,
      connected: widget.connected,
      busy: widget.firingId == item.id,
      editMode: widget.editMode,
      onTransform: (c, sc) => _updateButton(
        item.id,
        pos.copyWith(
          x: c?.dx.clamp(0.0, 1.0).toDouble(),
          y: c?.dy.clamp(0.0, 1.0).toDouble(),
          s: sc,
        ),
      ),
      onToggleVisible:
          onToggleVisible ??
          () => _updateButton(item.id, pos.copyWith(v: !pos.v)),
      onFire: widget.onFire,
    );
  }
}

/// 使用态左上胶囊：状态点 + 布局名 + chevron；点开毛玻璃菜单（切换布局 /
/// 远程输入设置 / 返回写字）。收起时不占画布视线。
class _CanvasCapsule extends StatefulWidget {
  const _CanvasCapsule({
    required this.cs,
    required this.connected,
    required this.name,
    required this.onSensitivity,
    required this.onLayouts,
    required this.onSettings,
    required this.onExit,
  });

  final ColorScheme cs;
  final bool connected;
  final String name;
  final VoidCallback onSensitivity;
  final VoidCallback onLayouts;
  final VoidCallback onSettings;
  final VoidCallback onExit;

  @override
  State<_CanvasCapsule> createState() => _CanvasCapsuleState();
}

class _CanvasCapsuleState extends State<_CanvasCapsule> {
  static const _sens = 'sens';
  static const _layouts = 'layouts';
  static const _settings = 'settings';
  static const _exit = 'exit';

  final GlobalKey _key = GlobalKey();
  bool _open = false;

  Future<void> _toggleMenu() async {
    if (_open) return;
    setState(() => _open = true);
    unawaited(HapticFeedback.selectionClick());
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    String? selected;
    if (box != null && overlay != null) {
      // 菜单锚在胶囊正下方，向上留 4px 呼吸、宽度比胶囊略宽。
      final topLeft = box.localToGlobal(
        box.size.bottomLeft(Offset.zero) - const Offset(0, 2),
      );
      final position = RelativeRect.fromRect(
        Rect.fromPoints(topLeft, topLeft.translate(200, 8)),
        Offset.zero & overlay.size,
      );
      selected = await showMenu<String>(
        context: context,
        position: position,
        color: widget.cs.surface.withValues(alpha: 0.96),
        elevation: 8,
        shadowColor: widget.cs.shadow.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: widget.cs.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        popUpAnimationStyle: AnimationStyle(
          curve: Curves.easeOutBack,
          duration: const Duration(milliseconds: 280),
        ),
        items: const [
          PopupMenuItem(
            value: _sens,
            height: 40,
            child: Row(
              children: [
                Icon(Icons.tune, size: 17),
                SizedBox(width: 10),
                Text('触摸板灵敏度', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          PopupMenuItem(
            value: _layouts,
            height: 40,
            child: Row(
              children: [
                Icon(Icons.dashboard_customize_outlined, size: 17),
                SizedBox(width: 10),
                Text('切换布局', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          PopupMenuItem(
            value: _settings,
            height: 40,
            child: Row(
              children: [
                Icon(Icons.tune, size: 17),
                SizedBox(width: 10),
                Text('远程输入设置', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: _exit,
            height: 40,
            child: Row(
              children: [
                Icon(Icons.keyboard_outlined, size: 17),
                SizedBox(width: 10),
                Text('返回写字', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      );
    }
    if (mounted) setState(() => _open = false);
    switch (selected) {
      case _sens:
        widget.onSensitivity();
      case _layouts:
        widget.onLayouts();
      case _settings:
        widget.onSettings();
      case _exit:
        widget.onExit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: InkWell(
          onTap: _toggleMenu,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            key: _key,
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.7),
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 状态点：连接色 + 同色光晕（对齐原型 dot halo）。
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.connected ? cs.primary : cs.outlineVariant,
                    boxShadow: widget.connected
                        ? [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.25),
                              spreadRadius: 2.5,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  child: Icon(
                    Icons.expand_more,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
