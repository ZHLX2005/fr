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
  final void Function(double target, double velocity, bool fromDrag)
      onCollapseSettle;
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
    // 投射必须基于「当前」收展值：用拖拽起点值会让慢速拖拽（速度≈0）
    // 永远吸附回起点，表现为「怎么拖都不收起」。
    final current = calendarClamp01(widget.collapse.value);
    final proj = calendarProject(current, velocity, _range);
    widget.onCollapseSettle(
      proj > 0.5 ? 1 : 0,
      velocity * 1000 / _range,
      true,
    );
  }

  void _toggleCollapse() {
    final raw = calendarClamp01(widget.collapse.value);
    widget.onCollapseSettle(raw > 0.5 ? 0 : 1, 0, false);
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
          // 底部为悬浮 FAB / 悬浮底栏预留的空白放在滚动视口之外：只缩小
          // 可视区，不计入内容高度——装饰性留白不得制造可滚动量，否则
          // 空面板也能被拖出回弹。
          child: Padding(
            padding: EdgeInsets.only(
              bottom: 120 + MediaQuery.paddingOf(context).bottom,
            ),
            child: _PanelScroll(
              collapse: widget.collapse,
              collapseRange: _range,
              onCollapseDrive: widget.onCollapseDrive,
              onCollapseSettle: widget.onCollapseSettle,
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
          ),
        ),
      ],
    );
  }
}

/// 月页任务面板的滚动层（原型 makeKinetic 的 Flutter 落地）。
///
/// 与原生 ListView 的差别正是本次要修的冲突点：
/// · 内容不溢出（含完全无内容）时不可滚动，纵向拖拽整段驱动月历收展；
/// · 内容溢出时先滚动内容，到达上/下端点后的剩余位移才交接给收展；
/// · 松手按 130ms 动量投射惯性滑行，越界用 k170/c26 弹簧回弹。
class _PanelScroll extends StatefulWidget {
  const _PanelScroll({
    required this.child,
    required this.collapse,
    required this.collapseRange,
    required this.onCollapseDrive,
    required this.onCollapseSettle,
  });

  final Widget child;
  final ValueListenable<double> collapse;
  final double collapseRange;
  final ValueChanged<double> onCollapseDrive;
  final void Function(double target, double velocity, bool fromDrag)
      onCollapseSettle;

  @override
  State<_PanelScroll> createState() => _PanelScrollState();
}

class _PanelScrollState extends State<_PanelScroll>
    with SingleTickerProviderStateMixin {
  final GlobalKey _contentKey = GlobalKey();
  late final CalendarSpring _spring;

  double _off = 0;
  double _max = 0;
  double _viewport = 300;

  double? _startY;
  double _rawBase = 0;
  double _collapseBase = 1;
  bool _dragging = false;
  bool _moved = false;
  bool _handoff = false;
  bool _measuring = false;

  @override
  void initState() {
    super.initState();
    _spring = CalendarSpring(
      vsync: this,
      description: kCalendarPanelSpring,
      onUpdate: _onSpringTick,
    );
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _onSpringTick() {
    final next = _spring.value.clamp(0.0, _max);
    if (next == _off) return;
    setState(() => _off = next);
  }

  void _setOff(double value) {
    if (value == _off) return;
    setState(() => _off = value);
  }

  /// 内容高度只能在布局后量：post-frame 读 RenderBox，量到变化才 setState。
  void _scheduleMeasure(double viewport) {
    _viewport = viewport;
    if (_measuring) return;
    _measuring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measuring = false;
      if (!mounted) return;
      final box = _contentKey.currentContext?.findRenderObject();
      if (box is! RenderBox) return;
      final max = math.max(0.0, box.size.height - _viewport);
      if (max == _max) return;
      setState(() {
        _max = max;
        if (_off > _max) _off = _max;
      });
    });
  }

  void _onDragStart(DragStartDetails d) {
    _spring.stop();
    _dragging = true;
    _moved = false;
    _handoff = false;
    _startY = d.localPosition.dy;
    _rawBase = _off;
    _collapseBase = calendarClamp01(widget.collapse.value);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final startY = _startY;
    if (startY == null) return;
    // 手指上移为正 = 内容上移（与 off 同向）；月历收展方向与之相反。
    final dy = startY - d.localPosition.dy;
    if (!_moved) {
      if (dy.abs() <= kCalendarDragDeadZone) return;
      _moved = true;
    }
    final raw = _rawBase + dy;
    final range = math.max(1.0, widget.collapseRange);
    if (raw < 0) {
      // 列表顶端的下拉：整个面板展开。
      _handoff = true;
      _setOff(0);
      widget.onCollapseDrive(_collapseBase - raw / range);
    } else if (raw > _max) {
      // 列表底端的继续上推：整个面板收成单周行。
      _handoff = true;
      _setOff(_max);
      widget.onCollapseDrive(_collapseBase - (raw - _max) / range);
    } else {
      if (_handoff) {
        _handoff = false;
        widget.onCollapseDrive(_collapseBase);
      }
      _setOff(raw);
    }
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    _startY = null;
    final fingerV = (d.primaryVelocity ?? 0) / 1000; // px/ms，向下为正
    if (_handoff) {
      // 端点的剩余位移已经驱动收展：松手交给收展弹簧吸附。
      _handoff = false;
      final current = calendarClamp01(widget.collapse.value);
      final proj = calendarProject(current, fingerV, widget.collapseRange);
      widget.onCollapseSettle(
        proj > 0.5 ? 1 : 0,
        fingerV * 1000 / math.max(1.0, widget.collapseRange),
        true,
      );
      return;
    }
    if (!_moved) return;
    final contentV = -fingerV; // 内容位移速度
    if (contentV.abs() <= 0.05) return;
    final target =
        (_off + contentV * kCalendarMomentumMs).clamp(0.0, _max);
    _spring.to(target, velocity: contentV * 1000);
  }

  void _onDragCancel() {
    _dragging = false;
    _startY = null;
    if (_handoff) {
      _handoff = false;
      widget.onCollapseSettle(
        calendarClamp01(widget.collapse.value) > 0.5 ? 1 : 0,
        0,
        true,
      );
    }
    _spring.to(_off.clamp(0.0, _max));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxHeight;
        _scheduleMeasure(viewport);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: _onDragStart,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          onVerticalDragCancel: _onDragCancel,
          child: ClipRect(
            child: SizedBox.expand(
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: -_off,
                    child: KeyedSubtree(
                      key: _contentKey,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: viewport),
                        child: widget.child,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
class _MonthCell extends StatefulWidget {
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

  @override
  State<_MonthCell> createState() => _MonthCellState();
}

class _MonthCellState extends State<_MonthCell> {
  bool _pressed = false;

  bool get _out => widget.date.month != widget.month.month;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final date = widget.date;
    final today = widget.today;
    final palette = widget.palette;
    final isToday = _sameDay(date, today);
    final isSelected = _sameDay(date, widget.selectedDate);
    final sub = _out ? null : calendarLunarSubLabel(date);
    final subColor = (sub != null && sub.$2)
        ? palette.accent
        : palette.textSecondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _pressed = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) => setState(() => _pressed = false),
      onTapCancel:
          widget.onTap == null ? null : () => setState(() => _pressed = false),
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
                        : (isSelected
                            ? palette.accent
                            : (_out
                                ? palette.textSecondary
                                : palette.textPrimary)),
                  ),
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
