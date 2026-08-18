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
        return const BoxDecoration();
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
        LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth - 4; // 减去 horizontal padding
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ..._buildTitleLines(course.title, textColor, maxWidth),
                  if (course.location != null && course.location!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        course.location!,
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 8,
                          height: 1.1,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  /// 最多 3 行、每行最多 3 字，最多容纳 9 字；超过则第 9 位变 …
  /// 如果塞不下 3 字，会自动缩小字号直到放得下（最低 8）
  List<Widget> _buildTitleLines(String title, Color textColor, double maxWidth) {
    final len = title.length;
    if (len == 0) return [];

    const int maxChars = 9;

    // 初始字号
    double fontSize;
    if (len <= 3) {
      fontSize = 12;
    } else if (len <= 6) {
      fontSize = 11;
    } else {
      fontSize = 10;
    }

    // 如果塞不下 3 个字，逐级缩小（每次 0.5），最低到 8
    // 中文字实际渲染宽度 ≈ fontSize * 1.15，3 字 ≈ fontSize * 3.45
    while (fontSize > 8 && fontSize * 3.45 > maxWidth) {
      fontSize -= 0.5;
    }

    final textStyle = TextStyle(
      color: textColor,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: 1.1,
    );

    // 超过 9 字：前 8 字正常，第 9 位换成 …
    final String display =
        len > maxChars ? '${title.substring(0, maxChars - 1)}…' : title;

    // 把 display 尽量均匀地分到 1~3 行，每行最多 3 字
    final lineTexts = _splitEvenly(display, maxCharsPerLine: 3);
    return lineTexts
        .map((t) => Text(t, style: textStyle, maxLines: 1, overflow: TextOverflow.clip))
        .toList();
  }

  /// 将字符串尽量均匀分成多行，每行不超过 maxCharsPerLine，最多 3 行
  List<String> _splitEvenly(String text, {required int maxCharsPerLine}) {
    final len = text.length;
    if (len <= maxCharsPerLine) return [text];

    // 确定行数（1~3）
    final lineCount = len <= maxCharsPerLine * 2 ? 2 : 3;
    final base = len ~/ lineCount;
    final extra = len % lineCount; // 前几行多 1 个字

    final lines = <String>[];
    int start = 0;
    for (int i = 0; i < lineCount; i++) {
      final count = base + (i < extra ? 1 : 0);
      lines.add(text.substring(start, start + count));
      start += count;
    }
    return lines;
  }
}
