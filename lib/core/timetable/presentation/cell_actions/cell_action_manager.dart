// cell 交互策略 —— 策略模式（fr 28 重构）
//
// 不同模式对"编辑 cell"给出完全不同的 UI 与数据通路：
// - 课表模式（学校/通用）：直接编辑 CourseItem（课程名/地点/老师）
// - 追剧模式：路由到剧模型编辑（课程由剧模型自动派生，直接编辑会被覆盖）
//
// 新增模式 = 新增一个 CellActionStrategy 实现并在
// CellActionManager.strategyFor 登记，timetable_page 零改动。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import 'school_cell_actions.dart';
import 'anime_cell_actions.dart';

export 'school_cell_actions.dart';
export 'anime_cell_actions.dart';

/// 策略回调页面/读 store 所需的最小依赖（不持有页面状态）
class CellActionContext {
  final BuildContext context;
  final WidgetRef ref;

  /// 更新页面选中 cell 状态（传 null 清除）
  final void Function(String? selectedKey) onSelectionChanged;

  const CellActionContext({
    required this.context,
    required this.ref,
    required this.onSelectionChanged,
  });
}

/// cell 坐标定位 + 触发意图（focusCourse 非空 = 编辑已有课程，空 = 添加）
class CellTarget {
  final int cycleIndex;
  final int dayOfCycle;
  final int slotIndex;
  final String cellKey; // 'd{day}_s{slot}'
  final CourseItem? focusCourse;

  const CellTarget({
    required this.cycleIndex,
    required this.dayOfCycle,
    required this.slotIndex,
    required this.cellKey,
    this.focusCourse,
  });
}

/// cell 操作策略抽象：添加/编辑 cell 的统一入口
abstract class CellActionStrategy {
  Future<void> openEditor(CellActionContext ctx, CellTarget target);
}

/// cell 管理器：按 config 模式路由到对应策略。
///
/// 页面只与本类交互，不感知任何模式分支：
/// ```dart
/// CellActionManager().openEditor(ctx, target, config);
/// ```
class CellActionManager {
  /// 模式 → 策略（新增模式在此登记）
  CellActionStrategy strategyFor(TimetableConfig config) {
    if (config.isAnimeMode) return AnimeCellStrategy();
    return SchoolCellStrategy();
  }

  /// 触发：添加/编辑 cell（按当前模式分派）
  Future<void> openEditor(
    CellActionContext ctx,
    CellTarget target,
    TimetableConfig config,
  ) {
    return strategyFor(config).openEditor(ctx, target);
  }
}
