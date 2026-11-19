import 'package:flutter/material.dart';

import '../domain/calendar_task.dart';
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
  });

  final List<CalendarTask> tasks;
  final bool loading;
  final CalendarPalette palette;
  final ValueChanged<CalendarTask> onToggle;
  final ValueChanged<CalendarTask> onDelete;
  final bool storageAvailable;

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
      return _EmptyState(
        palette: palette,
        title: '当前平台未启用本地数据库',
        subtitle: '日历任务需要 SQLite；请在 Android / iOS 上使用。',
      );
    }

    if (tasks.isEmpty) {
      return _EmptyState(
        palette: palette,
        title: '你这一天没有任务',
        subtitle: '放松一下吧',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 96),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _TaskRow(
          task: task,
          palette: palette,
          onToggle: () => onToggle(task),
          onDelete: () => onDelete(task),
        );
      },
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.palette,
    required this.onToggle,
    required this.onDelete,
  });

  final CalendarTask task;
  final CalendarPalette palette;
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
    final color = task.colorValue == null
        ? palette.accent
        : Color(task.colorValue!);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            _timeLabel,
            style: TextStyle(
              fontSize: 12,
              color: palette.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        Expanded(
          child: Material(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
            elevation: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onToggle,
              child: Container(
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: palette.divider.withValues(alpha: 0.7),
                  ),
                ),
                child: Row(
                  children: [
                    _TaskCheck(task: task, color: color, palette: palette),
                    const SizedBox(width: 10),
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
                    IconButton(
                      tooltip: '删除任务',
                      onPressed: onDelete,
                      icon: Icon(
                        Icons.more_horiz,
                        size: 18,
                        color: palette.textSecondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TaskCheck extends StatelessWidget {
  const _TaskCheck({
    required this.task,
    required this.color,
    required this.palette,
  });

  final CalendarTask task;
  final Color color;
  final CalendarPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: task.completed ? palette.accent : color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: task.completed
          ? const Icon(Icons.check, size: 15, color: Colors.white)
          : Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.palette,
    required this.title,
    required this.subtitle,
  });

  final CalendarPalette palette;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 210,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 190,
                    height: 120,
                    decoration: BoxDecoration(
                      color: palette.accentSoft.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(60),
                    ),
                  ),
                  Transform.rotate(
                    angle: -0.08,
                    child: Container(
                      width: 108,
                      height: 86,
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: palette.divider),
                        boxShadow: [
                          BoxShadow(
                            color: palette.shadow,
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            height: 22,
                            decoration: BoxDecoration(
                              color: palette.accent.withValues(alpha: 0.8),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(11),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Icon(
                              Icons.event_note_outlined,
                              size: 34,
                              color: palette.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 38,
                    top: 34,
                    child: Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: palette.textSecondary.withValues(alpha: 0.45),
                    ),
                  ),
                  Positioned(
                    left: 46,
                    bottom: 28,
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: palette.textSecondary.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
