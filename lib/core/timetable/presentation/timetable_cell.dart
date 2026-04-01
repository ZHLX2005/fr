import 'package:flutter/material.dart';
import '../domain/models.dart';

/// 单元格状态
enum TimetableCellState {
  /// 空白单元格
  empty,
  /// 选中状态（高亮+显示+按钮）
  selected,
  /// 已填充课程内容
  filled,
}

/// 3态课表单元格组件
class TimetableCell extends StatelessWidget {
  const TimetableCell({
    super.key,
    required this.state,
    required this.course,
    required this.onTap,
    required this.onLongPress,
  });

  final TimetableCellState state;
  final CourseItem? course;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: _backgroundColor(theme),
          borderRadius: BorderRadius.circular(10),
          border: _border(theme),
          boxShadow: _boxShadow(theme),
        ),
        child: _buildContent(theme),
      ),
    );
  }

  Color _backgroundColor(ThemeData theme) {
    switch (state) {
      case TimetableCellState.empty:
        return theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);
      case TimetableCellState.selected:
        return theme.colorScheme.primaryContainer;
      case TimetableCellState.filled:
        final seed = course?.colorSeed ?? 0;
        return _getCourseColor(seed);
    }
  }

  Color _getCourseColor(int seed) {
    final colors = [
      const Color(0xFF6366F1),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFFEF4444),
      const Color(0xFFF97316),
      const Color(0xFFEAB308),
      const Color(0xFF22C55E),
      const Color(0xFF14B8A6),
      const Color(0xFF0EA5E9),
      const Color(0xFF64748B),
    ];
    return colors[seed % colors.length];
  }

  Border? _border(ThemeData theme) {
    switch (state) {
      case TimetableCellState.empty:
        return Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
          width: 1,
        );
      case TimetableCellState.selected:
        return Border.all(
          color: theme.colorScheme.primary,
          width: 2,
        );
      case TimetableCellState.filled:
        return null;
    }
  }

  List<BoxShadow>? _boxShadow(ThemeData theme) {
    if (state != TimetableCellState.filled) return null;
    return [
      BoxShadow(
        color: _getCourseColor(course?.colorSeed ?? 0).withValues(alpha: 0.3),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ];
  }

  Widget _buildContent(ThemeData theme) {
    switch (state) {
      case TimetableCellState.empty:
        return Center(
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: theme.colorScheme.outline.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.add,
              size: 14,
              color: theme.colorScheme.outline.withValues(alpha: 0.4),
            ),
          ),
        );
      case TimetableCellState.selected:
        return Center(
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.add,
              size: 20,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        );
      case TimetableCellState.filled:
        if (course == null) return const SizedBox.shrink();
        return _buildCourseContent(theme);
    }
  }

  Widget _buildCourseContent(ThemeData theme) {
    final color = _getCourseColor(course!.colorSeed ?? 0);
    final isLight = color.computeLuminance() > 0.5;
    final textColor = isLight ? Colors.black87 : Colors.white;
    final subTextColor = isLight ? Colors.black54 : Colors.white70;

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              course!.title,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (course!.location != null && course!.location!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 10,
                  color: subTextColor,
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    course!.location!,
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 10,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
