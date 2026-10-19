// lib/lab/demos/remotetype/rt_canvas_view.dart
//
// 横屏画布：触摸板 / 输入框 / 快捷按钮是同一模块系统的三类模块，整个横屏
// 自由编排。形态源自「游戏手柄」（左手触摸区、右手按钮区），但布局不封死
// ——编辑模式下每个模块可拖动摆位、触摸板与输入框可开关显隐。
//
// 两态（边界刻意做得明显）：
//   use（使用态）—— 触摸板吃手势、输入框打字、按钮点按触发 + 长按拖动；
//                   顶部浮层 = 连接点 · 灵敏度 · 进入编辑 · 退出。
//   edit（编辑态）—— 触摸板/输入框/按钮全部转入摆位（画布主色描边框 +
//                   顶部横幅 + 底部显隐面板；所有使用类手势停用，拖动直达
//                   不需长按）。进出经顶部横幅「完成」或系统返回（页面层
//                   PopScope 先退编辑再退画布）。
//
// 布局持久化：RtCanvasLayout（模块锚点 + 按钮归一化中心），拖动期间本地
// 预览、松手一次性回写（页面层落盘）。坐标全部归一化，与屏幕尺寸解耦。
//
// AppBar 不参与（全出血）；退出走浮层或系统返回。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context/colors.dart';
import 'rt_prefs.dart' show RtCanvasAnchor, RtCanvasLayout, RtShortcutItem;
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

  /// 摆位落位 / 显隐切换回写（页面层持久化）。
  final ValueChanged<RtCanvasLayout> onLayoutChanged;
  final ValueChanged<RtShortcutItem> onFire;
  final VoidCallback onEditShortcuts;
  final VoidCallback onExit;
  final void Function(String message) onNotify;

  @override
  State<RtCanvasView> createState() => _RtCanvasViewState();
}

class _RtCanvasViewState extends State<RtCanvasView> {
  // 按钮规格。
  static const double _btnW = 86;
  static const double _btnH = 56;

  // 模块规格（位置可编排、大小固定 v1）：触摸板按画布比例、输入框定高。
  static const double _padWf = 0.54;
  static const double _padHf = 0.84;
  static const double _inputH = 64;

  final GlobalKey _canvasKey = GlobalKey();

  // 拖动预览（编辑态）：模块/按钮 id → 当前归一化中心。松手一次性回写。
  String? _dragId;
  Offset? _dragPos;

  // ================= 布局解析 =================

  /// 内置默认布局（布局数据缺条目时兜底）：触摸板居左、输入框右上，
  /// 按钮自动找位——首跑即接近旧手柄形态。
  static RtCanvasAnchor _defaultAnchor(String id) {
    if (id == kRtCanvasModuleTouchpad) {
      return const RtCanvasAnchor(visible: true, x: 0.27, y: 0.55);
    }
    return const RtCanvasAnchor(visible: true, x: 0.73, y: 0.16);
  }

  RtCanvasAnchor _anchorOf(String id) =>
      widget.layout.modules[id] ?? _defaultAnchor(id);

  Offset _anchorPos(String id) {
    if (_dragId == id && _dragPos != null) return _dragPos!;
    final a = _anchorOf(id);
    return Offset(a.x, a.y);
  }

  /// 全局坐标 → 画布归一化坐标。画布异常小（span ≤ 0）时 0/0 = NaN 会
  /// 一路漏进 Positioned 撑爆布局，落中心兜底。
  Offset _toCanvasNormalized(Offset global) {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return const Offset(0.5, 0.5);
    final size = box.size;
    if (size.width <= 0 || size.height <= 0) return const Offset(0.5, 0.5);
    final local = box.globalToLocal(global);
    double clamp01(double v) => v.clamp(0.0, 1.0).toDouble();
    return Offset(clamp01(local.dx / size.width), clamp01(local.dy / size.height));
  }

