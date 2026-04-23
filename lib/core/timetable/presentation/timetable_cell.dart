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
        decoration: _buildDecoration(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildContent(),
        ),
      ),
    );
  }

  BoxDecoration _buildDecoration() {
    switch (state) {
      case TimetableCellState.empty:
        return BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: TimetableColors.border.withValues(alpha: 0.4),
            width: 0.5,
          ),
        );
      case TimetableCellState.selected:
        return BoxDecoration(
          color: TimetableColors.selectedBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: TimetableColors.accent.withValues(alpha: 0.25),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: TimetableColors.accent.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        );
      case TimetableCellState.filled:
        final baseColor = TimetableColors.getCourseColor(course?.colorSeed ?? 0);
        return BoxDecoration(
          color: baseColor.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: baseColor.withValues(alpha: 0.3),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: baseColor.withValues(alpha: 0.2),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        );
    }
  }

  Widget _buildContent() {
    switch (state) {
      case TimetableCellState.empty:
        return Container(color: Colors.transparent);
      case TimetableCellState.selected:
        return Stack(
          children: [
            // 柔和内阴影
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Icon(
                Icons.add,
                size: 18,
                color: TimetableColors.accent.withValues(alpha: 0.7),
              ),
            ),
          ],
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
    final subTextColor = isLight
        ? const Color(0xFF5D5D5D).withValues(alpha: 0.8)
        : Colors.white.withValues(alpha: 0.75);

    return Stack(
      children: [
        // 顶部微光
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 16,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        // 内容
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ..._buildTitleLines(course.title, textColor),
              if (course.location != null && course.location!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    course.location!,
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 8,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 按长度自动分行
  List<Widget> _buildTitleLines(String title, Color textColor) {
    final lines = <Widget>[];
    final len = title.length;

    if (len <= 3) {
      lines.add(Text(
        title,
        style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w600, height: 1.1),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    } else if (len == 4) {
      lines.add(Text(
        title.substring(0, 2),
        style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w600, height: 1.1),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
      lines.add(Text(
        title.substring(2),
        style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w600, height: 1.1),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    } else if (len == 5) {
      lines.add(Text(
        title.substring(0, 3),
        style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w600, height: 1.1),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
      lines.add(Text(
        title.substring(3),
        style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w600, height: 1.1),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    } else {
      lines.add(Text(
        title,
        style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w600, height: 1.1),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ));
    }

    return lines;
  }
}
