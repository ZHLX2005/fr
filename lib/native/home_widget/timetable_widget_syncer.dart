import 'package:flutter/foundation.dart';
import '../../core/timetable/domain/models.dart';
import 'timetable_widget_data.dart';
import 'timetable_widget_service.dart';

/// 课表 → 桌面小组件同步器
///
/// 职责单一：接收 (config, items) 快照，转换为 [TimetableWidgetData] 并触发推送。
/// 由 [TimetableStore] 通过依赖注入持有，从而把"推 widget"逻辑隔离在存储层之外。
///
/// 设计要点：
/// - 接口式设计：只暴露 [sync]，业务方不感知底层是 SharedPreferences 还是别的通道
/// - 弱依赖 widget：可被替换为 fake/noop 实现用于单测
/// - 不做节流：调用方负责频率（store 只在状态变更后调一次）
abstract class TimetableWidgetSyncer {
  /// 把当前课表快照推送到桌面小组件
  Future<void> sync({
    required TimetableConfig config,
    required Map<String, List<CourseItem>> items,
  });
}

/// 默认实现：直接走 [TimetableWidgetService]（写 SharedPreferences + 通知原生）
class DefaultTimetableWidgetSyncer implements TimetableWidgetSyncer {
  const DefaultTimetableWidgetSyncer();

  @override
  Future<void> sync({
    required TimetableConfig config,
    required Map<String, List<CourseItem>> items,
  }) async {
    try {
      // 从 config 拿今天所在周期，作为过滤课程的依据；
      // 课表里同一格可能有 "w1,3,5" 和 "w2,4,6" 两种课程，必须按当前周筛掉错的那门
      final currentCycleIndex = config.todayCycleIndex;
      final data = TimetableWidgetData.fromStore(
        config: config,
        items: items,
        currentCycleIndex: currentCycleIndex,
      );
      await TimetableWidgetService.updateTimetableWidget(data);
    } catch (e, stack) {
      // 同步失败不应影响主流程（store 已经写完 Hive）
      debugPrint('[TimetableWidgetSyncer] sync failed: $e\n$stack');
    }
  }
}

/// 空实现：用于单测或禁用 widget 同步的场景
class NoopTimetableWidgetSyncer implements TimetableWidgetSyncer {
  const NoopTimetableWidgetSyncer();

  @override
  Future<void> sync({
    required TimetableConfig config,
    required Map<String, List<CourseItem>> items,
  }) async {}
}
