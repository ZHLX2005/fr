import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/calendar_date_utils.dart';
import 'calendar_motion.dart';
import 'calendar_palette.dart';

/// 年视图：12 张迷你月卡（含今日环、任务标记、农历首日）。
///
/// 横向拖动切换年份（kFlip 弹簧轮盘，与月历翻月同款跟手机制），
/// 箭头点按也走同一动效；点卡片通过 [onMonthTap] 上报（携带卡片
/// RenderBox 全局矩形，供年→月容器变换转场取起点）；卡片外观组件
/// [CalendarMiniMonthCard] 同时被 ghost 转场复用。
///
/// [gridTransform] / [staggerT] / [staggerTarget] 用于月→年容器变换：
/// 网格整体做 FLIP 汇聚（原型 .year-grid 的 transform 关键帧），其余
/// 卡片按与目标卡的距离错峰浮现（原型逐卡 opacity + delay）。
class CalendarYearPane extends StatefulWidget {
  const CalendarYearPane({
    super.key,
    required this.year,
    required this.today,
    required this.markedDates,
    required this.mondayFirst,
    required this.palette,
    required this.onYearChanged,
    required this.onMonthTap,
    this.cardKeys,
    this.gridTransform,
    this.staggerT,
    this.staggerTarget = 0,
  });

  final int year;
  final DateTime today;
  final Set<String> markedDates;
  final bool mondayFirst;
  final CalendarPalette palette;
  final ValueChanged<int> onYearChanged;
  final void Function(BuildContext cardContext, DateTime monthFirst) onMonthTap;

  /// 按月份序号（0-11）提供卡片 GlobalKey，供容器变换取终态矩形。
  final Map<int, GlobalKey>? cardKeys;

  /// 月→年汇聚：作用于卡片网格的变换矩阵（null = 恒等）。
  final Matrix4? gridTransform;

  /// 错峰浮现进度（0..1），null = 不启用（全部卡片完全可见）。
  final double? staggerT;

  /// 错峰基准卡片（目标月序 0-11）。
  final int staggerTarget;

  @override
  State<CalendarYearPane> createState() => _CalendarYearPaneState();
}

