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
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: _backgroundColor(theme),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
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
        return _getCourseColor(seed).withValues(alpha: 0.88);
    }
  }

  Color _getCourseColor(int seed) {
    // 柔和色系 - 中等饱和度
    final colors = [
      const Color(0xFF7B9FCC), // 柔蓝
      const Color(0xFF9B8FC4), // 柔紫
      const Color(0xFFC49AB0), // 柔粉
      const Color(0xFFD4AA96), // 柔橘
      const Color(0xFF98C49A), // 柔绿
      const Color(0xFF7EAAAA), // 柔青
      const Color(0xFF96B5C4), // 雾蓝
      const Color(0xFFD4B59A), // 柔棕
    ];
    return colors[seed % colors.length];
  }

  Border? _border(ThemeData theme) {
    switch (state) {
      case TimetableCellState.empty:
        return null;
      case TimetableCellState.selected:
        return null;
      case TimetableCellState.filled:
        return Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        );
    }
  }

  List<BoxShadow>? _boxShadow(ThemeData theme) {
    if (state != TimetableCellState.filled) return null;
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.06),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  Widget _buildContent(ThemeData theme) {
    switch (state) {
      case TimetableCellState.empty:
        // 空白：透明但有点击区域
        return Container(color: Colors.transparent);
      case TimetableCellState.selected:
        return Center(
          child: Icon(
            Icons.add,
            size: 22,
            color: TimetableColors.accentLight,
          ),
        );
      case TimetableCellState.filled:
        if (course == null) return const SizedBox.shrink();
        return _buildCourseContent(theme);
    }
  }

  Widget _buildCourseContent(ThemeData theme) {
    final color = _getCourseColor(course!.colorSeed ?? 0);
    final isLight = color.computeLuminance() > 0.55;
    final textColor = isLight ? const Color(0xFF3D3D3D) : Colors.white;
    final subTextColor = isLight ? const Color(0xFF5D5D5D) : Colors.white70;

    return Stack(
      children: [
        // 顶部微光
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 20,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        // 内容
        Padding(
          padding: const EdgeInsets.all(8),
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
        ),
      ],
    );
  }
}
