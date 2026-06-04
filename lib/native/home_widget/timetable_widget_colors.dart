/// 课表小组件颜色映射
/// 与 TimetableColors.courseColors 保持一致（莫兰迪色系），保证视觉统一
class TimetableWidgetColors {
  /// 8 个莫兰迪色（按 seed % 8 索引），与 TimetableColors.courseColors 一一对应
  static const List<String> palette = [
    '#8B9DC3', // 灰蓝
    '#9E8FA8', // 灰紫
    '#B58AA5', // 灰粉
    '#C49A8B', // 灰橘
    '#A8C4A2', // 灰绿
    '#7FAAAA', // 灰青
    '#A5B5C4', // 雾蓝
    '#C4B5A0', // 灰棕
  ];

  static String forSeed(int seed) {
    if (palette.isEmpty) return '#9E9E9E';
    final i = seed.abs() % palette.length;
    return palette[i];
  }
}
