import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/calendar_date_utils.dart';
import '../domain/calendar_lunar.dart';
import '../domain/calendar_task.dart';
import 'calendar_motion.dart';
import 'calendar_palette.dart';
import 'calendar_task_list.dart';

/// 月视图：双态（收起 = 单周行 + 任务面板 / 展开 = 整月网格）+
/// 纵向跟手收展（k205/c29 弹簧吸附 + 指数阻力）+ 横向翻月轮盘。
class CalendarMonthPane extends StatefulWidget {
  const CalendarMonthPane({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.today,
    required this.markedDates,
    required this.mondayFirst,
    required this.palette,
    required this.collapse,
    required this.tasks,
    required this.loading,
    required this.storageAvailable,
    this.storageMessage,
    required this.onCollapseDrive,
    required this.onCollapseSettle,
    required this.onFlipCommit,
    required this.onSelect,
    required this.onToggleTask,
    required this.onDeleteTask,
    this.onRetryStorage,
    this.gridAreaKey,
  });

  final DateTime month;
  final DateTime selectedDate;
  final DateTime today;
  final Set<String> markedDates;
  final bool mondayFirst;
  final CalendarPalette palette;

  /// 0..1 之外的值保留（拖拽越界时映射为阻力位移）。
  final ValueListenable<double> collapse;
  final List<CalendarTask> tasks;
  final bool loading;
  final bool storageAvailable;
  final String? storageMessage;
  final ValueChanged<double> onCollapseDrive;
  final void Function(double target, double velocity) onCollapseSettle;
  final ValueChanged<DateTime> onFlipCommit;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<CalendarTask> onToggleTask;
  final ValueChanged<CalendarTask> onDeleteTask;
  final VoidCallback? onRetryStorage;

  /// 月历网格区（weekday 表头之下、抓手之上）的 key，供容器变换
  /// 测量终态矩形——对应原型的 #mArea，不含周条/任务面板。
  final GlobalKey? gridAreaKey;

  @override
  State<CalendarMonthPane> createState() => _CalendarMonthPaneState();
}