  /// 拖动落位回写：use 态按钮长按拖动与 edit 态模块拖动共用一个出口。
  void _commitDrag() {
    final id = _dragId;
    final settled = _dragPos;
    setState(() {
      _dragId = null;
      _dragPos = null;
    });
    if (id == null || settled == null) return;
    final clamped = Offset(
      settled.dx.clamp(0.0, 1.0).toDouble(),
      settled.dy.clamp(0.0, 1.0).toDouble(),
    );
    if (id == kRtCanvasModuleTouchpad || id == kRtCanvasModuleInput) {
      final cur = _anchorOf(id);
      widget.onLayoutChanged(
        widget.layout.withModule(
          id,
          RtCanvasAnchor(visible: cur.visible, x: clamped.dx, y: clamped.dy),
        ),
      );
    } else {
      widget.onLayoutChanged(widget.layout.withButton(id, clamped));
    }
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
      // 顶部横幅：状态名 + 操作提示 + 完成
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              children: [
                Icon(Icons.edit, size: 16, color: cs.onPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '编辑布局 · 拖动模块调整位置',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => widget.onEditModeChanged(false),
                  style: TextButton.styleFrom(
                    foregroundColor: cs.onPrimary,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('完成'),
                ),
              ],
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
                  avatar: Icon(Icons.playlist_add, size: 18,
                      color: cs.onSurfaceVariant),
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
      onSelected: (_) {
        final cur = _anchorOf(id);
        widget.onLayoutChanged(
          widget.layout.withModule(
            id,
            RtCanvasAnchor(visible: !cur.visible, x: cur.x, y: cur.y),
          ),
        );
        unawaited(HapticFeedback.selectionClick());
      },
      avatar: Icon(
        visible ? Icons.visibility : Icons.visibility_off,
        size: 18,
        color: visible ? cs.primary : cs.onSurfaceVariant,
      ),
      label: Text(label),
    );
  }

  // ---- 模块：触摸板 ----

