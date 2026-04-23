import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'timetable_colors.dart';

/// 单元格状态
enum TimetableCellState {
  /// 空白单元格
  empty,

  /// 选中状态（高亮+显示+按钮）
  selected,

  /// 已填充课程内容
  filled,
}

/// 3态课程单元格组件
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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: _backgroundColor(theme),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _buildContent(theme),
        ),
      ),
    );
  }

  Color _backgroundColor(ThemeData theme) {
    switch (state) {
      case TimetableCellState.empty:
        return Colors.transparent;
      case TimetableCellState.selected:
        return TimetableColors.selectedBg;
      case TimetableCellState.filled:
        final seed = course?.colorSeed ?? 0;
        return TimetableColors.getCourseColor(seed).withValues(alpha: 0.88);
    }
  }

  Widget _buildContent(ThemeData theme) {
    switch (state) {
      case TimetableCellState.empty:
        return Container(color: Colors.transparent);
      case TimetableCellState.selected:
        return Center(
          child: Icon(
            Icons.add,
            size: 18,
            color: TimetableColors.accentLight,
          ),
        );
      case TimetableCellState.filled:
        if (course == null) return const SizedBox.shrink();
        return _buildCourseContent(theme);
    }
  }

  Widget _buildCourseContent(ThemeData theme) {
    final color = TimetableColors.getCourseColor(course!.colorSeed ?? 0);
    final isLight = color.computeLuminance() > 0.55;
    final textColor = isLight ? const Color(0xFF3D3D3D) : Colors.white;
    final subTextColor = isLight ? const Color(0xFF5D5D5D) : Colors.white70;

    final location = course!.location;
    final title = course!.title;

    // 紧凑布局：标题单行 + 位置单行（或合并一行）
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 课程名：单行，超长省略
          Text(
            title,
            style: TextStyle(
              color: textColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // 位置/地点：省略号
          if (location != null && location.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                location,
                style: TextStyle(
                  color: subTextColor,
                  fontSize: 9,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}
