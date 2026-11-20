// 日历任务面板：浮在日历之上的下拉面板（列表视图用）。
//
// 面板关系参考 Lab 容器的下拉面板：主内容（日历）在后景，任务面板**覆盖**
// 在前景——圆角顶部 + 把手 + 阴影，拖把手在「收起 / 展开」两态间吸附。
// **默认展开**：进来任务面板是主内容，日历缩为后景（页面按 progress 做
// 后景变换）；下拉把手才露出完整日历。
//
// 高度进度（0 收起 / 1 展开）写在页面持有的 [progress] notifier 上，
// 页面据此联动日历层变换与 FAB 显隐——面板自身只管高度与内容。
//
// 拖拽只发生在把手区：面板内的任务列表照常滚动，两者不抢手势。

import 'package:flutter/material.dart';

import 'calendar_palette.dart';

class CalendarTaskPanel extends StatefulWidget {
  const CalendarTaskPanel({
    super.key,
    required this.palette,
    required this.progress,
    required this.child,
    required this.headerLabel,
    this.headerTrailing,
    this.expandedRatio = 0.72,
    this.collapsedRatio = 0.26,
  });

  final CalendarPalette palette;

  /// 高度进度（0 = 收起，1 = 展开）。页面持有，面板写值，
  /// 页面的日历后景变换与 FAB 显隐随之联动。
  final ValueNotifier<double> progress;

  /// 面板主体（任务列表）。
  final Widget child;

  /// 面板头部标题（通常是「当前日期 · 星期」）。
  final String headerLabel;

  /// 头部右侧附加信息（任务数等）。
  final Widget? headerTrailing;

  /// 展开态高度 = 可用高 × 此比例。
  final double expandedRatio;

  /// 收起态高度 = 展开高 × 此比例。
  final double collapsedRatio;

  @override
  State<CalendarTaskPanel> createState() => _CalendarTaskPanelState();
}

class _CalendarTaskPanelState extends State<CalendarTaskPanel> {
  double _dragStartHeight = 0;
  bool _dragging = false;

  /// 本帧进度镜像（AnimatedContainer 的动画时长按是否拖拽切换）。
  double get _progress => widget.progress.value;

  static const double _handleAreaHeight = 34;

  double _collapsedHeight(double maxHeight) =>
      (maxHeight * widget.expandedRatio * widget.collapsedRatio).clamp(
        96.0,
        maxHeight * 0.5,
      );

  double _expandedHeight(double maxHeight) => maxHeight * widget.expandedRatio;

  void _onDragStart(DragStartDetails details, double maxHeight) {
    _dragging = true;
    _dragStartHeight = _currentHeight(maxHeight);
  }

  void _onDragUpdate(DragUpdateDetails details, double maxHeight) {
    final collapsed = _collapsedHeight(maxHeight);
    final expanded = _expandedHeight(maxHeight);
    final range = expanded - collapsed;
    if (range <= 0) return;
    final next = _dragStartHeight - details.delta.dy;
    widget.progress.value = ((next - collapsed) / range).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    // 快速上滑/下滑优先按速度定档，否则按当前进度过半定档。
    final target = velocity < -350
        ? 1.0
        : velocity > 350
            ? 0.0
            : (_progress > 0.5 ? 1.0 : 0.0);
    _settle(target);
  }

  void _settle(double target) {
    widget.progress.value = target;
  }

  void _toggle() {
    _settle(_progress > 0.5 ? 0.0 : 1.0);
  }

  double _currentHeight(double maxHeight) {
    final collapsed = _collapsedHeight(maxHeight);
    final expanded = _expandedHeight(maxHeight);
    return collapsed + (expanded - collapsed) * _progress;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final collapsed = _collapsedHeight(maxHeight);
        final expanded = _expandedHeight(maxHeight);

        return ValueListenableBuilder<double>(
          valueListenable: widget.progress,
          builder: (context, progress, _) {
            final height = collapsed + (expanded - collapsed) * progress;
            return Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedContainer(
                duration: _dragging
                    ? Duration.zero
                    : const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                height: height,
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: palette.shadow,
                      blurRadius: 24,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    // 把手区：拖这里改高度；点一下切换展开/收起。
                    GestureDetector(
                      key: const ValueKey('calendar-panel-handle'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggle,
                      onVerticalDragStart: (d) => _onDragStart(d, maxHeight),
                      onVerticalDragUpdate: (d) => _onDragUpdate(d, maxHeight),
                      onVerticalDragEnd: _onDragEnd,
                      child: SizedBox(
                        height: _handleAreaHeight,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: palette.divider,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 头部信息行：当前日期 + 任务数（面板自己的标题，语义闭合）。
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.headerLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.textSecondary,
                              ),
                            ),
                          ),
                          if (widget.headerTrailing != null)
                            widget.headerTrailing!,
                        ],
                      ),
                    ),
                    Expanded(child: widget.child),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
