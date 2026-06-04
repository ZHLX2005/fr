import 'dart:convert';
import '../../core/timetable/domain/models.dart';
import 'timetable_widget_colors.dart';

/// 桌面课表小组件数据
///
/// 设计原则：
/// - 整个完整数据序列化为 JSON 一次性写入 SharedPreferences，Kotlin 端按 JSON 解析
/// - 课程按"当前周"过滤后再推 widget：每门课有 `visibleInCycles` 列表，
///   只把当前 cycleIndex 下 `isVisibleInCycle()` 为 true 的课程推给桌面
/// - 固定 7 列 × 5 行（daysPerCycle 截断到 7，slotsPerDay 截断到 5；超出范围留空）
class TimetableWidgetData {
  /// 截断上限：列=7（周一到周日），行=5
  static const int maxDays = 7;
  static const int maxSlots = 5;

  /// 课表起始日期 ISO（"YYYY-MM-DD"），用于 Kotlin 端按今天日期计算 dayOfCycle
  final String startDateIso;

  /// 周期内的天数（<=7），超出部分不渲染
  final int daysPerCycle;

  /// 每天的节数（<=5），超出部分不渲染
  final int slotsPerDay;

  /// 35 个槽位的课程数据（按 dayOfCycle * 5 + slotIndex 索引）
  /// 槽位顺序：day0_slot0, day0_slot1, ..., day0_slot4, day1_slot0, ...
  final List<TimetableCellData> cells;

  const TimetableWidgetData({
    required this.startDateIso,
    required this.daysPerCycle,
    required this.slotsPerDay,
    required this.cells,
  });

  /// 从 TimetableConfig + items 构建
  ///
  /// - 取前 7 列、5 行
  /// - 超出 daysPerCycle / slotsPerDay 的位置留空
  /// - 每个 cellKey 取该位置在 [currentCycleIndex] 周可见的第一门课程；
  ///   都不在该周可见则留空
  /// - [currentCycleIndex] 为 null 时（今天不在课表周期范围内），
  ///   退回到"不过滤"，仍展示第一条课程，保证非空时 widget 不会全黑
  factory TimetableWidgetData.fromStore({
    required TimetableConfig config,
    required Map<String, List<CourseItem>> items,
    int? currentCycleIndex,
  }) {
    final clampedDays = config.daysPerCycle.clamp(0, maxDays);
    final clampedSlots = config.slotsPerDay.clamp(0, maxSlots);

    final cells = <TimetableCellData>[];
    for (int day = 0; day < maxDays; day++) {
      for (int slot = 0; slot < maxSlots; slot++) {
        if (day >= clampedDays || slot >= clampedSlots) {
          cells.add(TimetableCellData.empty);
          continue;
        }
        final key = 'd${day}_s$slot';
        final list = items[key];
        if (list == null || list.isEmpty) {
          cells.add(TimetableCellData.empty);
          continue;
        }

        // 在当前周过滤；都不匹配则留空
        final cycleIdx = currentCycleIndex;
        final visible = cycleIdx == null
            ? list
            : list.where((c) => c.isVisibleInCycle(cycleIdx)).toList();
        if (visible.isEmpty) {
          cells.add(TimetableCellData.empty);
          continue;
        }
        final course = visible.first;
        cells.add(
          TimetableCellData(
            title: course.title,
            location: course.location,
            teacher: course.teacher,
            color: TimetableWidgetColors.forSeed(course.colorSeed ?? 0),
          ),
        );
      }
    }

    return TimetableWidgetData(
      startDateIso: config.startDateIso,
      daysPerCycle: clampedDays,
      slotsPerDay: clampedSlots,
      cells: cells,
    );
  }

  /// 序列化为 JSON 字符串
  String toJsonString() {
    return json.encode({
      'startDateIso': startDateIso,
      'daysPerCycle': daysPerCycle,
      'slotsPerDay': slotsPerDay,
      'cells': cells.map((c) => c.toMap()).toList(),
    });
  }

  /// 空数据（未配置时）
  static final empty = TimetableWidgetData(
    startDateIso: '1970-01-01',
    daysPerCycle: 0,
    slotsPerDay: 0,
    cells: List.filled(maxDays * maxSlots, TimetableCellData.empty),
  );
}

/// 单个课程格子数据
class TimetableCellData {
  /// 课程标题（空字符串表示无课）
  final String title;
  final String? location;
  final String? teacher;

  /// 颜色 hex（含 #），用于背景
  final String color;

  const TimetableCellData({
    required this.title,
    this.location,
    this.teacher,
    required this.color,
  });

  static const empty = TimetableCellData(title: '', color: '');

  bool get isEmpty => title.isEmpty;

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'location': location ?? '',
      'teacher': teacher ?? '',
      'color': color,
    };
  }
}