  Widget _touchpadModule(Size canvasSize) {
    final w = canvasSize.width * _padWf;
    final h = canvasSize.height * _padHf;
    final rect = _moduleRect(_anchorPos(kRtCanvasModuleTouchpad),
        Size(w, h), canvasSize);
    Widget pad = RtTouchSurface(
      session: widget.session,
      connected: widget.connected,
      sensitivity: widget.sensitivity,
      onNotify: widget.onNotify,
      // 编辑态不展示手势图例（图例讲的是使用态手势）。
      showLegend: !widget.editMode,
    );
    if (widget.editMode) {
      // 编辑态：手势面停用，拖动直达（pan 不进手势仲裁的长按等待）。
      pad = _panDraggable(
        id: kRtCanvasModuleTouchpad,
        child: IgnorePointer(child: _editFrame(pad, '触摸板')),
      );
    }
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: w,
      height: h,
      child: pad,
    );
  }

  // ---- 模块：输入框 ----

  Widget _inputModule(Size canvasSize) {
    final w = canvasSize.width * 0.46;
    final rect = _moduleRect(
      _anchorPos(kRtCanvasModuleInput),
      Size(w, _inputH),
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
      // 编辑态：输入框停用（不弹键盘），拖动直达。
      box = _panDraggable(
        id: kRtCanvasModuleInput,
        child: IgnorePointer(child: _editFrame(box, '输入框')),
      );
    }
    return Positioned(left: rect.left, top: rect.top, width: w, height: _inputH, child: box);
  }

  // ---- 模块：快捷按钮 ----

  List<Widget> _buttonModules(Size canvasSize) {
    // 摆位解析：已存的直接用；没存过的按候选槽找空位（本次 build 内
    // 顺次占位，保证多个新按钮互不重叠、且重建结果稳定）。
    final assigned = Map.of(widget.layout.buttons);
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
    return [
      for (final item in widget.shortcuts)
        _buttonModule(item, savedPos: resolved[item.id]!, canvasSize: canvasSize),
    ];
  }

  Widget _buttonModule(
    RtShortcutItem item, {
    required Offset savedPos,
    required Size canvasSize,
  }) {
    final c = context.colors;
    final cs = c.scheme;
    final busy = widget.firingId == item.id;
    final dragging = _dragId == item.id;
    final pos = dragging && _dragPos != null ? _dragPos! : savedPos;

    // 归一化中心 → 像素中心，再夹回按钮完整在场内。
    final cx = (pos.dx * canvasSize.width).clamp(
      _btnW / 2,
      canvasSize.width < _btnW ? _btnW / 2 : canvasSize.width - _btnW / 2,
    );
    final cy = (pos.dy * canvasSize.height).clamp(
      _btnH / 2,
      canvasSize.height < _btnH ? _btnH / 2 : canvasSize.height - _btnH / 2,
    );

    final bg = busy ? cs.primary : c.surface;
    final fg = busy ? cs.onPrimary : (widget.connected ? c.text : c.textMuted);

    Widget button = AnimatedScale(
      scale: dragging ? 1.10 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: _btnW,
        height: _btnH,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: dragging
                ? cs.primary.withValues(alpha: 0.8)
                : cs.outlineVariant.withValues(alpha: 0.6),
            width: dragging ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: dragging ? 0.22 : 0.10),
              blurRadius: dragging ? 18 : 8,
              offset: Offset(0, dragging ? 8 : 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            // 编辑态禁触发：摆位时误发快捷键代价高（锁屏类还有确认弹窗）。
            onTap: widget.editMode ? null : () => widget.onFire(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimary,
                        ),
                      )
                    : Text(
                        item.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.editMode) {
      button = _panDraggable(id: item.id, startPos: savedPos, child: button);
    } else {
      // 使用态：长按拖动（抓取点保持不跳）；轻点让给内层 InkWell。
      button = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (d) {
          HapticFeedback.mediumImpact();
          final finger = _toCanvasNormalized(d.globalPosition);
          setState(() {
            _dragId = item.id;
            _dragPos = savedPos; // 拾起瞬间按钮原地不动
            _grabDelta = finger - savedPos;
          });
        },
        onLongPressMoveUpdate: (d) {
          final finger = _toCanvasNormalized(d.globalPosition);
          setState(() => _dragPos = finger - _grabDelta);
        },
        onLongPressEnd: (_) => _commitDrag(),
        onLongPressCancel: () {
          setState(() {
            _dragId = null;
            _dragPos = null;
          });
        },
        child: button,
      );
    }
    return Positioned(
      left: cx - _btnW / 2,
      top: cy - _btnH / 2,
      child: button,
    );
  }

  // 抓取点偏差：拾起时手指与按钮中心的距离，拖动期间保持不跳。
  Offset _grabDelta = Offset.zero;

  // ---- 编辑态拖动通用件 ----

  /// 编辑态的直拖包装：pan 不需要长按等待，进入编辑即所见即所得。
  /// [startPos] 缺省时按钮取其已解析摆位——自动找位的新按钮拖动起点
  /// 必须是它屏幕上的位置，落到中心兜底会瞬移。
  Widget _panDraggable({
    required String id,
    required Widget child,
    Offset? startPos,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        HapticFeedback.mediumImpact();
        setState(() {
          _dragId = id;
          _dragPos = startPos ??
              (id == kRtCanvasModuleTouchpad || id == kRtCanvasModuleInput
                  ? _anchorPos(id)
                  : widget.layout.buttons[id] ?? const Offset(0.5, 0.5));
        });
      },
      onPanUpdate: (d) {
        final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || _dragPos == null) return;
        final size = box.size;
        setState(() {
          _dragPos = Offset(
            _dragPos!.dx + d.delta.dx / size.width,
            _dragPos!.dy + d.delta.dy / size.height,
          );
        });
      },
      onPanEnd: (_) => _commitDrag(),
      onPanCancel: () {
        setState(() {
          _dragId = null;
          _dragPos = null;
        });
      },
      child: child,
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
                Icon(Icons.drag_indicator, size: 14,
                    color: cs.primary.withValues(alpha: 0.9)),
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

  /// 归一化中心 + 固定规格 → 像素矩形（夹回画布内）。
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
}
