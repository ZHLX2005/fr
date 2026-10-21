// lib/lab/demos/remotetype/rt_canvas_button.dart
//
// 画布快捷按钮模块：交互判定与视觉都收在此处，画布层（rt_canvas_view）只管
// 摆位解析与持久化回写。
//
// 两态交互（与画布整体约定一致；**编辑布局只有一个入口** = 画布顶部
// 「编辑布局」，使用态一律不提供任何编排手势）：
//   use（使用态）—— 点按触发快捷键，仅此而已（无长按拖动）。
//   edit（编辑态）—— 拖动移位；右下角拉手缩放（横向驱动倍率）；
//                   点按切换显隐。隐藏的按钮以半透明幽灵呈现（可点回、
//                   可拖可缩），使用态不渲染。
//
// 快捷键的「有哪些」归打字页编辑器（增删改定义），「显示哪些」归这里的
// RtCanvasButtonPos.v——两层职责分离，互不越界。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/context/colors.dart';
import 'rt_prefs.dart'
    show
        RtCanvasButtonPos,
        RtCanvasButtonShape,
        RtShortcutItem,
        kRtCanvasBtnScaleMax,
        kRtCanvasBtnScaleMin;
import 'rt_shortcut_bar.dart' show RtKeyDisplay;

/// 按钮基准规格（倍率 1.0）。倍率上下限在 rt_prefs（单一事实源）。
const double kRtCanvasBtnBaseW = 86;
const double kRtCanvasBtnBaseH = 56;

/// 圆形按钮基准直径（倍率 1.0）。手柄键用——面积取胶囊两档之间。
const double kRtCanvasBtnCircleBase = 62;

class RtCanvasButton extends StatefulWidget {
  const RtCanvasButton({
    super.key,
    required this.item,
    required this.pos,
    required this.canvasSize,
    required this.connected,
    required this.busy,
    required this.editMode,
    required this.onTransform,
    required this.onToggleVisible,
    required this.onFire,
  });

  final RtShortcutItem item;
  final RtCanvasButtonPos pos;
  final Size canvasSize;
  final bool connected;
  final bool busy;
  final bool editMode;

  /// 变换落定（画布层钳制并持久化）。位移与倍率合成一个回调：两指同按
  /// （拖体 + 拉手）各改一个预览字段时，一次提交读的是同一份快照——拆成
  /// 两个回调会各自从旧 widget.pos 出发 copyWith，后提交的把先提交的覆盖掉。
  /// null = 该维度本次没动。
  final void Function(Offset? pos, double? scale) onTransform;
  final VoidCallback onToggleVisible;
  final ValueChanged<RtShortcutItem> onFire;

  @override
  State<RtCanvasButton> createState() => _RtCanvasButtonState();
}

class _RtCanvasButtonState extends State<RtCanvasButton> {
  // 拖动/缩放的本地预览（松手一次性回写，拖动期间所见即所得）。
  // 仅编辑态使用——使用态没有任何编排手势（编辑唯一入口 = 顶部「编辑布局」）。
  Offset? _dragPos;
  double? _dragScale;

  double get _scale => _dragScale ?? widget.pos.s;
  Offset get _center => _dragPos ?? Offset(widget.pos.x, widget.pos.y);

  // ================= 提交 =================

  void _endDrag({required bool commit}) {
    final pos = _dragPos;
    final scale = _dragScale;
    setState(() {
      _dragPos = null;
      _dragScale = null;
    });
    if (!commit) return;
    // 空拖（长按原地松手/拉手碰了下没拖）不回写不触感：省一次无谓落盘。
    final posChanged = pos != null &&
        (pos - Offset(widget.pos.x, widget.pos.y)).distance > 1e-6;
    final scaleChanged =
        scale != null && (scale - widget.pos.s).abs() > 1e-6;
    if (!posChanged && !scaleChanged) return;
    widget.onTransform(posChanged ? pos : null, scaleChanged ? scale : null);
    unawaited(HapticFeedback.selectionClick());
  }

  // ================= 构建 =================

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final ghost = widget.editMode && !widget.pos.v;
    final dragging = _dragPos != null || _dragScale != null;
    final round = widget.pos.shape == RtCanvasButtonShape.circle;

    // 倍率 → 像素规格；圆形取正方形，中心夹回按钮完整在场内。
    final w = round ? kRtCanvasBtnCircleBase * _scale : kRtCanvasBtnBaseW * _scale;
    final h = round ? w : kRtCanvasBtnBaseH * _scale;
    final cx = (_center.dx * widget.canvasSize.width).clamp(
      w / 2,
      widget.canvasSize.width < w ? w / 2 : widget.canvasSize.width - w / 2,
    );
    final cy = (_center.dy * widget.canvasSize.height).clamp(
      h / 2,
      widget.canvasSize.height < h ? h / 2 : widget.canvasSize.height - h / 2,
    );

