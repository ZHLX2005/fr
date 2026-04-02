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
        return theme.colorScheme.primaryContainer.withValues(alpha: 0.4);
      case TimetableCellState.filled:
        final seed = course?.colorSeed ?? 0;
        return _getCourseColor(seed).withValues(alpha: 0.65);
    }
  }

  Color _getCourseColor(int seed) {
    // 莫兰迪色系 - 低饱和度
    final colors = [
      const Color(0xFF8B9DC3), // 灰蓝
      const Color(0xFF9E8FA8), // 灰紫
      const Color(0xFFB58AA5), // 灰粉
      const Color(0xFFC49A8B), // 灰橘
      const Color(0xFFA8C4A2), // 灰绿
      const Color(0xFF7FAAAA), // 灰青
      const Color(0xFFA5B5C4), // 雾蓝
      const Color(0xFFC4B5A0), // 灰棕
    ];
    return colors[seed % colors.length];
  }

  Border? _border(ThemeData theme) => null;

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
            color: theme.colorScheme.primary.withValues(alpha: 0.6),
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

    return Container(
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
    );
  }
}
