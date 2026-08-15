import 'package:flutter/material.dart';

import '../timetable_editor_dialog.dart';
import '../timetable_store.dart';
import 'cell_action_manager.dart';

/// 课表模式（学校/通用）cell 策略：直接编辑 CourseItem。
///
/// 打开课程编辑对话框（课程名/地点/老师），读写课表课程本身。
class SchoolCellStrategy implements CellActionStrategy {
  @override
  Future<void> openEditor(CellActionContext ctx, CellTarget target) async {
    // 从 store 获取该 cellKey 的所有课程
    final courses = ctx.ref.read(TimetableStore.cellProvider(target.cellKey));

    // 清除选中状态
    ctx.onSelectionChanged(null);

    // 显示居中的对话框
    await showDialog(
      context: ctx.context,
      barrierColor: Colors.black26,
      builder: (dialogCtx) => TimetableEditorDialog(
        dayOfCycle: target.dayOfCycle,
        slotIndex: target.slotIndex,
        cycleIndex: target.cycleIndex,
        cellKey: target.cellKey,
        existingCourses: courses,
        focusCourse: target.focusCourse,
        onClose: () => Navigator.pop(dialogCtx),
      ),
    );
  }
}
