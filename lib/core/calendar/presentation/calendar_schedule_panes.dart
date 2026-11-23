import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/calendar_lunar.dart';
import '../domain/calendar_task.dart';
import 'calendar_motion.dart';
import 'calendar_palette.dart';

/// 周条：周 / 日页共用的七日条，横向跟手翻周（k300/c28 弹簧）。
class CalendarWeekStrip extends StatefulWidget {
  const CalendarWeekStrip({
    super.key,
    required this.weekBase,
    required this.selectedDate,
    required this.today,
    required this.mondayFirst,
    required this.palette,
    required this.onShift,
    required this.onSelect,
  });

  final DateTime weekBase;
  final DateTime selectedDate;
  final DateTime today;
  final bool mondayFirst;
  final CalendarPalette palette;
  final ValueChanged<DateTime> onShift;
  final ValueChanged<DateTime> onSelect;

  @override
  State<CalendarWeekStrip> createState() => _CalendarWeekStripState();
}

class _CalendarWeekStripState extends State<CalendarWeekStrip>
    with TickerProviderStateMixin {
  late final CalendarSpring _spring;
  final ValueNotifier<double> _t = ValueNotifier<double>(0);
  final CalendarVelocitySampler _velocity = CalendarVelocitySampler();

  double? _startX;
  int _dir = 1;
  DateTime? _shadowBase;
  DateTime? _pendingBase;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _spring = CalendarSpring(
      vsync: this,
      description: kCalendarFlipSpring,
      onUpdate: _onTick,
    );
  }

  @override
  void dispose() {
    _spring.dispose();
    _t.dispose();
    super.dispose();
  }

  void _onTick() {
    _t.value = _spring.value;
    if (_dragging) return;
    if (_spring.value >= 0.999 && _pendingBase != null) {
      final pending = _pendingBase!;
      _spring.stop();
      _spring.jump(0);
      setState(() {
        _shadowBase = null;
        _pendingBase = null;
        _t.value = 0;
      });
      widget.onShift(pending);
    } else if (_spring.value <= 0.001 &&
        _shadowBase != null &&
        _spring.lastToTarget < 0.5) {
      _spring.stop();
      _spring.jump(0);
      setState(() => _shadowBase = null);
    }
  }

  double _width() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) return math.max(1.0, box.size.width);
    return 358;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (d) {
          _startX = d.localPosition.dx;
          _velocity.reset(0);
          if (_spring.isAnimating) {
            _spring.stop();
            _spring.jump(_pendingBase != null ? 1 : 0);
          }
        },
        onHorizontalDragUpdate: (d) {
          if (_startX == null) return;
          final dx = d.localPosition.dx - _startX!;
          _velocity.add(dx);
          if (!_dragging) {
            if (dx.abs() <= 6) return;
            setState(() {
              _dragging = true;
              _dir = dx < 0 ? 1 : -1;
              // shadow 层存目标周（滑入），主层始终是当前周（滑出）。
              _pendingBase = widget.weekBase.add(Duration(days: _dir * 7));
              _shadowBase = _pendingBase;
            });
          }
          _spring.jump(calendarClamp01(dx.abs() / _width()));
        },
        onHorizontalDragEnd: (d) {
          final velocity = (d.primaryVelocity ?? 0) / 1000;
          final proj = calendarProject(_t.value, velocity.abs(), _width());
          _dragging = false;
          _startX = null;
          if (_pendingBase != null && (proj > 0.5 || velocity.abs() > 0.35)) {
            _spring.to(1, velocity: velocity.abs() * _width());
          } else {
            _spring.to(0);
          }
        },
        child: SizedBox(
          height: 66,
          child: ValueListenableBuilder<double>(
            valueListenable: _t,
            builder: (context, t, _) {
              final width = _width();
              return Stack(
                children: [
                  // shadow：待进入的周，从翻页方向对侧滑入
                  // （t 0→1 时 offset dir*w*(1-t)：+w → 0）。
                  if (_shadowBase != null)
                    Positioned.fill(
                      child: Transform.translate(
                        offset: Offset(_dir * width * (1 - t), 0),
                        child: _week(_shadowBase!),
                      ),
                    ),
                  // 主层：当前周，翻页时向方向侧滑出
                  // （offset -dir*w*t：0 → -w）；静止态 t=0 → 0，原位可见。
                  Positioned.fill(
                    child: Transform.translate(
                      offset: Offset(-_dir * width * t, 0),
                      child: _week(widget.weekBase),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _week(DateTime base) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: _WeekCell(
                date: base.add(Duration(days: i)),
                selectedDate: widget.selectedDate,
                today: widget.today,
                palette: widget.palette,
                onTap: () => widget.onSelect(base.add(Duration(days: i))),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekCell extends StatefulWidget {
  const _WeekCell({
    required this.date,
    required this.selectedDate,
    required this.today,
    required this.palette,
    required this.onTap,
  });

  final DateTime date;
  final DateTime selectedDate;
  final DateTime today;
  final CalendarPalette palette;
  final VoidCallback onTap;

  @override
  State<_WeekCell> createState() => _WeekCellState();
}

class _WeekCellState extends State<_WeekCell> {
  bool _pressed = false;

  bool get isToday =>
      widget.date.year == widget.today.year &&
      widget.date.month == widget.today.month &&
      widget.date.day == widget.today.day;

  bool get isSelected =>
      widget.date.year == widget.selectedDate.year &&
      widget.date.month == widget.selectedDate.month &&
      widget.date.day == widget.selectedDate.day;

  @override
  Widget build(BuildContext context) {
    final date = widget.date;
    final palette = widget.palette;
    final sub = calendarLunarSubLabel(date);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? palette.accentSoft.withValues(alpha: 0.45) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: _pressed ? 0.86 : 1,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutBack,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: isToday
                      ? Border.all(color: palette.danger, width: 1.5)
                      : null,
                ),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 17,
                    height: 1,
                    fontWeight: isToday || isSelected
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: isToday
                        ? palette.danger
                        : (isSelected ? palette.accent : palette.textPrimary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 1),
            if (sub != null)
              Text(
                sub.$1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1,
                  color: isToday
                      ? palette.danger
                      : (sub.$2 ? palette.accent : palette.textSecondary),
                  fontWeight: sub.$2 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 全天任务条（周页顶部）。
class CalendarAllDayChips extends StatelessWidget {
  const CalendarAllDayChips({
    super.key,
    required this.days,
    required this.palette,
  });

  final List<List<CalendarTask>> days;
  final CalendarPalette palette;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    for (final list in days) {
      for (final task in list) {
        if (!task.allDay) continue;
        chips.add(_chip(task));
      }
    }
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Text(
            '全天',
            style: TextStyle(fontSize: 11, color: palette.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: chips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) => chips[index],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(CalendarTask task) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: calendarTaskColor(
          task.colorValue,
          task.id,
        ).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: palette.textPrimary),
      ),
    );
  }
}

/// 时间轴：06:00–24:00 行网格 + 绝对定位事件块（周 = 7 列 / 日 = 1 列）。
class CalendarTimeline extends StatelessWidget {
  const CalendarTimeline({
    super.key,
    required this.days,
    required this.showNowLine,
    required this.palette,
    required this.onToggle,
    this.dayDates = const [],
    this.onCreateAt,
    this.onResize,
  });

  /// 1 列（日）或 7 列（周）。
  final List<List<CalendarTask>> days;

  /// 每列对应日期（空白处点按换算用），长度与 [days] 一致时才生效。
  final List<DateTime> dayDates;

  /// 日页且选中日为今天时为 true（画「现在」线）。
  final bool showNowLine;
  final CalendarPalette palette;
  final ValueChanged<CalendarTask> onToggle;

  /// 点按空白：返回四舍五入到 30 分钟的起始时刻。
  final ValueChanged<DateTime>? onCreateAt;

  /// 拖拽任务块上下边缘改时长后回调。
  final void Function(CalendarTask task, DateTime start, DateTime end)?
  onResize;

  static const double _startHour = 6;
  static const double _rowHeight = 52;
  static const int _hours = 18;
  static const double _labelWidth = 38;

  @override
  Widget build(BuildContext context) {
    final cols = days.length;
    return SingleChildScrollView(
      // 底部留出悬浮底栏 / 系统手势区的可滚余量：FAB 底边约在屏底上方
      // 88px（72 padding + 16 悬浮）+ ~20px 阴影，132 保证末尾事件与
      // 按钮阴影之间仍有呼吸感。
      padding: const EdgeInsets.only(bottom: 132),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.max(
            1.0,
            constraints.maxWidth - _labelWidth,
          );
          final colWidth = contentWidth / cols;
          final events = <Widget>[];
          for (var c = 0; c < cols; c++) {
            // 泳道分栏：同列时间重叠的事件并排铺开，而不是叠画互相盖住。
            final lanes = layoutTimelineLanes(days[c]);
            for (final layout in lanes) {
              final task = layout.task;
              final top =
                  (task.start.hour - _startHour) * _rowHeight +
                  task.start.minute / 60 * _rowHeight;
              final end = task.end ?? task.start.add(const Duration(hours: 1));
              final bottom =
                  (end.hour - _startHour) * _rowHeight +
                  end.minute / 60 * _rowHeight;
              final height = math.max(26.0, bottom - top - 2);
              // 列内先按泳道数均分，再扣泳道间 2px 缝。
              final slot =
                  (colWidth - 6 - (layout.lanes - 1) * 2) / layout.lanes;
              final width = math.max(12.0, slot);
              events.add(
                _TimelineEvent(
                  key: ValueKey(task.id),
                  task: task,
                  left:
                      _labelWidth +
                      c * colWidth +
                      3 +
                      layout.lane * (width + 2),
                  width: width,
                  top: top,
                  height: height,
                  dense: cols > 1,
                  palette: palette,
                  color: calendarTaskColor(task.colorValue, task.id),
                  onTap: () => onToggle(task),
                  onResize: onResize,
                ),
              );
            }
          }
          final nowLine = _nowLineOrNull();
          if (nowLine != null) events.add(nowLine);

          final createAt = onCreateAt;
          return SizedBox(
            height: _hours * _rowHeight,
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: createAt == null
                      ? null
                      : (d) {
                          final dx = d.localPosition.dx - _labelWidth;
                          if (dx < 0) return;
                          final col = (dx / colWidth).floor().clamp(
                            0,
                            cols - 1,
                          );
                          if (dayDates.length != cols) return;
                          final date = dayDates[col];
                          final rawMinutes =
                              _startHour * 60 +
                              d.localPosition.dy / _rowHeight * 60;
                          final minutes = ((rawMinutes / 30).round() * 30)
                              .clamp(
                                _startHour.toInt() * 60,
                                (_startHour.toInt() + _hours) * 60 - 30,
                              )
                              .toInt();
                          createAt(
                            DateTime(
                              date.year,
                              date.month,
                              date.day,
                            ).add(Duration(minutes: minutes)),
                          );
                        },
                  child: Column(
                    children: [
                      for (var h = 0; h < _hours; h++)
                        Container(
                          height: _rowHeight,
                          decoration: BoxDecoration(
                            border: h == 0
                                ? null
                                : Border(
                                    top: BorderSide(
                                      color: palette.divider,
                                      width: 0.6,
                                    ),
                                  ),
                          ),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: _labelWidth,
                              child: Transform.translate(
                                offset: const Offset(0, -6),
                                child: Text(
                                  '${(_startHour.toInt() + h).toString().padLeft(2, '0')}:00',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: palette.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ...events,
              ],
            ),
          );
        },
      ),
    );
  }

  /// 泳道分栏（Google Calendar 同款口径）：
  /// 1. 按开始时间排序，切成互不重叠的「簇」（新事件开始 ≥ 簇内最晚结束 → 开新簇）；
  /// 2. 簇内贪心分配泳道（第一个空闲泳道），同簇事件等宽并排。
  /// 全天任务由调用方过滤，这里只处理时间轴任务。
  @visibleForTesting
  static List<TimelineLane> layoutTimelineLanes(List<CalendarTask> tasks) {
    final timed = [...tasks.where((t) => !t.allDay)]
      ..sort((a, b) {
        final c = a.start.compareTo(b.start);
        if (c != 0) return c;
        return (a.end ?? a.start.add(const Duration(hours: 1))).compareTo(
          b.end ?? b.start.add(const Duration(hours: 1)),
        );
      });

    final out = <TimelineLane>[];
    var cluster = <CalendarTask>[];
    var clusterEnd = DateTime.fromMillisecondsSinceEpoch(0);

    void flush() {
      if (cluster.isEmpty) return;
      final laneEnds = <DateTime>[];
      final laneOf = <CalendarTask, int>{};
      for (final t in cluster) {
        final end = t.end ?? t.start.add(const Duration(hours: 1));
        var lane = 0;
        while (lane < laneEnds.length && laneEnds[lane].isAfter(t.start)) {
          lane++;
        }
        if (lane == laneEnds.length) laneEnds.add(end);
        laneEnds[lane] = end;
        laneOf[t] = lane;
      }
      for (final t in cluster) {
        out.add(TimelineLane(t, laneOf[t]!, laneEnds.length));
      }
      cluster = <CalendarTask>[];
      clusterEnd = DateTime.fromMillisecondsSinceEpoch(0);
    }

    for (final t in timed) {
      final end = t.end ?? t.start.add(const Duration(hours: 1));
      if (cluster.isNotEmpty && !t.start.isBefore(clusterEnd)) flush();
      cluster.add(t);
      if (end.isAfter(clusterEnd)) clusterEnd = end;
    }
    flush();
    return out;
  }

  Widget? _nowLineOrNull() {
    if (!showNowLine) return null;
    final now = DateTime.now();
    final top =
        (now.hour - _startHour) * _rowHeight + now.minute / 60 * _rowHeight;
    if (top < 0) return null;
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 原型 .tl-now：1.5px 柿朱横线 + 左端 8px 圆点（原 height:0 不画线）。
            Container(height: 1.5, color: palette.danger),
            Transform.translate(
              offset: const Offset(34, -4),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: palette.danger,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 时间轴事件块：点按切换完成；上下边缘的圆点可拖拽调整起止时间。
///
/// 拖拽全程 1:1 跟手，位移在**拖动中就实时吸附到 15 分钟网格**（块体
/// 以吸附后的几何渲染，松手即所见即所得，无松手瞬间跳变）；拖动时
/// 被拖边缘旁显示时间气泡。回写后父级用新任务重建，didUpdateWidget
/// 以几何变化为准清零本地位移；若回写失败（toast 报错）则由兜底
/// 定时器复位假位置。
class _TimelineEvent extends StatefulWidget {
  const _TimelineEvent({
    super.key,
    required this.task,
    required this.left,
    required this.width,
    required this.top,
    required this.height,
    required this.dense,
    required this.palette,
    required this.color,
    required this.onTap,
    required this.onResize,
  });

  final CalendarTask task;
  final double left;
  final double width;
  final double top;
  final double height;
  final bool dense;
  final CalendarPalette palette;
  final Color color;
  final VoidCallback onTap;
  final void Function(CalendarTask task, DateTime start, DateTime end)?
  onResize;

  @override
  State<_TimelineEvent> createState() => _TimelineEventState();
}

class _TimelineEventState extends State<_TimelineEvent> {
  static const double _minHeight = 26;
  static const int _snapMinutes = 15;
  static const double _handleZone = 14;

  double _adjustTop = 0;
  double _adjustBottom = 0;
  bool _dragging = false;

  /// 本次拖拽正在动的边缘（null = 未拖拽）。时间气泡按它定位。
  bool? _dragTopEdge;
  Timer? _resetFallback;

  @override
  void didUpdateWidget(covariant _TimelineEvent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.top != widget.top ||
        oldWidget.height != widget.height ||
        oldWidget.task.start != widget.task.start ||
        oldWidget.task.end != widget.task.end) {
      _adjustTop = 0;
      _adjustBottom = 0;
      _resetFallback?.cancel();
    }
  }

  @override
  void dispose() {
    _resetFallback?.cancel();
    super.dispose();
  }

  double get _gridHeight =>
      CalendarTimeline._hours * CalendarTimeline._rowHeight;

  /// 15 分钟网格吸附（px 口径）。
  double _snapPx(double px) {
    final minutes = px / CalendarTimeline._rowHeight * 60;
    final snapped = (minutes / _snapMinutes).round() * _snapMinutes;
    return snapped / 60 * CalendarTimeline._rowHeight;
  }

  /// 拖拽中的吸附显示几何：[displayTop, displayBottom]。
  /// 拖上缘时吸附顶边、拖下缘时吸附底边，另一侧保持；吸附后不足
  /// 最小高度或越出网格时把被拖侧钳回来。
  (double, double) _displayGeometry() {
    var top = widget.top + _adjustTop;
    var bottom = widget.top + widget.height + _adjustBottom;
    if (_dragging && _dragTopEdge != null) {
      if (_dragTopEdge!) {
        top = _snapPx(top).clamp(0.0, bottom - _minHeight);
      } else {
        bottom = _snapPx(bottom).clamp(top + _minHeight, _gridHeight);
      }
    }
    return (top.clamp(0.0, _gridHeight), bottom.clamp(0.0, _gridHeight));
  }

  void _dragStart(bool topEdge) {
    _dragging = true;
    _dragTopEdge = topEdge;
  }

  void _dragUpdate(bool topEdge, DragUpdateDetails d) {
    setState(() {
      if (topEdge) {
        final maxTop = widget.height + _adjustBottom - _minHeight;
        _adjustTop = (_adjustTop + d.delta.dy).clamp(-widget.top, maxTop);
      } else {
        final minBottom = _minHeight - widget.height + _adjustTop;
        final maxBottom = _gridHeight - widget.top - widget.height - _adjustTop;
        _adjustBottom = (_adjustBottom + d.delta.dy).clamp(
          minBottom,
          maxBottom,
        );
      }
    });
  }

  void _dragEnd() {
    if (!_dragging) return;
    // 先取吸附后的显示几何（依赖 _dragging/_dragTopEdge 标记），再清标记。
    final (top, bottom) = _displayGeometry();
    _dragging = false;
    _dragTopEdge = null;
    // 本地偏移固化成吸附后几何：回写往返期间块体停在松手所见位置，
    // 不闪回未吸附的旧值。
    _adjustTop = top - widget.top;
    _adjustBottom = bottom - (widget.top + widget.height);
    setState(() {});
    final base = DateTime(
      widget.task.start.year,
      widget.task.start.month,
      widget.task.start.day,
    );
    DateTime at(double px) {
      final minutes = px / CalendarTimeline._rowHeight * 60;
      final snapped = (minutes / _snapMinutes).round() * _snapMinutes;
      return base.add(
        Duration(minutes: CalendarTimeline._startHour.toInt() * 60 + snapped),
      );
    }

    final start = at(top);
    final end = at(bottom);
    // 几何没变（原地点了一下边缘）就不打扰仓储。
    if (start == widget.task.start && end == (widget.task.end ?? start)) {
      if (_adjustTop != 0 || _adjustBottom != 0) {
        setState(() {
          _adjustTop = 0;
          _adjustBottom = 0;
        });
      }
      return;
    }
    widget.onResize?.call(widget.task, start, end);
    // 回写失败（或写入丢失）兜底：600ms 内父级没带来新几何就复位，
    // 不让块体停在拖拽后的假位置。
    _resetFallback?.cancel();
    _resetFallback = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      if (_adjustTop != 0 || _adjustBottom != 0) {
        setState(() {
          _adjustTop = 0;
          _adjustBottom = 0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final (displayTop, displayBottom) = _displayGeometry();
    final top = displayTop;
    final height = math.max(_minHeight, displayBottom - displayTop);
    final canResize = widget.onResize != null && !widget.task.completed;
    final showTime = !widget.dense && height >= 42;
    // 短事件也给手柄：命中条高度压到块高一半以内，圆点只在块足够高时
    // 画（避免压住标题文字）；低块整条边缘就是拖拽热区。
    final zoneH = math.min(_handleZone, height / 2);

    return Positioned(
      left: widget.left,
      width: widget.width,
      top: top,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: widget.dense ? 3 : 4,
                ),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(color: widget.color, width: 3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.task.title,
                      maxLines: showTime ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: widget.dense ? 10.5 : 12,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (showTime)
                      Text(
                        '${widget.task.start.hour.toString().padLeft(2, '0')}:'
                        '${widget.task.start.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.2,
                          color: palette.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // 拖拽中的时间气泡：贴被拖边缘内侧，显示吸附后的时刻。
          if (_dragging && _dragTopEdge != null)
            Positioned(
              top: _dragTopEdge! ? 2 : null,
              bottom: _dragTopEdge! ? null : 2,
              right: 2,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _bubbleText(displayTop, displayBottom, _dragTopEdge!),
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: palette.background,
                    ),
                  ),
                ),
              ),
            ),
          if (canResize) ...[
            // 手柄贴块内边缘：Positioned 超出父盒的部分不参与命中测试，
            // 放在块内才能稳定抢到纵向拖拽。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: zoneH,
              child: Center(child: _handle(true, height >= 30)),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: zoneH,
              child: Center(child: _handle(false, height >= 30)),
            ),
          ],
        ],
      ),
    );
  }

  /// 气泡文案：拖上缘显示新开始时刻，拖下缘显示新结束时刻。
  String _bubbleText(double top, double bottom, bool topEdge) {
    final px = topEdge ? top : bottom;
    final minutes =
        (px / CalendarTimeline._rowHeight * 60).round() +
        CalendarTimeline._startHour.toInt() * 60;
    final clamped = minutes.clamp(0, 24 * 60 - 1);
    return '${(clamped ~/ 60).toString().padLeft(2, '0')}:'
        '${(clamped % 60).toString().padLeft(2, '0')}';
  }

  Widget _handle(bool topEdge, bool showDot) {
    return GestureDetector(
      key: ValueKey(
        'timeline-resize-${topEdge ? 'start' : 'end'}-${widget.task.id}',
      ),
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => _dragStart(topEdge),
      onVerticalDragUpdate: (d) => _dragUpdate(topEdge, d),
      onVerticalDragEnd: (_) => _dragEnd(),
      onVerticalDragCancel: () => _dragEnd(),
      child: SizedBox.expand(
        // 短事件不画圆点（会压住标题），整条边缘就是拖拽热区。
        child: showDot
            ? Center(
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.palette.overlay,
                    border: Border.all(color: widget.color, width: 1.5),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// 泳道布局结果：任务 + 在簇内的泳道号 / 簇内总泳道数。
class TimelineLane {
  const TimelineLane(this.task, this.lane, this.lanes);

  final CalendarTask task;
  final int lane;
  final int lanes;
}

/// 日程页：未来两周按天分组。
class CalendarAgendaPane extends StatelessWidget {
  const CalendarAgendaPane({
    super.key,
    required this.groups,
    required this.today,
    required this.palette,
    required this.loading,
    required this.storageAvailable,
    this.storageMessage,
    this.onRetry,
    required this.onToggle,
    required this.onDelete,
  });

  final List<MapEntry<DateTime, List<CalendarTask>>> groups;
  final DateTime today;
  final CalendarPalette palette;
  final bool loading;
  final bool storageAvailable;
  final String? storageMessage;
  final VoidCallback? onRetry;
  final ValueChanged<CalendarTask> onToggle;
  final ValueChanged<CalendarTask> onDelete;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: palette.accent,
          ),
        ),
      );
    }
    if (!storageAvailable) {
      return Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Text(
          storageMessage ?? '本地数据库未就绪',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: palette.textSecondary),
        ),
      );
    }
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_cafe_outlined,
              size: 44,
              color: palette.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              '未来两周还没有日程',
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              '休息，也是日程',
              style: TextStyle(
                fontSize: 11,
                color: palette.textSecondary.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 116),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = groups[index];
        final day = entry.key;
        final diff = day.difference(today).inDays;
        final rel = diff == 0
            ? '今天'
            : (diff == 1 ? '明天' : (diff == -1 ? '昨天' : null));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 2),
              child: Row(
                children: [
                  if (rel != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        rel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: palette.accent,
                        ),
                      ),
                    ),
                  Text(
                    '${day.month}月${day.day}日',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '星期${'一二三四五六日'[day.weekday - DateTime.monday]}',
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            for (final task in entry.value)
              _AgendaRow(
                task: task,
                palette: palette,
                onToggle: () => onToggle(task),
                onDelete: () => onDelete(task),
              ),
          ],
        );
      },
    );
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.task,
    required this.palette,
    required this.onToggle,
    required this.onDelete,
  });

  final CalendarTask task;
  final CalendarPalette palette;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = calendarTaskColor(task.colorValue, task.id);
    final timeLabel = task.allDay
        ? '全天'
        : '${task.start.hour.toString().padLeft(2, '0')}:'
              '${task.start.minute.toString().padLeft(2, '0')} – '
              '${(task.end ?? task.start).hour.toString().padLeft(2, '0')}:'
              '${(task.end ?? task.start).minute.toString().padLeft(2, '0')}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onDelete,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Container(
                width: 21,
                height: 21,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: task.completed ? palette.accent : null,
                  border: task.completed
                      ? null
                      : Border.all(color: palette.divider, width: 1.5),
                ),
                child: task.completed
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: task.completed
                          ? palette.completed
                          : palette.textPrimary,
                      decoration: task.completed
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