class _CalendarMonthPaneState extends State<CalendarMonthPane>
    with TickerProviderStateMixin {
  late CalendarSpring _flipSpring;
  final ValueNotifier<double> _flipT = ValueNotifier<double>(0);
  final CalendarVelocitySampler _velocity = CalendarVelocitySampler();

  double? _dragStart;
  double _collapseBase = 1;
  double? _flipStart;
  int _flipDir = 1;
  DateTime? _shadowMonth;
  DateTime? _pendingMonth;
  bool _flipDragging = false;
  bool _collapseDragging = false;

  int get _rows => _rowsFor(widget.month);
  double get _monthHeight => _rows * kCalendarRowHeight;
  double get _range => math.max(1.0, _monthHeight - kCalendarRowHeight);

  int _rowsFor(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final start =
        calendarWeekStart(first, mondayFirst: widget.mondayFirst);
    final offset = first.difference(start).inDays;
    return ((offset + calendarDaysInMonth(month.year, month.month)) / 7)
        .ceil();
  }

  @override
  void initState() {
    super.initState();
    _flipSpring = CalendarSpring(
      vsync: this,
      description: kCalendarFlipSpring,
      onUpdate: _onFlipTick,
    );
  }

  @override
  void dispose() {
    _flipSpring.dispose();
    _flipT.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CalendarMonthPane old) {
    super.didUpdateWidget(old);
    if (widget.month != old.month) {
      // 翻月提交后的外部状态变更：轮盘复位。
      if (_pendingMonth != null && !_flipDragging) {
        _flipSpring.stop();
        _flipSpring.jump(0);
        _shadowMonth = null;
        _pendingMonth = null;
        _flipT.value = 0;
      }
    }
  }

  void _onFlipTick() {
    _flipT.value = _flipSpring.value;
    if (_flipDragging) return;
    if (_flipSpring.value >= 0.999 && _pendingMonth != null) {
      final pending = _pendingMonth!;
      _flipSpring.stop();
      _flipSpring.jump(0);
      _shadowMonth = null;
      _pendingMonth = null;
      _flipT.value = 0;
      widget.onFlipCommit(pending);
    } else if (_flipSpring.value <= 0.001 &&
        _shadowMonth != null &&
        _flipSpring.lastToTarget < 0.5) {
      _flipSpring.stop();
      _flipSpring.jump(0);
      setState(() {
        _shadowMonth = null;
        _pendingMonth = null; // 未过阈值回弹：清掉残留目标，防后续误 commit。
      });
    }
  }

  /* ───────────── 纵向：收起 / 展开 ───────────── */

  void _onVerticalStart(DragStartDetails d) {
    _collapseDragging = true;
    _dragStart = d.localPosition.dy;
    _collapseBase = widget.collapse.value;
    _velocity.reset(0);
    if (!_flipDragging && _flipSpring.isAnimating) {
      _flipSpring.stop();
      _flipSpring.jump(_pendingMonth != null ? 1 : 0);
    }
  }

  void _onVerticalUpdate(DragUpdateDetails d) {
    final startY = _dragStart;
    if (startY == null) return;
    final dy = d.localPosition.dy - startY;
    if (dy.abs() <= kCalendarDragDeadZone && !_collapseDragging) return;
    final drive = dy > 0
        ? dy - kCalendarDragDeadZone
        : dy + kCalendarDragDeadZone;
    _velocity.add(dy);
    widget.onCollapseDrive(_collapseBase + drive / _range);
  }

  void _onVerticalEnd(DragEndDetails d) {
    if (!_collapseDragging) return;
    _collapseDragging = false;
    _dragStart = null;
    final velocity = (d.primaryVelocity ?? 0) / 1000; // px/ms，向下为正
    final proj = calendarProject(_collapseBase, velocity, _range);
    final threshold = _collapseBase > 0.5 ? 0.88 : 0.12;
    widget.onCollapseSettle(
      proj > threshold ? 1 : 0,
      velocity * 1000 / _range,
    );
  }

  void _toggleCollapse() {
    final raw = calendarClamp01(widget.collapse.value);
    widget.onCollapseSettle(raw > 0.5 ? 0 : 1, 0);
  }

  /* ───────────── 横向：翻月轮盘 ───────────── */

  void _onHorizontalStart(DragStartDetails d) {
    _flipStart = d.localPosition.dx;
    _velocity.reset(0);
    if (_flipSpring.isAnimating) {
      _flipSpring.stop();
      _flipSpring.jump(_pendingMonth != null ? 1 : 0);
    }
  }

  void _onHorizontalUpdate(DragUpdateDetails d) {
    final startX = _flipStart;
    if (startX == null) return;
    final dx = d.localPosition.dx - startX;
    _velocity.add(dx);
    final width = _areaWidth();
    if (!_flipDragging) {
      if (dx.abs() <= 6) return;
      setState(() {
        _flipDragging = true;
        _flipDir = dx < 0 ? 1 : -1;
        // shadow = 待进入的目标月（从对侧滑入）；当前月由主层滑出。
        _shadowMonth = DateTime(
          widget.month.year,
          widget.month.month + _flipDir,
          1,
        );
        _pendingMonth = _shadowMonth;
      });
    }
    _flipSpring.jump(calendarClamp01(dx.abs() / width));
  }

  void _onHorizontalEnd(DragEndDetails d) {
    final width = _areaWidth();
    final velocity = (d.primaryVelocity ?? 0) / 1000;
    final proj = calendarProject(_flipT.value, velocity.abs(), width);
    _flipDragging = false;
    _flipStart = null;
    if (_pendingMonth != null && (proj > 0.5 || velocity.abs() > 0.35)) {
      _flipSpring.to(1, velocity: velocity.abs() * width);
    } else {
      _flipSpring.to(0);
    }
  }

  double _areaWidth() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return math.max(1.0, box.size.width);
    }
    return 358;
  }

  /* ───────────── 渲染 ───────────── */

  @override
  Widget build(BuildContext context) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final header = widget.mondayFirst
        ? weekdays
        : ['日', ...weekdays.sublist(0, 6)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
          child: Row(
            children: [
              for (final w in header)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.palette.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 月历区：高度随收展弹簧联动，内部支持纵向收展 / 横向翻月。
        ValueListenableBuilder<double>(
          valueListenable: widget.collapse,
          builder: (context, raw, _) {
            final p = calendarClamp01(raw);
            final height =
                kCalendarRowHeight + (_monthHeight - kCalendarRowHeight) * p;
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart: _onVerticalStart,
              onVerticalDragUpdate: _onVerticalUpdate,
              onVerticalDragEnd: _onVerticalEnd,
              onHorizontalDragStart: _onHorizontalStart,
              onHorizontalDragUpdate: _onHorizontalUpdate,
              onHorizontalDragEnd: _onHorizontalEnd,
              child: ClipRect(
                child: SizedBox(
                  key: widget.gridAreaKey,
                  height: height,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _flipT,
                    builder: (context, flip, _) {
                      final width = math.max(1.0, _areaWidth());
                      return Stack(
                        children: [
                          // shadow：待进入的月份，从翻页方向对侧滑入
                          // （flip 0→1 时 offset dir*w*(1-flip)：+w → 0）。
                          if (_shadowMonth != null)
                            Positioned.fill(
                              child: Transform.translate(
                                offset:
                                    Offset(_flipDir * width * (1 - flip), 0),
                                child: CalendarMonthGridContent(
                                  month: _shadowMonth!,
                                  selectedDate: widget.selectedDate,
                                  today: widget.today,
                                  markedDates: widget.markedDates,
                                  mondayFirst: widget.mondayFirst,
                                  palette: widget.palette,
                                  collapse: raw,
                                  ignoreDayTap: true,
                                ),
                              ),
                            ),
                          // 主层：当前月份，翻页时向方向侧滑出
                          // （flip 0→1 时 offset -dir*w*flip：0 → -w）；
                          // 静止态 flip=0 → offset 0，网格原位可见。
                          Positioned.fill(
                            child: Transform.translate(
                              offset: Offset(-_flipDir * width * flip, 0),
                              child: CalendarMonthGridContent(
                                month: widget.month,
                                selectedDate: widget.selectedDate,
                                today: widget.today,
                                markedDates: widget.markedDates,
                                mondayFirst: widget.mondayFirst,
                                palette: widget.palette,
                                collapse: raw,
                                onDayTap: widget.onSelect,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        // 抓手：点按切换收展，拖拽跟手。
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleCollapse,
          onVerticalDragStart: _onVerticalStart,
          onVerticalDragUpdate: _onVerticalUpdate,
          onVerticalDragEnd: _onVerticalEnd,
          child: SizedBox(
            height: 40,
            child: ValueListenableBuilder<double>(
              valueListenable: widget.collapse,
              builder: (context, raw, _) {
                final p = calendarClamp01(raw);
                return Center(
                  child: Transform.rotate(
                    angle: math.pi * (1 - p),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 22,
                      color: widget.palette.textSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // 任务面板（月页固有下半区）：点按/拖拽均可切换收展。
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleCollapse,
          onVerticalDragStart: _onVerticalStart,
          onVerticalDragUpdate: _onVerticalUpdate,
          onVerticalDragEnd: _onVerticalEnd,
          child: _TaskPanelHeader(
            selectedDate: widget.selectedDate,
            tasks: widget.tasks,
            palette: widget.palette,
          ),
        ),
        Expanded(
          child: CalendarTaskList(
            tasks: widget.tasks,
            loading: widget.loading,
            palette: widget.palette,
            storageAvailable: widget.storageAvailable,
            storageMessage: widget.storageMessage,
            onRetry: widget.onRetryStorage,
            onToggle: widget.onToggleTask,
            onDelete: widget.onDeleteTask,
          ),
        ),
      ],
    );
  }
}

/// 月网格内容：行 + 格子（农历/节气/节日次级文案）。
///
/// 收起态：整层上移让选中周贴顶，非选中行按 smootherstep 渐隐；
/// 无手势（ghost 转场复用同一外观）。
class CalendarMonthGridContent extends StatelessWidget {
  const CalendarMonthGridContent({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.today,
    required this.markedDates,
    required this.mondayFirst,
    required this.palette,
    required this.collapse,
    this.onDayTap,
    this.ignoreDayTap = false,
  });

  final DateTime month;
  final DateTime selectedDate;
  final DateTime today;
  final Set<String> markedDates;
  final bool mondayFirst;
  final CalendarPalette palette;

  /// 0..1 之外的值保留（拖拽越界映射为阻力位移）。
  final double collapse;
  final ValueChanged<DateTime>? onDayTap;
  final bool ignoreDayTap;

  int get _rows {
    final first = DateTime(month.year, month.month, 1);
    final start = calendarWeekStart(first, mondayFirst: mondayFirst);
    final offset = first.difference(start).inDays;
    return ((offset + calendarDaysInMonth(month.year, month.month)) / 7)
        .ceil();
  }

  int get _selWeek {
    final start = calendarWeekStart(month, mondayFirst: mondayFirst);
    final offset = selectedDate.difference(start).inDays;
    return (offset ~/ 7).clamp(0, _rows - 1);
  }

  @override
  Widget build(BuildContext context) {
    final p = calendarClamp01(collapse);
    final range = math.max(
        1.0, _rows * kCalendarRowHeight - kCalendarRowHeight);
    final extraY = collapse < 0
        ? calendarRubber(-collapse * range)
        : (collapse > 1 ? -calendarRubber((collapse - 1) * range) : 0.0);
    final dy = -_selWeek * kCalendarRowHeight * (1 - p) + extraY;
    final othersOpacity = calendarSmootherstep((p - 0.12) / 0.5);
    final start = calendarMonthGridStart(month, mondayFirst: mondayFirst);

    return Transform.translate(
      offset: Offset(0, dy),
      // OverflowBox 让内容保持整月高度自然布局（收起态父高仅一行时
      // 不触发 RenderFlex overflow），超出部分由上层 ClipRect 裁剪。
      child: OverflowBox(
        minHeight: _rows * kCalendarRowHeight,
        maxHeight: _rows * kCalendarRowHeight,
        alignment: Alignment.topCenter,
        child: Column(
        children: [
          for (var row = 0; row < _rows; row++)
            Opacity(
              opacity: row == _selWeek ? 1 : othersOpacity,
              child: SizedBox(
                height: kCalendarRowHeight,
                child: Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: _MonthCell(
                          date: start.add(Duration(days: row * 7 + col)),
                          month: month,
                          selectedDate: selectedDate,
                          today: today,
                          hasTask: markedDates
                              .contains(calendarDateKey(start.add(
                                  Duration(days: row * 7 + col)))),
                          palette: palette,
                          onTap: ignoreDayTap
                              ? null
                              : () => onDayTap?.call(
                                  start.add(Duration(days: row * 7 + col))),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}

/// 月格子：日号圆环 + 农历次级文案。
class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.date,
    required this.month,
    required this.selectedDate,
    required this.today,
    required this.hasTask,
    required this.palette,
    this.onTap,
  });

  final DateTime date;
  final DateTime month;
  final DateTime selectedDate;
  final DateTime today;
  final bool hasTask;
  final CalendarPalette palette;
  final VoidCallback? onTap;

  bool get _out => date.month != month.month;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final isToday = _sameDay(date, today);
    final isSelected = _sameDay(date, selectedDate);
    final sub = _out ? null : calendarLunarSubLabel(date);
    final subColor = (sub != null && sub.$2)
        ? palette.accent
        : palette.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? palette.accentSoft.withValues(alpha: 0.45) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
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
                  fontWeight:
                      isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isToday
                      ? palette.danger
                      : (isSelected
                          ? palette.accent
                          : (_out
                              ? palette.textSecondary
                              : palette.textPrimary)),
                ),
              ),
            ),
            const SizedBox(height: 1),
            SizedBox(
              height: 11,
              child: sub == null
                  ? null
                  : Text(
                      sub.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1,
                        color: isToday ? palette.danger : subColor,
                        fontWeight: sub.$2 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 面板头部：日期 + 计数，点按/拖拽均可切换收展。
class _TaskPanelHeader extends StatelessWidget {
  const _TaskPanelHeader({
    required this.selectedDate,
    required this.tasks,
    required this.palette,
  });

  final DateTime selectedDate;
  final List<CalendarTask> tasks;
  final CalendarPalette palette;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final done = tasks.where((t) => t.completed).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${selectedDate.month}月${selectedDate.day}日',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Text(
              weekdays[selectedDate.weekday - DateTime.monday],
              style: TextStyle(
                fontSize: 12,
                color: palette.textSecondary,
              ),
            ),
          ),
          const Spacer(),
          if (tasks.isNotEmpty)
            Text(
              '${tasks.length} 项 · 已完成 $done',
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
        ],
      ),
    );
  }
}
