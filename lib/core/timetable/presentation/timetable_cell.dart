import 'package:flutter/material.dart';
import '../domain/models.dart';
import 'timetable_colors.dart';

/// 单元格状态
enum TimetableCellState {
  empty,
  selected,
  filled,
}

/// 课程单元格
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: _backgroundColor(),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: _buildContent(),
        ),
      ),
    );
  }

  Color _backgroundColor() {
    switch (state) {
      case TimetableCellState.empty:
        return Colors.transparent;
      case TimetableCellState.selected:
        return TimetableColors.selectedBg;
      case TimetableCellState.filled:
        return TimetableColors.getCourseColor(course?.colorSeed ?? 0)
            .withValues(alpha: 0.88);
    }
  }

  Widget _buildContent() {
    switch (state) {
      case TimetableCellState.empty:
        return const SizedBox.shrink();
      case TimetableCellState.selected:
        return Center(
          child: Icon(Icons.add, size: 16, color: TimetableColors.accentLight),
        );
      case TimetableCellState.filled:
        if (course == null) return const SizedBox.shrink();
        return _CourseContent(course: course!);
    }
  }
}

/// 课程内容：标题分行 + 地点
class _CourseContent extends StatelessWidget {
  const _CourseContent({required this.course});

  final CourseItem course;

  @override
  Widget build(BuildContext context) {
    final color = TimetableColors.getCourseColor(course.colorSeed ?? 0);
    final isLight = color.computeLuminance() > 0.55;
    final textColor = isLight ? const Color(0xFF3D3D3D) : Colors.white;
    final subTextColor = isLight ? const Color(0xFF5D5D5D) : Colors.white70;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 课程名：按长度分行
          ..._buildTitleLines(course.title, textColor),
          // 地点：完整显示，不截断
          if (course.location != null && course.location!.isNotEmpty)
            Text(
              course.location!,
              style: TextStyle(
                color: subTextColor,
                fontSize: 8,
                height: 1.1,
              ),
              maxLines: 2,
            ),
        ],
      ),
    );
  }

  /// 按长度自动分行
  List<Widget> _buildTitleLines(String title, Color textColor) {
    final lines = <Widget>[];
    final len = title.length;

    if (len <= 3) {
      // 1-3字：单行
      lines.add(Text(
        title,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    } else if (len == 4) {
      // 4字：2+2
      lines.add(Text(
        title.substring(0, 2),
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
      lines.add(Text(
        title.substring(2),
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    } else if (len == 5) {
      // 5字：3+2
      lines.add(Text(
        title.substring(0, 3),
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
      lines.add(Text(
        title.substring(3),
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    } else {
      // 6字及以上：最多2行，超长省略
      lines.add(Text(
        title,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ));
      if (title.length > 6) {
        lines.add(Text(
          title.substring(6),
          style: TextStyle(
            color: textColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ));
      }
    }

    return lines;
  }
}
