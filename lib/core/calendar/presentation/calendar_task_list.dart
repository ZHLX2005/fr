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
      return Center(
        child: _StorageUnavailable(
          palette: palette,
          message: storageMessage,
          onRetry: onRetry,
        ),
      );
    }

    if (tasks.isEmpty) {
      return const Center(child: _EmptyState());
    }

    // 滚动交给外层 _PanelScroll（与月历收展共用同一条纵向手势），
    // 这里只负责内容排版；空态不产生任何可滚动量。
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _TaskRow(
              task: tasks[i],
              palette: palette,
              showConnector: i != tasks.length - 1,
              onToggle: () => onToggle(tasks[i]),
              onDelete: () => onDelete(tasks[i]),
            ),
          ],
        ],
      ),
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

class _TaskGlyph extends StatefulWidget {
  const _TaskGlyph({
    required this.color,
    required this.completed,
    required this.palette,
  });

  final Color color;
  final bool completed;
  final CalendarPalette palette;

  @override
  State<_TaskGlyph> createState() => _TaskGlyphState();
}

class _TaskGlyphState extends State<_TaskGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    if (widget.completed) _pop.value = 1;
  }

  @override
  void didUpdateWidget(covariant _TaskGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 原型 chk-pop：勾选瞬间 scale 1→1.22→1（300ms，回弹曲线）。
    if (widget.completed && !oldWidget.completed) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, _) {
        final t = _pop.value;
        // 0→.45 放大到 1.22，.45→1 回弹到 1。
        final scale = t < 0.45
            ? 1 + 0.22 * (t / 0.45)
            : 1.22 - 0.22 * ((t - 0.45) / 0.55);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: widget.completed ? widget.palette.accent : widget.color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: widget.completed
                  ? Icon(Icons.check, size: 16, color: widget.palette.onAccent)
                  : Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: widget.palette.onAccent
                            .withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = CalendarPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 原型 `.dp-empty`：一只淡茶盏 + 两行小字，不用大插画压住整块面板。
            Icon(
              Icons.emoji_food_beverage_outlined,
              size: 34,
              color: palette.textSecondary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 8),
            Text(
              '这一天还空着',
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
            const SizedBox(height: 3),
            Text(
              '下方面板可直接添加',
              style: TextStyle(
                fontSize: 11,
                color: palette.textSecondary.withValues(alpha: 0.7),
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