class _CalendarYearPaneState extends State<CalendarYearPane>
    with TickerProviderStateMixin {
  /// 农历换算支持范围，切年不允许越过。
  static const int _minYear = 1900;
  static const int _maxYear = 2100;

  late final CalendarSpring _spring;
  final ValueNotifier<double> _t = ValueNotifier<double>(0);
  final CalendarVelocitySampler _velocity = CalendarVelocitySampler();

  double? _startX;
  int _dir = 1;
  int? _shadowYear; // 目标年（滑入层）
  int? _pendingYear;
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

  @override
  void didUpdateWidget(CalendarYearPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.year != oldWidget.year) {
      // 切年提交后的外部状态变更：轮盘复位。
      if (_pendingYear != null && !_dragging) {
        _spring.stop();
        _spring.jump(0);
        _shadowYear = null;
        _pendingYear = null;
        _t.value = 0;
      }
    }
  }

  void _onTick() {
    _t.value = _spring.value;
    if (_dragging) return;
    if (_spring.value >= 0.999 && _pendingYear != null) {
      final pending = _pendingYear!;
      _spring.stop();
      _spring.jump(0);
      _shadowYear = null;
      _pendingYear = null;
      _t.value = 0;
      widget.onYearChanged(pending);
    } else if (_spring.value <= 0.001 &&
        _shadowYear != null &&
        // 从 0 起步 to(1) 的首个 tick 上报 value=0（elapsed=0），不得
        // 误判为「回弹完成」杀掉动画：只在朝 0 回弹时触发。
        _spring.lastToTarget < 0.5) {
      _spring.stop();
      _spring.jump(0);
      setState(() {
        _shadowYear = null;
        _pendingYear = null; // 未过阈值回弹：清掉残留目标，防误 commit。
      });
    }
  }

  double _width() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) return math.max(1.0, box.size.width);
    return 358;
  }

  /// 箭头点按 / 程序化切年：与拖拽同一条轮盘动效。
  void _animateTo(int target) {
    if (target < _minYear || target > _maxYear) return;
    if (_spring.isAnimating) {
      _spring.stop();
      _spring.jump(0);
    }
    setState(() {
      _dir = target > widget.year ? 1 : -1;
      _pendingYear = target;
      _shadowYear = target;
      _dragging = false;
    });
    _spring.to(1);
  }

  /* ───────────── 横向拖拽：切年 ───────────── */

  void _onHorizontalStart(DragStartDetails d) {
    _startX = d.localPosition.dx;
    _velocity.reset(0);
    if (_spring.isAnimating) {
      _spring.stop();
      _spring.jump(_pendingYear != null ? 1 : 0);
    }
  }

  void _onHorizontalUpdate(DragUpdateDetails d) {
    final startX = _startX;
    if (startX == null) return;
    final dx = d.localPosition.dx - startX;
    _velocity.add(dx);
    if (!_dragging) {
      if (dx.abs() <= kCalendarDragDeadZone) return;
      final dir = dx < 0 ? 1 : -1;
      final target = widget.year + dir;
      if (target < _minYear || target > _maxYear) return;
      setState(() {
        _dragging = true;
        _dir = dir;
        _pendingYear = target;
        _shadowYear = target;
      });
    }
    _spring.jump(calendarClamp01(dx.abs() / _width()));
  }

  void _onHorizontalEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    _startX = null;
    final velocity = (d.primaryVelocity ?? 0) / 1000; // px/ms
    final proj = calendarProject(_t.value, velocity.abs(), _width());
    if (_pendingYear != null && (proj > 0.5 || velocity.abs() > 0.35)) {
      _spring.to(1, velocity: velocity.abs() * _width());
    } else {
      _spring.to(0);
    }
  }

  /// 原型：delay = 100+min(220, |i-target|*32) ms，时长 240ms，ease-out。
  double _cardOpacity(int i) {
    final t = widget.staggerT;
    if (t == null) return 1;
    final elapsed = t.clamp(0.0, 1.0) * 520;
    final delay = 100.0 +
        math.min(220.0, (i - widget.staggerTarget).abs() * 32.0);
    final p = ((elapsed - delay) / 240).clamp(0.0, 1.0);
    return 1 - (1 - p) * (1 - p);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _YearArrow(
                icon: Icons.chevron_left,
                palette: widget.palette,
                onTap: () => _animateTo(widget.year - 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  '${widget.year}',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: widget.palette.textPrimary,
                  ),
                ),
              ),
              _YearArrow(
                icon: Icons.chevron_right,
                palette: widget.palette,
                onTap: () => _animateTo(widget.year + 1),
              ),
            ],
          ),
        ),
        Expanded(
          child: ClipRect(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _onHorizontalStart,
              onHorizontalDragUpdate: _onHorizontalUpdate,
              onHorizontalDragEnd: _onHorizontalEnd,
              child: ValueListenableBuilder<double>(
                valueListenable: _t,
                builder: (context, t, _) {
                  final width = _width();
                  return Stack(
                    children: [
                      // shadow：待进入的年份，从翻页方向对侧滑入。
                      if (_shadowYear != null)
                        Positioned.fill(
                          child: Transform.translate(
                            offset: Offset(_dir * width * (1 - t), 0),
                            child: _yearGrid(_shadowYear!, interactive: false),
                          ),
                        ),
                      // 主层：当前年份，翻页时向方向侧滑出；静止态原位可见。
                      Positioned.fill(
                        child: Transform.translate(
                          offset: Offset(-_dir * width * t, 0),
                          child: _yearGrid(widget.year, interactive: true),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _yearGrid(int year, {required bool interactive}) {
    return Transform(
      alignment: Alignment.topLeft,
      transform: widget.gridTransform ?? Matrix4.identity(),
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        padding: const EdgeInsets.fromLTRB(0, 2, 0, 116),
        childAspectRatio: 0.82,
        children: [
          for (var m = 1; m <= 12; m++)
            Opacity(
              // 错峰浮现只作用于主层（morph 期间轮盘静止，shadow 为 null）。
              opacity: interactive ? _cardOpacity(m - 1) : 1,
              child: Builder(
                // GlobalKey 不可重复挂载：shadow 层不带 key。
                builder: (context) {
                  final cardKeys = widget.cardKeys;
                  final GlobalKey? cardKey =
                      interactive && cardKeys != null ? cardKeys[m - 1] : null;
                  return CalendarMiniMonthCard(
                    key: cardKey,
                    month: DateTime(year, m, 1),
                    today: widget.today,
                    selectedDate: null,
                    markedDates: widget.markedDates,
                    mondayFirst: widget.mondayFirst,
                    palette: widget.palette,
                    isCurrentMonth: year == widget.today.year &&
                        m == widget.today.month,
                    onTap: interactive
                        ? () =>
                            widget.onMonthTap(context, DateTime(year, m, 1))
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _YearArrow extends StatelessWidget {
  const _YearArrow({
    required this.icon,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final CalendarPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: palette.textSecondary),
      ),
    );
  }
}

/// 迷你月卡：label + 迷你日历（固定 6 行布局保证卡片等高）。
class CalendarMiniMonthCard extends StatelessWidget {
  const CalendarMiniMonthCard({
    super.key,
    required this.month,
    required this.today,
    required this.markedDates,
    required this.mondayFirst,
    required this.palette,
    this.selectedDate,
    this.isCurrentMonth = false,
    this.onTap,
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selectedDate;
  final Set<String> markedDates;
  final bool mondayFirst;
  final CalendarPalette palette;
  final bool isCurrentMonth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              '${month.month}月',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isCurrentMonth ? FontWeight.w700 : FontWeight.w500,
                color: isCurrentMonth
                    ? palette.accent
                    : palette.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                children: [
                  for (var row = 0; row < 6; row++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var col = 0; col < 7; col++)
                            Expanded(
                              child: Center(
                                child: _MiniCell(
                                  date: _cellDate(month, row, col),
                                  month: month,
                                  today: today,
                                  selectedDate: selectedDate,
                                  markedDates: markedDates,
                                  palette: palette,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _cellDate(DateTime month, int row, int col) {
    final start = calendarMonthGridStart(month, mondayFirst: mondayFirst);
    return start.add(Duration(days: row * 7 + col));
  }
}

class _MiniCell extends StatelessWidget {
  const _MiniCell({
    required this.date,
    required this.month,
    required this.today,
    required this.selectedDate,
    required this.markedDates,
    required this.palette,
  });

  final DateTime date;
  final DateTime month;
  final DateTime today;
  final DateTime? selectedDate;
  final Set<String> markedDates;
  final CalendarPalette palette;

  @override
  Widget build(BuildContext context) {
    if (date.month != month.month) {
      return const SizedBox.shrink();
    }
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final isSelected = selectedDate != null &&
        date.year == selectedDate!.year &&
        date.month == selectedDate!.month &&
        date.day == selectedDate!.day;
    final hasTask = markedDates.contains(calendarDateKey(date));

    final color = isToday
        ? palette.danger
        : (isSelected ? palette.accent : (hasTask ? palette.accent : null));
    return Container(
      width: 17,
      height: 17,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected && !isToday
            ? palette.accentSoft.withValues(alpha: 0.5)
            : null,
        border: isToday
            ? Border.all(color: palette.danger, width: 1)
            : null,
      ),
      child: Text(
        '${date.day}',
        style: TextStyle(
          fontSize: 8.5,
          height: 1,
          fontFeatures: const [],
          color: color ?? palette.textSecondary,
          fontWeight: isToday || hasTask ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
