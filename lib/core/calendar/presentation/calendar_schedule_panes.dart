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
          final proj =
              calendarProject(_t.value, velocity.abs(), _width());
          _dragging = false;
          _startX = null;
          if (_pendingBase != null &&
              (proj > 0.5 || velocity.abs() > 0.35)) {
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
                onTap: () =>
                    widget.onSelect(base.add(Duration(days: i))),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekCell extends StatelessWidget {
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

  bool get isToday =>
      date.year == today.year &&
      date.month == today.month &&
      date.day == today.day;

  bool get isSelected =>
      date.year == selectedDate.year &&
      date.month == selectedDate.month &&
      date.day == selectedDate.day;

  @override
  Widget build(BuildContext context) {
    final sub = calendarLunarSubLabel(date);
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
                          : palette.textPrimary),
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
        color: calendarTaskColor(task.colorValue, task.id)
            .withValues(alpha: 0.14),
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
  });

  /// 1 列（日）或 7 列（周）。
  final List<List<CalendarTask>> days;

  /// 日页且选中日为今天时为 true（画「现在」线）。
  final bool showNowLine;
  final CalendarPalette palette;
  final ValueChanged<CalendarTask> onToggle;

  static const double _startHour = 6;
  static const double _rowHeight = 52;
  static const int _hours = 18;
  static const double _labelWidth = 38;

  double get _gridHeight => _hours * _rowHeight;

  @override
  Widget build(BuildContext context) {
    final cols = days.length;
    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.max(
            1.0,
            constraints.maxWidth - _labelWidth,
          );
          final colWidth = contentWidth / cols;
          final events = <Widget>[];
          for (var c = 0; c < cols; c++) {
            for (final task in days[c]) {
              if (task.allDay) continue;
              final top = (task.start.hour - _startHour) * _rowHeight +
                  task.start.minute / 60 * _rowHeight;
              final end = task.end ?? task.start.add(const Duration(hours: 1));
              final bottom = (end.hour - _startHour) * _rowHeight +
                  end.minute / 60 * _rowHeight;
              final height = math.max(26.0, bottom - top - 2);
              final color = calendarTaskColor(task.colorValue, task.id);
              events.add(
                Positioned(
                  left: _labelWidth + c * colWidth + 3,
                  width: math.max(12.0, colWidth - 6),
                  top: top,
                  height: height,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onToggle(task),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: cols == 1 ? 4 : 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border(
                          left: BorderSide(color: color, width: 3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: cols == 1 ? 12 : 10.5,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                          ),
                          if (cols == 1)
                            Text(
                              _hhmm(task.start),
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
              );
            }
          }
          final nowLine = _nowLineOrNull();
          if (nowLine != null) events.add(nowLine);

          return SizedBox(
            height: _gridHeight,
            child: Stack(
              children: [
                Column(
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
                ...events,
              ],
            ),
          );
        },
      ),
    );
  }

  Widget? _nowLineOrNull() {
    if (!showNowLine) return null;
    final now = DateTime.now();
    final top = (now.hour - _startHour) * _rowHeight +
        now.minute / 60 * _rowHeight;
    if (top < 0) return null;
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 0, color: palette.danger),
          Transform.translate(
            offset: const Offset(34, -4),
            child: Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: palette.danger, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
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
              color: palette.textSecondary.withValues(alpha: 0.5),
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
      separatorBuilder: (_, _) => const SizedBox(height: 4),
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