    final bg = widget.busy ? cs.primary : (ghost ? c.surface.withValues(alpha: 0.4) : c.surface);
    final fg = widget.busy
        ? cs.onPrimary
        : (widget.connected && !ghost ? c.text : c.textMuted);

    Widget button = AnimatedScale(
      scale: dragging ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: w,
        height: h,
        decoration: BoxDecoration(
          shape: round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: round ? null : BorderRadius.circular(14),
          color: bg,
          border: Border.all(
            color: dragging
                ? cs.primary.withValues(alpha: 0.8)
                : ghost
                    ? cs.outlineVariant.withValues(alpha: 0.9)
                    : cs.outlineVariant.withValues(alpha: 0.6),
            width: dragging ? 1.6 : 1,
          ),
          boxShadow: ghost
              ? null
              : [
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
            borderRadius: round ? null : BorderRadius.circular(14),
            customBorder: round ? const CircleBorder() : null,
            onTap: widget.editMode
                ? widget.onToggleVisible // 编辑态：点按 = 显隐切换
                : () => widget.onFire(widget.item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Center(
                child: widget.busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimary,
                        ),
                      )
                    : round
                        ? _circleLabel(fg)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.item.label,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12 * _scale,
                                    height: 1.15,
                                    fontWeight: FontWeight.w600,
                                    color: fg,
                                  ),
                                ),
                              ),
                              if (ghost) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.visibility_off,
                                    size: 12, color: cs.onSurfaceVariant),
                              ],
                            ],
                          ),
              ),
            ),
          ),
        ),
      ),
    );

    return Positioned(
      left: cx - w / 2,
      top: cy - h / 2,
      child: widget.editMode ? _buildEditWrapper(button) : button,
    );
  }

  /// 圆形（手柄键）标签：末位主键的短名（RtKeyDisplay 同表），居中单行。
  /// 隐藏幽灵补一个小 visibility 角标。
  Widget _circleLabel(Color fg) {
    final cs = context.colors.scheme;
    final chord = widget.item.chords.isEmpty
        ? null
        : widget.item.chords.last;
    final keys = (chord == null || chord.keys.isEmpty)
        ? const ['?']
        : chord.keys;
    final short = RtKeyDisplay.labelFor(keys.last);
    final fontSize = switch (short.length) {
      <= 2 => 17.0,
      <= 4 => 13.0,
      _ => 10.5,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          short,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: fontSize * _scale,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
        if (widget.editMode && !widget.pos.v) ...[
          const SizedBox(height: 2),
          Icon(Icons.visibility_off, size: 11, color: cs.onSurfaceVariant),
        ],
      ],
    );
  }

  // ---- 编辑态：直拖移位 + 拉手缩放 ----

  Widget _buildEditWrapper(Widget button) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            HapticFeedback.mediumImpact();
            setState(
              () => _dragPos = Offset(widget.pos.x, widget.pos.y),
            );
          },
          onPanUpdate: (d) {
            setState(() {
              _dragPos = Offset(
                (_dragPos?.dx ?? widget.pos.x) +
                    d.delta.dx / widget.canvasSize.width,
                (_dragPos?.dy ?? widget.pos.y) +
                    d.delta.dy / widget.canvasSize.height,
              );
            });
          },
          onPanEnd: (_) => _endDrag(commit: true),
          onPanCancel: () => _endDrag(commit: false),
          child: button,
        ),
        // 右下缩放拉手：前置于按钮之上，命中优先于移位 pan。
        Positioned(
          right: 2,
          bottom: 2,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              HapticFeedback.mediumImpact();
              setState(() => _dragScale = widget.pos.s);
            },
            onPanUpdate: (d) {
              setState(() {
                // 横向拖动驱动倍率（单轴可控，比双轴好精细操作）。
                _dragScale = (widget.pos.s + d.delta.dx / 160)
                    .clamp(kRtCanvasBtnScaleMin, kRtCanvasBtnScaleMax)
                    .toDouble();
              });
            },
            onPanEnd: (_) => _endDrag(commit: true),
            onPanCancel: () => _endDrag(commit: false),
            child: RtCanvasGripDot(cs: context.colors.scheme),
          ),
        ),
      ],
    );
  }
}

/// 缩放拉手（视觉 22dp，命中区扩到 44dp）。画布层模块缩放同款复用。
class RtCanvasGripDot extends StatelessWidget {
  const RtCanvasGripDot({super.key, required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(color: cs.surface, width: 1.5),
          ),
          child: Icon(Icons.open_in_full, size: 12, color: cs.onPrimary),
        ),
      ),
    );
  }
}
