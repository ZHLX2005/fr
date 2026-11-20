import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/calendar_task.dart';
import 'calendar_controls.dart';
import 'calendar_palette.dart';

class CalendarTaskList extends StatelessWidget {
  const CalendarTaskList({
    super.key,
    required this.tasks,
    required this.loading,
    required this.palette,
    required this.onToggle,
    required this.onDelete,
    this.storageAvailable = true,
    this.storageMessage,
    this.onRetry,
  });

  final List<CalendarTask> tasks;
  final bool loading;
  final CalendarPalette palette;
  final ValueChanged<CalendarTask> onToggle;
  final ValueChanged<CalendarTask> onDelete;
  final bool storageAvailable;
  final String? storageMessage;
  final VoidCallback? onRetry;

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
      return _scrollable(
        _StorageUnavailable(
          palette: palette,
          message: storageMessage,
          onRetry: onRetry,
        ),
      );
    }

    if (tasks.isEmpty) {
      return _scrollable(const _EmptyState());
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _TaskRow(
          task: task,
          palette: palette,
          showConnector: index != tasks.length - 1,
          onToggle: () => onToggle(task),
          onDelete: () => onDelete(task),
        );
      },
    );
  }

  Widget _scrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 96),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.palette,
    required this.showConnector,
    required this.onToggle,
    required this.onDelete,
  });

  final CalendarTask task;
  final CalendarPalette palette;
  final bool showConnector;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  String get _timeLabel {
    if (task.allDay) return '全天';
    final h = task.start.hour.toString().padLeft(2, '0');
    final m = task.start.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final color = calendarTaskColor(task.colorValue, task.id);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _timeLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: palette.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 3,
                  top: 14,
                  child: _TaskGlyph(
                    color: color,
                    completed: task.completed,
                    palette: palette,
                  ),
                ),
                // 无封面图的卡片：图标下留一条极浅横线，替代边框做视觉隔离。
                Positioned(
                  left: 2,
                  right: 2,
                  top: 41,
                  child: Container(
                    height: 0.6,
                    color: palette.divider.withValues(alpha: 0.30),
                  ),
                ),
                if (showConnector)
                  Positioned(
                    left: 16.5,
                    top: 43,
                    bottom: -9,
                    child: Container(
                      width: 1,
                      color: palette.divider.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              onLongPress: onDelete,
              child: Container(
                constraints: const BoxConstraints(minHeight: 60),
                padding: const EdgeInsets.fromLTRB(8, 10, 6, 10),
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.25,
                              color: task.completed
                                  ? palette.completed
                                  : palette.textPrimary,
                              decoration: task.completed
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              decorationColor: palette.completed,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (task.notes != null && task.notes!.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              task.notes!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onDelete,
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.more_horiz,
                          size: 18,
                          color: palette.textSecondary.withValues(alpha: 0.7),
                        ),
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
}

class _TaskGlyph extends StatelessWidget {
  const _TaskGlyph({
    required this.color,
    required this.completed,
    required this.palette,
  });

  final Color color;
  final bool completed;
  final CalendarPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: completed ? palette.accent : color,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: completed
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 220,
              height: 160,
              child: CustomPaint(painter: _EmptyCalendarPainter()),
            ),
            const SizedBox(height: 10),
            Text(
              '你这一天没有任务',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: CalendarPalette.of(context).textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '放松一下吧',
              style: TextStyle(
                fontSize: 14,
                color: CalendarPalette.of(context).textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageUnavailable extends StatelessWidget {
  const _StorageUnavailable({
    required this.palette,
    required this.message,
    required this.onRetry,
  });

  final CalendarPalette palette;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow.withValues(alpha: 0.6),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.storage_rounded,
                color: palette.textSecondary,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '本地数据库还没准备好',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message ?? 'SQLite 初始化失败；日历数据暂时无法读取。',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: 144,
                child: CalendarActionButton(
                  label: '重试',
                  palette: palette,
                  filled: false,
                  height: 42,
                  onTap: onRetry,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyCalendarPainter extends CustomPainter {
  const _EmptyCalendarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final blob = Paint()
      ..color = const Color(0xFFD9ECE9).withValues(alpha: 0.9);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.16);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 185, height: 112),
      blob,
    );
    canvas.restore();

    final card = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 115, height: 92),
      const Radius.circular(8),
    );
    canvas.drawRRect(card.shift(const Offset(-4, 4)), Paint()..color = const Color(0x22000000));
    canvas.drawRRect(card, Paint()..color = Colors.white);
    canvas.drawRRect(
      card,
      Paint()
        ..color = const Color(0xFF31424A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    final header = RRect.fromRectAndRadius(
      Rect.fromLTWH(card.left + 1, card.top + 1, card.width - 2, 22),
      const Radius.circular(7),
    );
    canvas.drawRRect(header, Paint()..color = const Color(0xFF70BFCB));
    canvas.drawRRect(
      header,
      Paint()
        ..color = const Color(0xFF31424A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final ink = Paint()
      ..color = const Color(0xFF31424A)
      ..strokeWidth = 1.1;
    for (var i = 0; i < 3; i++) {
      final x = card.left + 28 + i * 28;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, card.top - 9, 5, 18),
          const Radius.circular(3),
        ),
        Paint()..color = Colors.white,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, card.top - 9, 5, 18),
          const Radius.circular(3),
        ),
        ink..strokeWidth = 1,
      );
    }

    final grid = Paint()
      ..color = const Color(0xFF9DB1B5)
      ..strokeWidth = 0.8;
    for (var row = 0; row < 3; row++) {
      final y = card.top + 44 + row * 16;
      canvas.drawLine(Offset(card.left + 10, y), Offset(card.right - 10, y), grid);
      for (var col = 1; col < 3; col++) {
        final x = card.left + 10 + col * 31;
        canvas.drawLine(Offset(x, card.top + 24), Offset(x, card.bottom - 5), grid);
      }
    }

    final clockCenter = Offset(card.left + 76, card.top + 46);
    canvas.drawCircle(clockCenter, 9, Paint()..color = const Color(0xFF70BFCB));
    canvas.drawArc(
      Rect.fromCircle(center: clockCenter, radius: 5),
      -math.pi / 2,
      math.pi * 1.15,
      false,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(clockCenter, clockCenter + const Offset(0, -5), ink..strokeWidth = 1.2);
    canvas.drawLine(clockCenter, clockCenter + const Offset(4, 0), ink);

    final sparkle = Paint()
      ..color = const Color(0xFF31424A)
      ..strokeWidth = 1;
    _drawSparkle(canvas, Offset(card.left - 22, card.top - 12), 8, sparkle);
    _drawSparkle(canvas, Offset(card.right + 16, card.bottom - 18), 6, sparkle);
    canvas.drawCircle(
      Offset(card.right - 12, card.top - 4),
      2,
      Paint()..color = const Color(0xFF31424A),
    );
  }

  void _drawSparkle(Canvas canvas, Offset center, double radius, Paint paint) {
    canvas.drawLine(
      center + Offset(-radius, 0),
      center + Offset(radius, 0),
      paint,
    );
    canvas.drawLine(
      center + Offset(0, -radius),
      center + Offset(0, radius),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
