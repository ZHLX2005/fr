import 'package:flutter/material.dart';
import '../domain/models.dart';

/// 课表格子组件 - 统一点击处理
class TimetableCell extends StatelessWidget {
  const TimetableCell({
    super.key,
    required this.cellKey,
    required this.course,
    required this.onTap,
    this.selected = false,
  });

  final String cellKey;
  final Course? course;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: course != null
          ? _getCourseColor(theme, course!.colorSeed)
          : (selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          child: course != null
              ? _buildCourseContent(theme)
              : _buildEmptyContent(theme),
        ),
      ),
    );
  }

  Widget _buildCourseContent(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          course!.title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (course!.location != null && course!.location!.isNotEmpty)
          Text(
            course!.location!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white70,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  Widget _buildEmptyContent(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.add,
        size: 16,
        color: theme.colorScheme.outline,
      ),
    );
  }

  Color _getCourseColor(ThemeData theme, int seed) {
    final colors = [
      const Color(0xFF6366F1), // 靛蓝
      const Color(0xFF8B5CF6), // 紫色
      const Color(0xFFEC4899), // 粉色
      const Color(0xFFEF4444), // 红色
      const Color(0xFFF97316), // 橙色
      const Color(0xFFEAB308), // 黄色
      const Color(0xFF22C55E), // 绿色
      const Color(0xFF14B8A6), // 青色
      const Color(0xFF3B82F6), // 蓝色
    ];
    return colors[seed.abs() % colors.length];
  }
}
